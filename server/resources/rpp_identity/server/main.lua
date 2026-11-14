-- rpp_identity, серверная часть. Сервер — единственный источник правды:
-- он выдаёт номера, проверяет имена и дистанцию знакомства и решает, какую
-- подпись каждый игрок видит над каждым другим.
local cfg = RppIdentityConfig
local RESOURCE = GetCurrentResourceName()

local online = {}      -- [playerId] = { guid, citizen = {id,first,last}|nil, known = {[guid]=true} }
local stage = {}       -- [playerId] = nil | "appearance" | "name"
local created = {}     -- [playerId] = true, если персонаж создан в редакторе в этой сессии
local offers = {}      -- [targetId] = { [fromId] = expiresAt }
local lastIntroduce = {} -- [playerId] = monotonic seconds
local loading = {}     -- [playerId] = true, пока паспорт читается из базы
local dbReady = false  -- true, если работает MySQL (без неё нет редактора внешности)

local function log(text) print("[" .. RESOURCE .. "] " .. text) end
local function now() return Open77.time.monotonic() end

local function notify(player, kind, message, title)
    local ok, err = pcall(Open77.notifications.send, player, {
        type = kind, title = title or "Паспорт", message = message,
        durationMs = kind == "error" and 6000 or 8000,
    })
    if not ok then log("notification failed: " .. tostring(err)) end
end

local function chat(player, text)
    TriggerClientEvent("chat:addMessage", player, { type = "system", text = text })
end

local function reply(player, raw, ok, message)
    if player == nil or player <= 0 then print(message); return end
    TriggerClientEvent("open77:command:result", player, raw, ok, message)
end

local function fullName(citizen) return citizen.first .. " " .. citizen.last end

-- ---------------------------------------------------------------------------
-- Игроки онлайн
-- ---------------------------------------------------------------------------
-- Читает паспорт из хранилища. Ждёт базу: только внутри CreateThread.
local function load(playerId)
    if not playerId then return nil end
    while loading[playerId] do Wait(20) end
    if online[playerId] then return online[playerId] end
    local guid = GetPlayerIdentifier(playerId)
    if guid == nil or guid == "" then return nil end
    loading[playerId] = true
    local ok, citizen, known = pcall(function()
        return RppStore.getCitizen(guid), RppStore.getKnown(guid)
    end)
    loading[playerId] = nil
    if not ok then
        log("passport load failed for " .. tostring(playerId) .. ": " .. tostring(citizen))
        return nil
    end
    local entry = { guid = guid, citizen = citizen, known = known }
    online[playerId] = entry
    return entry
end

--- Что `viewer` видит над `target`.
local function labelFor(viewer, target)
    local t = online[target]
    if not t or not t.citizen then
        return { playerId = target, label = cfg.unregisteredLabel, registered = false, known = false }
    end
    local v = online[viewer]
    if v and v.known[t.guid] then
        return { playerId = target, label = fullName(t.citizen), registered = true, known = true,
            citizenId = t.citizen.id }
    end
    return { playerId = target, label = RppNames.citizenTag(t.citizen.id), registered = true, known = false,
        citizenId = t.citizen.id }
end

local function pushLabels(viewer)
    if not online[viewer] then return end
    local list = {}
    for target in pairs(online) do
        if target ~= viewer then list[#list + 1] = labelFor(viewer, target) end
    end
    TriggerClientEvent("rpp_identity:labels", viewer, list)
end

local function pushAll()
    for viewer in pairs(online) do pushLabels(viewer) end
end

local function pushSelf(player)
    local entry = online[player]
    if not entry then return end
    TriggerClientEvent("rpp_identity:self", player, player, entry.citizen)
end

-- ---------------------------------------------------------------------------
-- Регистрация: кастомизация -> имя -> номер
-- ---------------------------------------------------------------------------
local function askName(player)
    stage[player] = "name"
    TriggerClientEvent("rpp_identity:askName", player)
end

local function startRegistration(player)
    local entry = load(player)
    if not entry then return false, "Не удалось определить аккаунт. Переподключитесь." end
    if entry.citizen then return false, "У вас уже есть паспорт: " .. RppNames.citizenTag(entry.citizen.id) end
    if stage[player] ~= nil then
        -- Повторный вызов (например, /register после закрытия формы): просто
        -- показываем текущий шаг ещё раз.
        if stage[player] == "name" then askName(player) end
        return true
    end
    if cfg.customizeBeforeName and dbReady and not created[player] then
        stage[player] = "appearance"
        TriggerClientEvent("rpp_identity:openAppearance", player, cfg.appearanceMode)
    else
        askName(player)
    end
    return true
end

-- Игрок полностью загрузился в мир: можно начинать регистрацию.
RegisterNetEvent("open77:session:gameplayReady", function()
    local player = source
    CreateThread(function()
        Wait(1500)
        local entry = load(player)
        if entry and not entry.citizen and stage[player] == nil then startRegistration(player) end
    end)
end)

-- Новый игрок только что создал персонажа в редакторе open77_appearance
-- (бывает только при включённой MySQL). Повторно редактор не открываем.
AddEventHandler("open77:appearance:characterCreated", function(player)
    player = tonumber(player)
    if not player then return end
    created[player] = true
    if stage[player] == "appearance" then askName(player) end
end)

-- Игрок сохранил внешность в редакторе.
AddEventHandler("open77:appearance:saved", function(player)
    player = tonumber(player)
    if player and stage[player] == "appearance" then askName(player) end
end)

-- Клиент сообщает, что редактор закрыт без сохранения, отклонён или не открылся.
RegisterNetEvent("rpp_identity:appearanceDone", function(reason)
    local player = source
    if stage[player] ~= "appearance" then return end
    log(("player %s skipped appearance: %s"):format(tostring(player), tostring(reason)))
    askName(player)
end)

RegisterNetEvent("rpp_identity:submitName", function(first, last)
    local player = source
    CreateThread(function()
    local entry = online[player]
    if not entry then return end
    if entry.citizen then
        return TriggerClientEvent("rpp_identity:registered", player, entry.citizen)
    end
    if stage[player] == "saving" then return end
    if stage[player] ~= "name" then
        return TriggerClientEvent("rpp_identity:nameRejected", player, "form", "Сейчас нельзя ввести имя.")
    end
    local cleanFirst, firstError = RppNames.validate(first)
    if not cleanFirst then
        return TriggerClientEvent("rpp_identity:nameRejected", player, "first", RppNames.errorText(firstError))
    end
    local cleanLast, lastError = RppNames.validate(last)
    if not cleanLast then
        return TriggerClientEvent("rpp_identity:nameRejected", player, "last", RppNames.errorText(lastError))
    end

    stage[player] = "saving" -- двойной клик «Подтвердить» не создаст два паспорта
    local citizen, saveError = RppStore.createCitizen(entry.guid, cleanFirst, cleanLast)
    if not citizen then
        stage[player] = "name"
        log("citizen save failed: " .. tostring(saveError))
        return TriggerClientEvent("rpp_identity:nameRejected", player, "form", "Ошибка сервера. Попробуйте ещё раз.")
    end
    local id = citizen.id
    entry.citizen = citizen
    stage[player] = nil
    log(("player %s registered as %s (%s)"):format(tostring(player), RppNames.citizenTag(id), fullName(citizen)))
    TriggerClientEvent("rpp_identity:registered", player, citizen)
    pushSelf(player)
    pushAll()
    TriggerEvent("rpp_identity:registered", player, citizen)
    end)
end)

-- ---------------------------------------------------------------------------
-- Знакомство
-- ---------------------------------------------------------------------------
local function distanceOk(a, b)
    local ok, pa = pcall(Open77.players.position, a)
    local ok2, pb = pcall(Open77.players.position, b)
    -- Позиция недоступна (нет прав или игрок ещё не в мире): дистанцию уже
    -- проверило контекстное меню на клиенте, сервер не блокирует.
    if not ok or not ok2 or type(pa) ~= "table" or type(pb) ~= "table" then return true end
    if pa.bucket ~= nil and pb.bucket ~= nil and pa.bucket ~= pb.bucket then return false end
    local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
    local limit = cfg.introduceDistance + 2.0 -- запас на задержку сети
    return dx * dx + dy * dy + dz * dz <= limit * limit
end

local function makeKnown(a, b)
    local ea, eb = online[a], online[b]
    ea.known[eb.guid] = true
    eb.known[ea.guid] = true
    RppStore.addKnown(ea.guid, eb.guid, ea.known)
    RppStore.addKnown(eb.guid, ea.guid, eb.known)
    if offers[a] then offers[a][b] = nil end
    if offers[b] then offers[b][a] = nil end
    pushLabels(a)
    pushLabels(b)
    notify(a, "success", "Вы познакомились: " .. fullName(eb.citizen), "Знакомство")
    notify(b, "success", "Вы познакомились: " .. fullName(ea.citizen), "Знакомство")
    TriggerEvent("rpp_identity:introduced", a, b)
end

local function pendingOffer(target, from)
    local list = offers[target]
    local expires = list and list[from]
    if expires and expires > now() then return true end
    if list then list[from] = nil end
    return false
end

local function introduce(player, target)
    local me, other = online[player], online[target]
    if not me or not me.citizen then return false, "Сначала получите паспорт: /register" end
    if not other then return false, "Игрок недоступен." end
    if not other.citizen then return false, "У этого человека ещё нет паспорта." end
    if player == target then return false, "Нельзя познакомиться с собой." end
    if me.known[other.guid] then return false, "Вы уже знакомы." end
    if not distanceOk(player, target) then return false, "Подойдите ближе." end

    -- Встречное предложение уже есть: это согласие.
    if pendingOffer(player, target) then
        makeKnown(player, target)
        return true
    end
    offers[target] = offers[target] or {}
    offers[target][player] = now() + cfg.offerSeconds
    notify(player, "info", ("Вы предложили знакомство: %s. Ждём ответа."):format(RppNames.citizenTag(other.citizen.id)),
        "Знакомство")
    notify(target, "info", ("%s хочет познакомиться. ALT + клик по нему -> «Познакомиться» или /accept (%d с)")
        :format(RppNames.citizenTag(me.citizen.id), cfg.offerSeconds), "Знакомство")
    return true
end

RegisterNetEvent("rpp_identity:introduce", function(target)
    local player = source
    target = tonumber(target)
    if not target then return end
    local t = now()
    if lastIntroduce[player] and t - lastIntroduce[player] < cfg.introduceCooldownSeconds then return end
    lastIntroduce[player] = t
    CreateThread(function()
        local ok, message = introduce(player, target)
        if not ok then notify(player, "warning", message, "Знакомство") end
    end)
end)

local function latestOffer(player)
    local best, bestExpires
    for from, expires in pairs(offers[player] or {}) do
        if expires > now() and online[from] and (not bestExpires or expires > bestExpires) then
            best, bestExpires = from, expires
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Команды
-- ---------------------------------------------------------------------------
RegisterCommand("passport", function(player, _, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "passport — команда игрока") end
    CreateThread(function()
    local entry = load(player)
    if not entry or not entry.citizen then
        return reply(player, raw, false, "У вас нет паспорта. Введите /register")
    end
    local count = 0
    for _ in pairs(entry.known) do count = count + 1 end
    local text = ("%s — %s. Знакомых: %d"):format(RppNames.citizenTag(entry.citizen.id), fullName(entry.citizen), count)
    chat(player, text)
    reply(player, raw, true, text)
    end)
end, false)

RegisterCommand("register", function(player, _, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "register — команда игрока") end
    CreateThread(function()
        local ok, message = startRegistration(player)
        reply(player, raw, ok, message or "Регистрация открыта.")
    end)
end, false)

RegisterCommand("accept", function(player, _, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "accept — команда игрока") end
    local from = latestOffer(player)
    if not from then return reply(player, raw, false, "Нет активных предложений знакомства.") end
    CreateThread(function()
        local ok, message = introduce(player, from)
        reply(player, raw, ok, message or "Знакомство принято.")
    end)
end, false)

RegisterCommand("decline", function(player, _, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "decline — команда игрока") end
    local list = offers[player] or {}
    local count = 0
    for from, expires in pairs(list) do
        if expires > now() and online[from] then
            count = count + 1
            notify(from, "warning", "Ваше предложение знакомства отклонено.", "Знакомство")
        end
    end
    offers[player] = nil
    reply(player, raw, count > 0, count > 0 and ("Отклонено предложений: " .. count) or "Нет активных предложений.")
end, false)

-- Админ: сбросить паспорт игрока (он пройдёт регистрацию заново).
-- Ограниченная команда: нужен `command.rpp.identity.reset` в acl.jsonc.
RegisterCommand("rpp.identity.reset", function(player, args, raw)
    CreateThread(function()
    local target = tonumber(args[1])
    local entry = target and load(target)
    if not entry then return reply(tonumber(player), raw, false, "Использование: rpp.identity.reset <playerId>") end
    RppStore.deleteCitizen(entry.guid)
    entry.citizen = nil
    stage[target] = nil
    created[target] = nil
    pushSelf(target)
    pushAll()
    notify(target, "warning", "Администратор сбросил ваш паспорт. Пройдите регистрацию заново.")
    startRegistration(target)
    reply(tonumber(player), raw, true, ("Паспорт игрока %d сброшен."):format(target))
    end)
end, true)

-- Админ: кто скрывается за номером (аккаунт <-> паспорт).
-- Ограниченная команда: нужен `command.rpp.identity.info` в acl.jsonc.
RegisterCommand("rpp.identity.info", function(player, args, raw)
    CreateThread(function()
    local target = tonumber(args[1])
    local entry = target and load(target)
    if not entry then return reply(tonumber(player), raw, false, "Использование: rpp.identity.info <playerId>") end
    local account = Open77.players.name and Open77.players.name(target) or GetPlayerName(target)
    local text = entry.citizen
        and ("Игрок %d (%s): %s — %s"):format(target, tostring(account), RppNames.citizenTag(entry.citizen.id), fullName(entry.citizen))
        or ("Игрок %d (%s): паспорта нет"):format(target, tostring(account))
    if tonumber(player) and tonumber(player) > 0 then chat(tonumber(player), text) end
    reply(tonumber(player), raw, true, text)
    end)
end, true)

RegisterNetEvent("chat:ready", function()
    TriggerClientEvent("chat:addSuggestions", source, {
        { command = "/passport", help = "Показать свой паспорт: номер жителя и имя.", parameters = {} },
        { command = "/register", help = "Пройти регистрацию паспорта (если ещё нет).", parameters = {} },
        { command = "/accept", help = "Принять последнее предложение знакомства.", parameters = {} },
        { command = "/decline", help = "Отклонить все предложения знакомства.", parameters = {} },
    })
end)

-- ---------------------------------------------------------------------------
-- Жизненный цикл
-- ---------------------------------------------------------------------------
-- Клиент загрузил ресурс (подключение или перезагрузка ресурса).
RegisterNetEvent("rpp_identity:hello", function()
    local player = source
    CreateThread(function()
        if not load(player) then return end
        pushSelf(player)
        pushAll()
    end)
end)

AddEventHandler("onPlayerConnected", function(playerIdStr)
    local player = tonumber(playerIdStr)
    if player and player > 0 then CreateThread(function() load(player) end) end
end)

AddEventHandler("onPlayerDisconnected", function(playerIdStr)
    local player = tonumber(playerIdStr)
    if not player then return end
    online[player], stage[player], created[player], lastIntroduce[player] = nil, nil, nil, nil
    loading[player] = nil
    offers[player] = nil
    for _, list in pairs(offers) do list[player] = nil end
    pushAll()
end)

-- Экспорты для других серверных ресурсов.
exports("getCitizen", function(player)
    local entry = online[tonumber(player)]
    return entry and entry.citizen or nil
end)
exports("areAcquainted", function(a, b)
    local ea, eb = online[tonumber(a)], online[tonumber(b)]
    return ea ~= nil and eb ~= nil and ea.known[eb.guid] == true
end)
-- Как `viewer` видит `target`: имя знакомого или «Житель #N» (окно обмена rpp_inventory).
exports("labelFor", function(viewer, target)
    viewer, target = tonumber(viewer), tonumber(target)
    if not viewer or not target then return nil end
    return labelFor(viewer, target).label
end)

-- Хранилище: MySQL, если база работает, иначе kvp (server/storage.lua).
-- Без MySQL open77_appearance не открывает редактор (beginEdit ->
-- database_unavailable), и шаг кастомизации пропускается.
-- Затем подхватываем уже подключённых (перезагрузка ресурса на живом сервере).
CreateThread(function()
    dbReady = RppStore.init() == "mysql"
    log(dbReady and "MySQL available: customization before name is enabled"
        or "MySQL unavailable: customization step skipped")
    local ok, players = pcall(Open77.players.all)
    if ok and type(players) == "table" then
        for _, player in ipairs(players) do load(tonumber(player)) end
        pushAll()
    end
end)

log("ready")
