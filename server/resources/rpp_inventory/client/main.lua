-- rpp_inventory, клиентская часть: окно инвентаря (WebUI), клавиша I,
-- метки брошенных предметов и подбор. Все решения принимает сервер,
-- клиент только показывает состояние и пересылает действия.
local cfg = RppInventoryConfig
local RESOURCE = GetCurrentResourceName()

local page, ready, open = nil, false, false
local trading = false
local tradeOffers = {} -- [playerId] = true: этот игрок предложил нам обмен
local queue = {}
local lastState = nil
local lastToggle = 0

local function log(text) print("[" .. RESOURCE .. "] " .. text) end
local function clock() return Open77.time.monotonic() * 1000 end

-- ---------------------------------------------------------------------------
-- Окно
-- ---------------------------------------------------------------------------
local function send(event, payload)
    if not page then return end
    if not ready then queue[#queue + 1] = { event, payload }; return end
    local ok, reason = page:send("inv:" .. event, payload or {})
    if ok == false then log("page send " .. event .. " refused: " .. tostring(reason)) end
end

local function focus(enabled)
    if not page then return end
    local ok, reason = page:setFocus(enabled, enabled)
    if ok == false then log("focus refused: " .. tostring(reason)) end
end

local function setOpen(value)
    if value == open then return end
    open = value
    lastToggle = clock()
    if open then
        TriggerServerEvent("rpp_inventory:open")
        send("show", lastState)
        focus(true)
    else
        send("hide")
        focus(false)
    end
end

-- Действия со страницы -> события сервера. Сервер проверяет всё сам.
local ACTIONS = {
    move = function(p) TriggerServerEvent("rpp_inventory:move", p.uid, p.x, p.y) end,
    sort = function() TriggerServerEvent("rpp_inventory:sort") end,
    tradeAdd = function(p) TriggerServerEvent("rpp_inventory:tradeAdd", p.uid) end,
    tradeRemove = function(p) TriggerServerEvent("rpp_inventory:tradeRemove", p.uid) end,
    tradeMoney = function(p) TriggerServerEvent("rpp_inventory:tradeMoney", p.amount) end,
    tradeReady = function(p) TriggerServerEvent("rpp_inventory:tradeReady", p.ready == true) end,
    tradeCancel = function() TriggerServerEvent("rpp_inventory:tradeCancel") end,
    equipWeapon = function(p) TriggerServerEvent("rpp_inventory:equipWeapon", p.uid, p.slot) end,
    equipClothing = function(p) TriggerServerEvent("rpp_inventory:equipClothing", p.uid) end,
    unequip = function(p) TriggerServerEvent("rpp_inventory:unequip", p.where, p.key) end,
    drop = function(p) TriggerServerEvent("rpp_inventory:drop", p.where, p.key) end,
    containerPut = function(p) TriggerServerEvent("rpp_inventory:containerPut", p.uid) end,
    containerTake = function(p) TriggerServerEvent("rpp_inventory:containerTake", p.uid) end,
    containerClose = function() TriggerServerEvent("rpp_inventory:containerClose") end,
}
local inContainer = false

local function ensurePage()
    if page then return true end
    local reason
    page, reason = WebUI.create({
        entry = "web/index.html", layer = "menu",
        width = 1920, height = 1080, fps = 60, zIndex = 740,
        transparent = true, visible = true,
    })
    if not page then
        log("WebUI failed: " .. tostring(reason))
        return false
    end
    page:on("inv:ready", function()
        ready = true
        for _, item in ipairs(queue) do page:send("inv:" .. item[1], item[2] or {}) end
        queue = {}
    end)
    page:on("inv:close", function()
        -- Закрыть окно во время обмена = отменить обмен.
        if trading then TriggerServerEvent("rpp_inventory:tradeCancel") end
        -- Закрыть окно у багажника = закрыть багажник.
        if inContainer then inContainer = false; TriggerServerEvent("rpp_inventory:containerClose") end
        -- Та же клавиша I закрывает окно со страницы и одновременно срабатывает
        -- привязка: окно не должно тут же открыться снова.
        open = false
        lastToggle = clock()
        focus(false)
    end)
    page:on("inv:action", function(payload)
        if not open or type(payload) ~= "table" then return end
        local handler = ACTIONS[payload.type]
        if handler then handler(payload) end
    end)
    return true
end

RegisterNetEvent("rpp_inventory:state", function(state)
    if type(state) ~= "table" then return end
    if state.cyber == nil and lastState then state.cyber = lastState.cyber end
    lastState = state
    if open then send("state", state) end
end)

-- ---------------------------------------------------------------------------
-- Обмен
-- ---------------------------------------------------------------------------
RegisterNetEvent("rpp_inventory:trade", function(trade)
    if type(trade) ~= "table" then return end
    trading = true
    if not ensurePage() then return end
    if not open then setOpen(true) end
    send("trade", trade)
end)

RegisterNetEvent("rpp_inventory:tradeClosed", function(reason)
    trading = false
    send("tradeClosed", { reason = reason })
end)

-- Хранилище (багажник): окно инвентаря с панелью хранилища слева.
RegisterNetEvent("rpp_inventory:container", function(box)
    if type(box) ~= "table" then return end
    inContainer = true
    if not ensurePage() then return end
    if not open then setOpen(true) end
    send("container", box)
end)

RegisterNetEvent("rpp_inventory:containerClosed", function()
    inContainer = false
    send("containerClosed", {})
end)

RegisterNetEvent("rpp_inventory:tradeOffers", function(list)
    tradeOffers = {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if tonumber(id) then tradeOffers[tonumber(id)] = true end
    end
end)

-- ALT-меню на игроке: «Предложить обмен» и «Принять обмен».
local function targetId(context)
    local target = context and context.target
    local id = target and tonumber(target.playerId)
    if not id or target.isLocalPlayer == true then return nil end
    return id
end

exports("canTradeOffer", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    return id ~= nil and not trading and not tradeOffers[id]
end)
exports("selectTradeOffer", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    if not id then return false end
    TriggerServerEvent("rpp_inventory:tradeOffer", id)
    return true
end)
exports("canTradeAccept", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    return id ~= nil and not trading and tradeOffers[id] == true
end)
exports("selectTradeAccept", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    if not id then return false end
    TriggerServerEvent("rpp_inventory:tradeAccept", id)
    return true
end)

local function registerContext()
    local entries = {
        { id = "rpp_trade_offer", label = "Предложить обмен", icon = "interact",
          description = "Обменяться вещами и деньгами. Обмен — только когда оба нажмут «Готов».",
          canInteract = "canTradeOffer", onSelect = "selectTradeOffer" },
        { id = "rpp_trade_accept", label = "Принять обмен", icon = "person",
          description = "Этот игрок предложил вам обмен.",
          canInteract = "canTradeAccept", onSelect = "selectTradeAccept" },
    }
    for _, entry in ipairs(entries) do
        entry.distance = cfg.tradeDistance
        entry.group = "Обмен"
        local pending, reason = Open77.exports.call("open77_contextmenu", "registerPlayers", entry)
        if pending then
            local token
            token, reason = pending:await()
            if token then reason = nil end
        end
        if reason then log("context menu " .. entry.id .. " failed: " .. tostring(reason)) end
    end
end

AddEventHandler("onClientResourceStart", function(name)
    if name == "open77_contextmenu" then CreateThread(registerContext) end
end)

-- ---------------------------------------------------------------------------
-- Клавиша и штатный инвентарь
-- ---------------------------------------------------------------------------
local ok, effective = pcall(RegisterKeyMapping, cfg.key.id, cfg.key.name, cfg.key.key, function()
    if clock() - lastToggle < 350 then return end
    if not ensurePage() then return end
    setOpen(not open)
end)
if not ok or effective == false then log("key mapping refused: " .. tostring(effective)) end

local blocked = {}
local function blockVanilla(active)
    if not cfg.blockVanillaInventory or type(Open77.input) ~= "table" then return end
    local tries = {
        { "setActionBlocked", "Inventory" },
        { "setNativeActionBlocked", "OpenInventoryMenu" },
        { "setNativeActionBlocked", "OpenHubMenu" },
    }
    for _, try in ipairs(tries) do
        local fn = Open77.input[try[1]]
        if type(fn) == "function" then
            local called, result = pcall(fn, try[2], active)
            if called and result ~= false then blocked[try[2]] = active or nil end
        end
    end
end

RegisterCommand("inv", function()
    if not ensurePage() then return end
    setOpen(not open)
end, false)

-- ---------------------------------------------------------------------------
-- Одежда, надетая до первого входа: сервер спрашивает один раз.
-- ---------------------------------------------------------------------------
RegisterNetEvent("rpp_inventory:requestWear", function()
    local slots = {}
    if type(Open77.equipment) == "table" and type(Open77.equipment.registry) == "function" then
        local called, registry = pcall(Open77.equipment.registry)
        if called and type(registry) == "table" then
            for slot, value in pairs(registry) do
                if type(value) == "string" and value ~= "" then slots[slot] = value
                elseif type(value) == "table" and type(value.record) == "string" then slots[slot] = value.record end
            end
        end
    end
    TriggerServerEvent("rpp_inventory:wearSnapshot", slots)
end)

-- ---------------------------------------------------------------------------
-- Брошенные предметы: метка на земле и подсказка «Подобрать» (open77_worldui)
-- ---------------------------------------------------------------------------
local pois = {}       -- [dropId] = handle | "pending"
local wanted = {}     -- [dropId] = drop

local function worldui(name, arg)
    local pending, reason = Open77.exports.call("open77_worldui", name, arg)
    if not pending then return nil, reason end
    return pending:await()
end

local function syncDrops()
    for id, handle in pairs(pois) do
        if not wanted[id] and handle ~= "pending" then
            worldui("remove", handle)
            pois[id] = nil
        end
    end
    for id, drop in pairs(wanted) do
        if pois[id] == nil then
            pois[id] = "pending"
            local result = worldui("create", {
                id = "drop_" .. id,
                position = { x = drop.x, y = drop.y, z = drop.z },
                style = "interaction",
                radius = 0.45,
                -- Метку и подсказку видно только вблизи (cfg.dropMarkerDistance, 3 м).
                maxDistance = cfg.dropMarkerDistance,
                label = "Подобрать: " .. tostring(drop.label),
                key = "E",
                promptDistance = math.max(1.0, math.min(cfg.pickupDistance, cfg.dropMarkerDistance) - 0.3),
                labelHeight = 0.6,
                event = "rpp_inventory:pickupPrompt",
            })
            if type(result) == "table" and result.ok then
                if wanted[id] then pois[id] = result.handle
                else worldui("remove", result.handle); pois[id] = nil end
            else
                pois[id] = nil
                log("drop marker failed: " .. tostring(type(result) == "table" and result.error or result))
            end
        end
    end
end

local syncing, again = false, false
local serverDrops = {}   -- что прислал сервер
local menuBusy = false   -- открыт инвентарь, меню, карта и т. п.: метки спрятаны

local function requestSync()
    wanted = menuBusy and {} or serverDrops
    if syncing then again = true; return end
    syncing = true
    CreateThread(function()
        repeat
            again = false
            wanted = menuBusy and {} or serverDrops
            local called, err = pcall(syncDrops)
            if not called then log("drop sync failed: " .. tostring(err)) end
        until not again
        syncing = false
    end)
end

RegisterNetEvent("rpp_inventory:drops", function(list)
    serverDrops = {}
    for _, drop in ipairs(type(list) == "table" and list or {}) do
        local id = tonumber(drop.id)
        if id and tonumber(drop.x) and tonumber(drop.y) and tonumber(drop.z) then serverDrops[id] = drop end
    end
    requestSync()
end)

-- Пока на экране курсор (инвентарь, пауза, карта, ALT-меню, любое окно),
-- метки «Подобрать» убираются и возвращаются, когда окно закрыто.
CreateThread(function()
    while true do
        Wait(200)
        local busy = open
        if not busy and type(Open77.input) == "table" and type(Open77.input.isCaptured) == "function" then
            local ok, _, cursor = pcall(Open77.input.isCaptured)
            busy = ok and cursor == true
        end
        if busy ~= menuBusy then
            menuBusy = busy
            requestSync()
        end
    end
end)

AddEventHandler("rpp_inventory:pickupPrompt", function()
    TriggerServerEvent("rpp_inventory:pickup")
end)

-- ---------------------------------------------------------------------------
-- Жизненный цикл
-- ---------------------------------------------------------------------------
local function worldPlayable()
    if type(Open77.session) ~= "table" or type(Open77.session.characterBootstrap) ~= "function" then return true end
    local called, bootstrap = pcall(Open77.session.characterBootstrap)
    return called and type(bootstrap) == "table" and bootstrap.phase == "ready"
end

-- Сервер выдаёт экипированное оружие заново. Ждём, пока сессия снимет
-- штатный набор игры, иначе выданное оружие пропадёт вместе с ним.
local helloToken = 0
local function hello()
    helloToken = helloToken + 1
    local token = helloToken
    CreateThread(function()
        local started = clock()
        while not worldPlayable() and clock() - started < 60000 do Wait(500) end
        Wait(3000)
        if token == helloToken then TriggerServerEvent("rpp_inventory:hello") end
    end)
end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= RESOURCE then return end
    blockVanilla(true)
    hello()
    CreateThread(registerContext)
end)

AddEventHandler("open77:worldReady", function()
    -- Новый мир: метки и оружие выставляются заново.
    pois = {}
    blockVanilla(true)
    hello()
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    for action in pairs(blocked) do
        for _, fn in ipairs({ "setActionBlocked", "setNativeActionBlocked" }) do
            if type(Open77.input) == "table" and type(Open77.input[fn]) == "function" then
                pcall(Open77.input[fn], action, false)
            end
        end
    end
    if page then pcall(page.setFocus, page, false, false) end
    page, ready, open = nil, false, false
end)
