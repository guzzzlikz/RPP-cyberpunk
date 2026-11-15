-- rpp_animwheel, клиент: окно колеса (WebUI), клавиша U, каталог анимаций
-- из open77_animations, проигрывание и сохранение слотов.
local RESOURCE = GetCurrentResourceName()
local SLOT_COUNT = 12
local STORE_KEY = "rpp.animwheel.slots"

local page, ready, open = nil, false, false
local queue = {}
local catalog, byId = {}, {}
local slots = {}          -- [1..12] = { profile = id, clip = clip } | nil
local lastToggle = 0
local loading = false

local function log(text) print("[" .. RESOURCE .. "] " .. text) end
local function clock() return Open77.time.monotonic() * 1000 end

local function send(event, payload)
    if not page then return end
    if not ready then queue[#queue + 1] = { event, payload }; return end
    page:send("wheel:" .. event, payload or {})
end

local function notify(text)
    pcall(TriggerEvent, "chat:addMessage", { type = "system", author = "АНИМАЦИИ", text = text })
end

-- ---------------------------------------------------------------------------
-- Слоты: «profile|clip;profile|clip;;...» в kvp клиента (без JSON).
-- ---------------------------------------------------------------------------
local function loadSlots()
    slots = {}
    local ok, text = pcall(Open77.kvp.get, STORE_KEY, "")
    if not ok or type(text) ~= "string" then return end
    local index = 0
    for part in (text .. ";"):gmatch("([^;]*);") do
        index = index + 1
        if index > SLOT_COUNT then break end
        local profile, clip = part:match("^([%w_%.%-]+)|([%w_%.%-]*)$")
        if profile then slots[index] = { profile = profile, clip = clip ~= "" and clip or nil } end
    end
end

local function saveSlots()
    local parts = {}
    for index = 1, SLOT_COUNT do
        local slot = slots[index]
        parts[index] = slot and (slot.profile .. "|" .. (slot.clip or "")) or ""
    end
    local ok, stored, reason = pcall(Open77.kvp.set, STORE_KEY, table.concat(parts, ";"))
    if not ok or stored == false then log("slots not saved: " .. tostring(ok and reason or stored)) end
end

local function slotView()
    local list = {}
    for index = 1, SLOT_COUNT do
        local slot = slots[index]
        if slot then
            local profile = byId[slot.profile]
            list[index] = { profile = slot.profile, label = profile and profile.label or slot.profile,
                category = profile and profile.category or "", missing = profile == nil }
        else
            list[index] = false
        end
    end
    return list
end

local function pushSlots() send("slots", { slots = slotView() }) end

-- ---------------------------------------------------------------------------
-- Каталог
-- ---------------------------------------------------------------------------
local function await(pending, err)
    if not pending then return nil, err or "resource_stopped" end
    return pending:await()
end

local function sendCatalog()
    -- Сообщение WebUI ограничено по числу узлов: каталог уходит пачками.
    local BATCH = 20
    local total = math.max(1, math.ceil(#catalog / BATCH))
    for batch = 1, total do
        local values = {}
        for i = (batch - 1) * BATCH + 1, math.min(batch * BATCH, #catalog) do
            local p = catalog[i]
            values[#values + 1] = { id = p.id, label = tostring(p.label or p.id), category = p.category or "",
                once = p.kind == "layer" and p.mode == "once", walks = p.kind == "layer" and p.locomotion ~= false,
                placement = p.placement or "standing",
                -- amb_* — фоновые анимации NPC из игры, привязанные к месту (гриль,
                -- стойка, станок): без него персонаж застывает в позе.
                ambient = tostring(p.id):sub(1, 4) == "amb_" }
        end
        send("catalog", { batch = batch, total = total, profiles = values })
    end
end

local function refresh()
    if loading then return end
    loading = true
    CreateThread(function()
        local values, err = await(Open77.animations.list())
        loading = false
        if not values then log("catalog failed: " .. tostring(err)); return end
        catalog, byId = values, {}
        for _, profile in ipairs(values) do byId[profile.id] = profile end
        sendCatalog()
        pushSlots()
    end)
end

-- ---------------------------------------------------------------------------
-- Проигрывание
-- ---------------------------------------------------------------------------
local ERRORS = {
    player_not_ready = "Персонаж ещё загружается.",
    player_not_alive = "Мёртвые не танцуют.",
    player_in_vehicle = "Сначала выйдите из машины.",
    animation_owned = "Сначала остановите текущее действие.",
    interrupted = "Анимация прервана: встаньте ровно и уберите оружие.",
    timeout = "Анимация не успела начаться, попробуйте ещё раз.",
    unknown_profile = "Эта анимация недоступна на сервере.",
}

local playSerial = 0

-- Вид от третьего лица. Анимация-воркспот показывается через временный вид от
-- 3-го лица, и Open77 ждёт, пока для него оденется отдельное тело. На медленном
-- кадре (15 FPS) тело одевалось ~2 с, Open77 не дожидался и возвращал вид от
-- 1-го лица («the incoming view did not become ready») — свою анимацию игрок
-- не видел, персонаж «просто стоял». Поэтому колесо само включает вид от 3-го
-- лица заранее, ждёт его, а после анимации возвращает 1-е лицо, если меняло его.
local switchedView = false

local function perspective(name, ...)
    local ok, result = pcall(function(...)
        local promise = Open77.exports.call("open77_perspective", name, ...)
        if not promise then return nil end
        return promise:await()
    end, ...)
    return ok and result or nil
end

local function ensureThirdPerson()
    if perspective("get") ~= "fpp" then return end
    if not perspective("set", "tps") then return end
    switchedView = true
    local deadline = Open77.time.monotonic() + 8
    while perspective("get") ~= "tps" and Open77.time.monotonic() < deadline do Wait(200) end
    Wait(2500) -- тело для вида от 3-го лица одевается ~2 с на медленном кадре
end

local function restoreView()
    if not switchedView then return end
    switchedView = false
    perspective("set", "fpp")
end

local function localPlayer()
    local ok, state = pcall(Open77.network.status)
    return ok and type(state) == "table" and tonumber(state.playerId) or nil
end

local starting = false -- идёт запуск новой анимации: остановка старой не возвращает вид

AddEventHandler("onPlayerAnimationChanged", function(player, state)
    if tonumber(player) ~= localPlayer() then return end
    if type(state) == "table" and state.active then return end
    if starting then return end
    CreateThread(restoreView)
end)

-- Текущая анимация: nil, если ничего не играет. Профиль и клип — в steps[step+1].
local function activeState()
    local state = await(Open77.animations.state())
    if type(state) ~= "table" or state.active == false then return nil end
    local step = type(state.steps) == "table" and state.steps[(tonumber(state.step) or 0) + 1] or nil
    return { profile = step and step.profile or state.profile, clip = step and step.clip or state.clip }
end

local function play(profileId)
    local profile = byId[profileId]
    if not profile then notify(ERRORS.unknown_profile); return end
    playSerial = playSerial + 1
    local serial = playSerial
    CreateThread(function()
        starting = true
        local function done() if serial == playSerial then starting = false end end
        -- Новая анимация заменяет текущую: если что-то играет, сначала
        -- останавливаем и ждём, пока остановка дойдёт (до 1,5 с).
        local current = activeState()
        if current then
            await(Open77.animations.cancel())
            local deadline = Open77.time.monotonic() + 1.5
            while activeState() and Open77.time.monotonic() < deadline do Wait(100) end
        end
        if serial ~= playSerial then return done() end
        ensureThirdPerson()
        if serial ~= playSerial then return done() end
        -- Те же параметры, что у команды /anim: только loop, без клипа и
        -- длительности — сервер сам берёт клип профиля по умолчанию.
        local options = { loop = profile.mode ~= "once" }
        local value, err = await(Open77.animations.request(profile.id, options))
        if not value and err ~= "cancelled" then
            log(("play %s failed: %s"):format(profile.id, tostring(err)))
            notify(ERRORS[err] or ("Анимация недоступна: " .. tostring(err)))
            done()
            restoreView()
            return
        end
        done()
        local now = activeState()
        log(("play %s (%s, loop=%s) -> playing %s / %s"):format(profile.id, tostring(profile.kind),
            tostring(options.loop), tostring(now and now.profile), tostring(now and now.clip)))
    end)
end

local function stop()
    playSerial = playSerial + 1
    CreateThread(function() await(Open77.animations.cancel()) end)
end

-- ---------------------------------------------------------------------------
-- Окно
-- ---------------------------------------------------------------------------
local function focus(enabled)
    if page then pcall(page.setFocus, page, enabled, enabled) end
end

local function setOpen(value)
    if value == open then return end
    open = value
    lastToggle = clock()
    if open then
        send("show", {})
        focus(true)
        refresh()
    else
        send("hide", {})
        focus(false)
    end
end

local function ensurePage()
    if page then return true end
    local reason
    page, reason = WebUI.create({
        entry = "web/index.html", layer = "menu",
        width = 1920, height = 1080, fps = 60, zIndex = 745,
        transparent = true, visible = true,
    })
    if not page then log("WebUI failed: " .. tostring(reason)); return false end
    page:on("wheel:ready", function()
        ready = true
        for _, item in ipairs(queue) do page:send("wheel:" .. item[1], item[2] or {}) end
        queue = {}
        if #catalog > 0 then sendCatalog() end
        pushSlots()
    end)
    page:on("wheel:close", function()
        open = false
        lastToggle = clock()
        focus(false)
    end)
    page:on("wheel:play", function(p)
        if type(p) ~= "table" or type(p.profile) ~= "string" then return end
        play(p.profile)
        if p.close then setOpen(false) end
    end)
    page:on("wheel:stop", function() stop(); setOpen(false) end)
    page:on("wheel:assign", function(p)
        local index = type(p) == "table" and tonumber(p.slot)
        if not index or index < 1 or index > SLOT_COUNT or index % 1 ~= 0 then return end
        if p.profile == false or p.profile == nil then
            slots[index] = nil
        else
            local profile = byId[tostring(p.profile)]
            if not profile then return end
            slots[index] = { profile = profile.id, clip = profile.clip }
        end
        saveSlots()
        pushSlots()
    end)
    return true
end

local ok, effective = pcall(RegisterKeyMapping, "rpp_animwheel.open", "Колесо анимаций", "U", function()
    if clock() - lastToggle < 300 then return end
    if not ensurePage() then return end
    setOpen(not open)
end)
if not ok or effective == false then log("key mapping refused: " .. tostring(effective)) end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= RESOURCE then return end
    loadSlots()
    refresh()
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    focus(false)
    page, ready, open = nil, false, false
end)
