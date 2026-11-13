-- rpp_identity, клиентская часть: подписи над головами, пункт «Познакомиться»
-- в ALT-меню и шаг кастомизации перед вводом имени.
local cfg = RppIdentityConfig
local RESOURCE = GetCurrentResourceName()

local selfId = 0
local selfCitizen = nil
local labels = {}     -- [playerId] = { label, registered, known, citizenId }
local applied = {}    -- [playerId] = подпись, которую мы уже выставили
local awaitingAppearance = false

local function notify(kind, message, title)
    local pending = Open77.exports.call("open77_notifications", "show", {
        title = title or "Паспорт", message = message, type = kind,
    })
    if pending then pending:await() end
end

-- ---------------------------------------------------------------------------
-- Подписи над головами
-- ---------------------------------------------------------------------------
local function signature(entry)
    return entry.label .. "|" .. tostring(entry.known)
end

local function applyNameplates()
    if type(Open77.nameplates) ~= "table" or type(Open77.nameplates.set) ~= "function" then return end
    for playerId, entry in pairs(labels) do
        local sig = signature(entry)
        if applied[playerId] ~= sig then
            local color = entry.known and cfg.knownColor or cfg.strangerColor
            local ok, reason = Open77.nameplates.set(playerId, {
                label = entry.label,
                color = color ~= "" and color or nil,
                accent = color ~= "" and color or nil,
                maxDistance = cfg.nameplateDistance,
                visible = true,
                showDistance = false,
            })
            if ok then applied[playerId] = sig
            else print(("[%s] nameplate for %d refused: %s"):format(RESOURCE, playerId, tostring(reason))) end
        end
    end
    for playerId in pairs(applied) do
        if labels[playerId] == nil then
            pcall(Open77.nameplates.remove, playerId)
            applied[playerId] = nil
        end
    end
end

RegisterNetEvent("rpp_identity:labels", function(list)
    local fresh = {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        local id = tonumber(entry.playerId)
        if id and id ~= selfId and type(entry.label) == "string" then
            fresh[id] = {
                label = entry.label, registered = entry.registered == true,
                known = entry.known == true, citizenId = entry.citizenId,
            }
        end
    end
    labels = fresh
    applyNameplates()
end)

RegisterNetEvent("rpp_identity:self", function(playerId, citizen)
    selfId = tonumber(playerId) or selfId
    selfCitizen = type(citizen) == "table" and citizen or nil
    labels[selfId] = nil
end)

-- Выход из мира/повторный вход сбрасывает нативные подписи: выставляем заново.
AddEventHandler("open77:worldReady", function()
    applied = {}
    applyNameplates()
end)

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
local function appearanceDone(reason)
    if not awaitingAppearance then return end
    awaitingAppearance = false
    TriggerServerEvent("rpp_identity:appearanceDone", reason)
end

local function appearanceOpen()
    local pending = Open77.exports.call("open77_appearance", "isOpen")
    if not pending then return false end
    local value = pending:await()
    return value == true
end

RegisterNetEvent("rpp_identity:openAppearance", function(mode)
    awaitingAppearance = true
    notify("info", "Настройте внешность персонажа. После сохранения вы введёте имя и фамилию.")
    local pending, reason = Open77.exports.call("open77_appearance", "open", mode or cfg.appearanceMode)
    if not pending then return appearanceDone("open_failed:" .. tostring(reason)) end
    pending:await()

    -- Страховка на случай, если событие закрытия редактора до нас не дошло:
    -- если редактор был открыт и закрылся, а сервер так и не попросил имя,
    -- через 10 секунд сами сообщаем серверу.
    CreateThread(function()
        local seenOpen, closedAt = false, nil
        local started = Open77.time.monotonic()
        while awaitingAppearance do
            local isOpen = appearanceOpen()
            if isOpen then seenOpen, closedAt = true, nil
            elseif seenOpen and closedAt == nil then closedAt = Open77.time.monotonic() end
            local t = Open77.time.monotonic()
            if closedAt and t - closedAt > 10 then return appearanceDone("closed") end
            -- Редактор так и не открылся за 30 секунд.
            if not seenOpen and t - started > 30 then return appearanceDone("never_opened") end
            Wait(1000)
        end
    end)
end)

AddEventHandler("open77:appearance:cancelled", function() appearanceDone("cancelled") end)
RegisterNetEvent("open77:appearance:rejected", function(_, reason)
    appearanceDone("rejected:" .. tostring(reason))
end)

RegisterNetEvent("rpp_identity:askName", function()
    awaitingAppearance = false
    RppForm.askName()
end)

RegisterNetEvent("rpp_identity:nameRejected", function(field, message)
    RppForm.rejected(field, message)
end)

RegisterNetEvent("rpp_identity:registered", function(citizen)
    if type(citizen) ~= "table" then return end
    selfCitizen = citizen
    RppForm.confirm(citizen)
    notify("success", ("Добро пожаловать, %s %s. Ваш номер: %s")
        :format(citizen.first, citizen.last, RppNames.citizenTag(citizen.id)))
end)

AddEventHandler("rpp_identity:formClosed", function()
    if selfCitizen == nil then
        notify("warning", "Паспорт не оформлен. Введите /register, чтобы открыть форму снова.")
    end
end)

-- ---------------------------------------------------------------------------
-- ALT-меню: «Познакомиться»
-- ---------------------------------------------------------------------------
exports("canIntroduce", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local target = context and context.target
    local id = target and tonumber(target.playerId)
    if not id or target.isLocalPlayer == true or id == selfId then return false end
    if selfCitizen == nil then return false end
    local entry = labels[id]
    return entry ~= nil and entry.registered and not entry.known
end)

exports("selectIntroduce", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = context and context.target and tonumber(context.target.playerId)
    if not id then return false end
    TriggerServerEvent("rpp_identity:introduce", id)
    return true
end)

local function registerContext()
    local pending, reason = Open77.exports.call("open77_contextmenu", "registerPlayers", {
        id = "rpp_introduce",
        label = "Познакомиться",
        description = "Представиться. Имена увидите оба после взаимного согласия.",
        icon = "person",
        distance = cfg.introduceDistance,
        group = "Паспорт",
        canInteract = "canIntroduce",
        onSelect = "selectIntroduce",
    })
    if pending then
        local token
        token, reason = pending:await()
        if token then return end
    end
    print(("[%s] context menu registration failed: %s"):format(RESOURCE, tostring(reason)))
end

AddEventHandler("onClientResourceStart", function(name)
    if name == RESOURCE then
        TriggerServerEvent("rpp_identity:hello")
        registerContext()
    elseif name == "open77_contextmenu" then
        registerContext()
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    for playerId in pairs(applied) do pcall(Open77.nameplates.remove, playerId) end
    applied = {}
end)
