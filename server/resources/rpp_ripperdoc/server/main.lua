-- rpp_ripperdoc, сервер. Всё решает сервер: кто риппердок, есть ли согласие,
-- рядом ли пациент, есть ли имплант в инвентаре, есть ли место для снятого.
local cfg = RppRipperdocConfig
local RESOURCE = GetCurrentResourceName()
local JSON = json or (Open77 and Open77.json)

local doctors = {}        -- [playerId] = true — риппердоки онлайн
local consent = {}        -- [patient] = { [doctor] = expiresAt }
local busy = {}           -- [patient] = операция идёт
local pending = {}        -- [ticket] = { kind, doctor, patient, owner, itemId, slot }
local viewing = {}        -- [doctor] = patient, чья панель открыта
local defined = false

local function log(text) print("[" .. RESOURCE .. "] " .. text) end
local function now() return Open77.time.monotonic() end
local function safe(guid) return (tostring(guid):gsub("[^%w%-_]", "_")) end

local function notify(player, kind, message)
    pcall(Open77.notifications.send, player, { type = kind, title = "Риппердок", message = message,
        durationMs = kind == "error" and 6000 or 4500 })
end

local function reply(player, raw, ok, message)
    if not player or player <= 0 then print(message); return end
    TriggerClientEvent("open77:command:result", player, raw, ok, message)
end

-- Вызов экспорта rpp_inventory (внутри CreateThread).
local function inventory(name, ...)
    local ok, result = pcall(function(...)
        local promise = Open77.exports.call("rpp_inventory", name, ...)
        if not promise then return nil end
        return promise:await()
    end, ...)
    if not ok then log("rpp_inventory." .. name .. " failed: " .. tostring(result)); return nil end
    return result
end

local function nameFor(viewer, target)
    local ok, label = pcall(function()
        local promise = Open77.exports.call("rpp_identity", "labelFor", viewer, target)
        return promise and promise:await() or nil
    end)
    if ok and type(label) == "string" and label ~= "" then return label end
    return "Игрок #" .. tostring(target)
end

-- ---------------------------------------------------------------------------
-- Роль
-- ---------------------------------------------------------------------------
local function isDoctorGuid(guid)
    local ok, value = pcall(Open77.kvp.get, "rpp.ripperdoc." .. safe(guid))
    return ok and (value == "1" or value == true)
end

local function broadcastDoctors()
    local list = {}
    for id in pairs(doctors) do list[#list + 1] = id end
    TriggerClientEvent("rpp_ripperdoc:doctors", -1, list)
end

local function refreshRole(player)
    local guid = GetPlayerIdentifier(player)
    local was = doctors[player] == true
    doctors[player] = (guid and guid ~= "" and isDoctorGuid(guid)) or nil
    TriggerClientEvent("rpp_ripperdoc:role", player, doctors[player] == true)
    if was ~= (doctors[player] == true) then broadcastDoctors() end
end

RegisterNetEvent("rpp_ripperdoc:hello", function()
    local player = tonumber(source)
    if not player then return end
    refreshRole(player)
    local list = {}
    for id in pairs(doctors) do list[#list + 1] = id end
    TriggerClientEvent("rpp_ripperdoc:doctors", player, list)
end)

-- Ограниченная: нужен `command.rpp.ripperdoc` в acl.jsonc (у роли admin есть command.*).
RegisterCommand("rpp.ripperdoc", function(player, args, raw)
    player = tonumber(player)
    local target = args[1] == "me" and player or tonumber(args[1])
    local mode = args[2] and args[2]:lower()
    if not target or (mode ~= "on" and mode ~= "off") then
        return reply(player, raw, false, "использование: rpp.ripperdoc <ID игрока|me> <on|off>")
    end
    local guid = GetPlayerIdentifier(target)
    if not guid or guid == "" then return reply(player, raw, false, "игрок не найден") end
    local stored = pcall(Open77.kvp.set, "rpp.ripperdoc." .. safe(guid), mode == "on" and "1" or "0")
    if not stored then return reply(player, raw, false, "не удалось сохранить роль") end
    refreshRole(target)
    notify(target, mode == "on" and "success" or "info",
        mode == "on" and "Вы теперь риппердок. ALT на пациенте → «Импланты (риппердок)»." or "Вы больше не риппердок.")
    reply(player, raw, true, ("игрок %d: риппердок %s"):format(target, mode == "on" and "включён" or "выключен"))
end, true)

-- ---------------------------------------------------------------------------
-- Импланты
-- ---------------------------------------------------------------------------
local function gradeOf(slot, gradeId)
    local def = cfg.definitions[slot]
    if not def then return nil end
    for _, grade in ipairs(def.grades) do if grade.id == gradeId then return grade end end
    return nil
end

local function entryGrade(entry)
    if type(entry) ~= "table" then return nil end
    return type(entry.grade) == "table" and entry.grade.id or entry.grade
end

--- Какой предмет получится из установленного импланта.
local function itemFor(slot, entry)
    local grade = entryGrade(entry)
    if grade and gradeOf(slot, grade) then return "cw_" .. slot .. "_" .. grade end
    return "cw_" .. slot .. "_training" -- чужой/неизвестный грейд: ближайший наш
end

local function parseItem(itemId)
    local slot, grade = tostring(itemId or ""):match("^cw_(%a+)_([%w_]+)$")
    if slot and gradeOf(slot, grade) then return slot, grade end
    return nil
end

local function position(player)
    local ok, pos = pcall(Open77.players.position, player)
    if ok and type(pos) == "table" and tonumber(pos.x) then return pos end
    return nil
end

local function near(a, b)
    local pa, pb = position(a), position(b)
    if not pa or not pb then return true end -- позиции недоступны: проверку пропускаем
    if pa.bucket ~= pb.bucket then return false end
    local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
    local limit = cfg.distance + 1.0
    return dx * dx + dy * dy + dz * dz <= limit * limit
end

local function consentLeft(patient, doctor)
    local expires = consent[patient] and consent[patient][doctor]
    if not expires then return 0 end
    return math.max(0, math.floor(expires - now()))
end

local function implantList(player)
    local list = inventory("listItems", player, "implant")
    local out = {}
    for _, item in ipairs(type(list) == "table" and list or {}) do
        local slot = parseItem(item.id)
        if slot then out[#out + 1] = { id = item.id, label = item.label, slot = slot } end
    end
    return out
end

local function installedView(record, slot)
    local entry = record and record[slot]
    if type(entry) ~= "table" then return false end
    local item = itemFor(slot, entry)
    local described = inventory("describe", item)
    return { item = item, label = type(described) == "table" and described.label or item,
        foreign = entry.definition ~= cfg.definitions[slot].id }
end

local function pushView(doctor)
    local patient = viewing[doctor]
    if not patient then return end
    local record = nil
    local ok, value = pcall(Open77.cyberware.current, patient)
    if ok and type(value) == "table" then record = value end
    TriggerClientEvent("rpp_ripperdoc:view", doctor, {
        patient = patient,
        patientName = nameFor(doctor, patient),
        consent = consentLeft(patient, doctor),
        busy = busy[patient] == true,
        ready = record ~= nil,
        installed = { arms = installedView(record, "arms"), legs = installedView(record, "legs") },
        slotLabels = cfg.slotLabels,
        patientImplants = implantList(patient),
        doctorImplants = implantList(doctor),
    })
end

local function pushViewsFor(patient)
    for doctor, target in pairs(viewing) do if target == patient then pushView(doctor) end end
end

--- Общие проверки операции. nil или текст ошибки.
local function operationProblem(doctor, patient)
    if not doctors[doctor] then return "Вы не риппердок." end
    if not patient or patient == doctor then return "Неверный пациент." end
    if not GetPlayerIdentifier(patient) then return "Пациент недоступен." end
    if not near(doctor, patient) then return "Подойдите к пациенту ближе (до " .. cfg.distance .. " м)." end
    if consentLeft(patient, doctor) <= 0 then
        return "Нет согласия пациента: он должен нажать ALT на вас → «Разрешить операцию»."
    end
    if busy[patient] then return "Операция уже идёт." end
    if not defined then return "Импланты ещё не готовы на сервере." end
    return nil
end

local function action(name, handler)
    RegisterNetEvent("rpp_ripperdoc:" .. name, function(...)
        local doctor = tonumber(source)
        if not doctor then return end
        local args = table.pack(...)
        CreateThread(function()
            local ok, message = pcall(handler, doctor, table.unpack(args, 1, args.n))
            if not ok then log(name .. " failed: " .. tostring(message)); message = "Внутренняя ошибка." end
            if type(message) == "string" then notify(doctor, "error", message) end
            pushView(doctor)
        end)
    end)
end

action("open", function(doctor, patient)
    patient = tonumber(patient)
    if not doctors[doctor] then return "Вы не риппердок." end
    if not patient or patient == doctor then return end
    if not near(doctor, patient) then return "Подойдите к пациенту ближе." end
    viewing[doctor] = patient
    TriggerClientEvent("rpp_ripperdoc:open", doctor)
end)

action("close", function(doctor) viewing[doctor] = nil end)
action("refresh", function() end)

local function finish(entry, ok, reason)
    busy[entry.patient] = nil
    local slotLabel = cfg.slotLabels[entry.slot] or entry.slot
    if entry.kind == "install" then
        if ok then
            notify(entry.doctor, "success", "Имплант установлен: " .. slotLabel .. ".")
            notify(entry.patient, "success", "Риппердок установил вам имплант: " .. slotLabel .. ".")
        else
            -- Имплант возвращается туда, откуда его взяли.
            inventory("addItem", entry.owner, entry.itemId)
            notify(entry.doctor, "error", "Установка не удалась: " .. tostring(reason or "ошибка") .. ". Имплант возвращён.")
        end
    else
        if ok then
            local added = inventory("addItem", entry.patient, entry.itemId)
            if not added then
                log(("removed %s from %d but inventory refused it"):format(entry.itemId, entry.patient))
                notify(entry.patient, "error", "Имплант снят, но не поместился в инвентарь.")
            end
            notify(entry.doctor, "success", "Имплант снят: " .. slotLabel .. ". Он в инвентаре пациента.")
            notify(entry.patient, "info", "Риппердок снял ваш имплант (" .. slotLabel .. "). Он в вашем инвентаре.")
        else
            notify(entry.doctor, "error", "Снять не удалось: " .. tostring(reason or "ошибка") .. ".")
        end
    end
    log(("%s %s doctor=%d patient=%d item=%s ok=%s %s"):format(entry.kind, entry.slot, entry.doctor,
        entry.patient, entry.itemId, tostring(ok), tostring(reason or "")))
    pushView(entry.doctor)
end

local function start(entry, result, reason)
    if not result or not result.ok then
        finish(entry, false, reason or (type(result) == "table" and result.error) or "operation_refused")
        return
    end
    if result.ticket then
        entry.at = now()
        pending[tostring(result.ticket)] = entry
    else
        finish(entry, true)
    end
end

action("install", function(doctor, patient, source_, itemId)
    patient = tonumber(patient)
    local problem = operationProblem(doctor, patient)
    if problem then return problem end
    local slot, grade = parseItem(itemId)
    if not slot then return "Это не имплант." end
    local record = Open77.cyberware.current(patient)
    if type(record) ~= "table" then return "Импланты пациента пока не загружены." end
    if record[slot] then return "Слот «" .. cfg.slotLabels[slot] .. "» занят: сначала снимите имплант." end
    local owner = source_ == "doctor" and doctor or patient
    if not inventory("removeItem", owner, itemId) then return "Этого импланта уже нет в инвентаре." end
    local operationId = Open77.cyberware.newOperationId()
    if not operationId then
        inventory("addItem", owner, itemId)
        return "Сервер имплантов недоступен."
    end
    busy[patient] = true
    local result, reason = Open77.cyberware.install(patient, cfg.definitions[slot].id, grade,
        { expectedRevision = record.revision, operationId = operationId, slot = slot })
    start({ kind = "install", doctor = doctor, patient = patient, owner = owner, itemId = itemId, slot = slot },
        result, reason)
end)

action("remove", function(doctor, patient, slot)
    patient = tonumber(patient)
    local problem = operationProblem(doctor, patient)
    if problem then return problem end
    if not cfg.definitions[slot] then return "Неверный слот." end
    local record = Open77.cyberware.current(patient)
    if type(record) ~= "table" then return "Импланты пациента пока не загружены." end
    if not record[slot] then return "В этом слоте нет импланта." end
    local itemId = itemFor(slot, record[slot])
    if not inventory("canCarry", patient, itemId) then
        return "У пациента нет места в инвентаре для импланта."
    end
    local operationId = Open77.cyberware.newOperationId()
    if not operationId then return "Сервер имплантов недоступен." end
    busy[patient] = true
    local result, reason = Open77.cyberware.remove(patient,
        { expectedRevision = record.revision, operationId = operationId, slot = slot })
    start({ kind = "remove", doctor = doctor, patient = patient, itemId = itemId, slot = slot }, result, reason)
end)

AddEventHandler("onCyberwareOperationCompleted", function(patient, ticket, encoded)
    local entry = pending[tostring(ticket)]
    if not entry then return end
    pending[tostring(ticket)] = nil
    local ok, completion = pcall(JSON.decode, encoded)
    local success = ok and type(completion) == "table" and completion.ok == true
    CreateThread(function()
        finish(entry, success, (not success) and (ok and type(completion) == "table" and completion.error or "operation_failed") or nil)
    end)
end)

-- Ответ на операцию не пришёл за 30 с: снимаем блокировку пациента. Предмет не
-- возвращаем и не выдаём — операция могла пройти, двойника импланта не будет.
CreateThread(function()
    while true do
        Wait(5000)
        local t = now()
        for ticket, entry in pairs(pending) do
            if t - (entry.at or t) > 30 then
                pending[ticket] = nil
                busy[entry.patient] = nil
                log(("operation %s timed out: %s %s doctor=%d patient=%d item=%s"):format(ticket, entry.kind,
                    entry.slot, entry.doctor, entry.patient, entry.itemId))
                notify(entry.doctor, "warning", "Сервер имплантов не ответил. Проверьте импланты пациента.")
                pushView(entry.doctor)
            end
        end
    end
end)

-- Пациент разрешает операцию (ALT на риппердоке).
RegisterNetEvent("rpp_ripperdoc:consent", function(doctor)
    local patient = tonumber(source)
    doctor = tonumber(doctor)
    if not patient or not doctor or doctor == patient then return end
    CreateThread(function()
        if not doctors[doctor] then return notify(patient, "error", "Этот игрок не риппердок.") end
        if not near(patient, doctor) then return notify(patient, "error", "Подойдите к риппердоку ближе.") end
        consent[patient] = consent[patient] or {}
        consent[patient][doctor] = now() + cfg.consentSec
        local minutes = math.floor(cfg.consentSec / 60)
        notify(patient, "success", "Вы разрешили операцию: " .. nameFor(patient, doctor) .. " (" .. minutes .. " мин).")
        notify(doctor, "info", nameFor(doctor, patient) .. " разрешил(а) операцию на " .. minutes .. " мин.")
        pushViewsFor(patient)
    end)
end)

AddEventHandler("onPlayerDisconnected", function(player)
    player = tonumber(player)
    if not player then return end
    if doctors[player] then doctors[player] = nil; broadcastDoctors() end
    consent[player], busy[player], viewing[player] = nil, nil, nil
    for _, list in pairs(consent) do list[player] = nil end
    for doctor, patient in pairs(viewing) do
        if patient == player then
            viewing[doctor] = nil
            TriggerClientEvent("rpp_ripperdoc:close", doctor)
        end
    end
end)

CreateThread(function()
    for slot, def in pairs(cfg.definitions) do
        local ok, result, reason = pcall(Open77.cyberware.define, def)
        if ok and result then
            log("implant definition " .. def.id .. " ready")
        else
            log("implant definition " .. def.id .. " failed: " .. tostring(ok and reason or result))
        end
    end
    defined = true
    local ok, players = pcall(Open77.players.all)
    for _, player in ipairs(ok and type(players) == "table" and players or {}) do
        player = tonumber(type(player) == "table" and player.id or player)
        if player then refreshRole(player) end
    end
    broadcastDoctors()
end)
