-- rpp_vehicles, серверная часть. Сервер — единственный источник правды: он
-- знает, чья машина, у кого ключи, и проверяет права и дистанцию у каждого
-- действия из ALT-меню. Клиентские проверки — только чтобы прятать пункты меню.
--
-- Права на машину: владелец; у кого ключи (владелец дал через ALT на игроке).
-- Права дают: замок, багажник, высадку пассажиров. Выдавать и забирать ключи
-- может только владелец.
local cfg = RppVehiclesConfig
local RESOURCE = GetCurrentResourceName()

local spawned = {}    -- [carId] = { car = строка из базы, vehicleId, locked, ownerPlayer }
local byVehicle = {}  -- [vehicleId] = carId
local trunkOpen = {}  -- [playerId] = carId: у кого открыт багажник какой машины
local lastAction = {} -- [playerId] = секунды: защита от спама

local function log(text) print("[" .. RESOURCE .. "] " .. text) end
local function now() return Open77.time.monotonic() end

local function notify(player, kind, message)
    local ok, err = pcall(Open77.notifications.send, player, {
        type = kind, title = "Машина", message = message, durationMs = kind == "error" and 5000 or 4000,
    })
    if not ok then log("notification failed: " .. tostring(err)) end
end

local function reply(player, raw, ok, message)
    if player == nil or player <= 0 then print(message); return end
    TriggerClientEvent("open77:command:result", player, raw, ok, message)
end

local function guidOf(player)
    local guid = GetPlayerIdentifier(player)
    if guid == nil or guid == "" then return nil end
    return guid
end

local function onlinePlayers()
    local ok, list = pcall(Open77.players.all)
    local out = {}
    for _, p in ipairs(ok and type(list) == "table" and list or {}) do
        local id = tonumber(type(p) == "table" and p.id or p)
        if id then out[#out + 1] = id end
    end
    return out
end

local function playerByGuid(guid)
    for _, p in ipairs(onlinePlayers()) do
        if guidOf(p) == guid then return p end
    end
    return nil
end

local function modelLabel(record)
    return cfg.labels[record] or tostring(record):gsub("^Vehicle%.", "")
end

-- ---------------------------------------------------------------------------
-- Позиции и дистанции
-- ---------------------------------------------------------------------------
local function playerPos(player)
    local ok, pos = pcall(Open77.players.position, player)
    if ok and type(pos) == "table" and tonumber(pos.x) then return pos end
    return nil
end

local function vehicleSnapshot(vehicleId)
    local ok, snap = pcall(Open77.vehicles.get, vehicleId)
    if ok and type(snap) == "table" then return snap end
    return nil
end

--- Расстояние от игрока до машины (м). math.huge, если в разных мирах; nil — неизвестно.
local function distanceTo(player, vehicleId)
    local pos, snap = playerPos(player), vehicleSnapshot(vehicleId)
    if not pos or not snap or snap.x == nil then return nil end
    if snap.bucket ~= nil and pos.bucket ~= nil and snap.bucket ~= pos.bucket then return math.huge end
    local dx, dy, dz = pos.x - snap.x, pos.y - snap.y, pos.z - snap.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distanceBetween(a, b)
    local pa, pb = playerPos(a), playerPos(b)
    if not pa or not pb then return nil end
    if pa.bucket ~= pb.bucket then return math.huge end
    local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function occupants(vehicleId)
    local snap = vehicleSnapshot(vehicleId)
    local list = {}
    for _, o in ipairs(snap and type(snap.occupants) == "table" and snap.occupants or {}) do
        local id = tonumber(type(o) == "table" and o.playerId or o)
        if id then list[#list + 1] = id end
    end
    return list
end

local function isInside(player, vehicleId)
    for _, id in ipairs(occupants(vehicleId)) do if id == player then return true end end
    return false
end

--- Рядом с машиной или сидит в ней.
local function near(player, vehicleId, limit)
    if isInside(player, vehicleId) then return true end
    local d = distanceTo(player, vehicleId)
    return d ~= nil and d <= limit
end

-- ---------------------------------------------------------------------------
-- Права
-- ---------------------------------------------------------------------------
--- "owner" | "key" | nil.
local function rightsOf(player, entry)
    local guid = guidOf(player)
    if not guid or not entry then return nil end
    if entry.car.owner == guid then return "owner" end
    if entry.car.keys[guid] then return "key" end
    return nil
end

--- Что каждый игрок может делать с вызванными машинами — для пунктов ALT-меню.
local function pushRights()
    for _, player in ipairs(onlinePlayers()) do
        local guid = guidOf(player)
        local list, holders = {}, {}
        for carId, entry in pairs(spawned) do
            local right = rightsOf(player, entry)
            if right then
                list[#list + 1] = { vehicleId = entry.vehicleId, carId = carId, label = entry.car.label,
                    locked = entry.locked == true, owner = right == "owner" }
            end
            if guid and entry.car.owner == guid then
                -- Кто из игроков онлайн держит ключи от моей машины: для «Забрать ключи».
                for holderGuid in pairs(entry.car.keys) do
                    local holder = playerByGuid(holderGuid)
                    if holder then holders[#holders + 1] = holder end
                end
            end
        end
        TriggerClientEvent("rpp_vehicles:rights", player, list, holders)
    end
end

-- ---------------------------------------------------------------------------
-- Вызов и парковка
-- ---------------------------------------------------------------------------
local function closeTrunksOf(carId, reason)
    for player, openCar in pairs(trunkOpen) do
        if openCar == carId then
            trunkOpen[player] = nil
            pcall(function()
                local p = Open77.exports.call("rpp_inventory", "closeContainer", player, reason)
                if p then p:await() end
            end)
        end
    end
end

local function forget(carId)
    local entry = spawned[carId]
    if not entry then return end
    spawned[carId] = nil
    byVehicle[entry.vehicleId] = nil
    closeTrunksOf(carId, "Багажник закрыт: машину убрали.")
end

local function spawnedCountFor(guid)
    local count = 0
    for _, entry in pairs(spawned) do if entry.car.owner == guid then count = count + 1 end end
    return count
end

local function spawnCar(player, car)
    if spawned[car.id] then return false, "«" .. car.label .. "» уже вызвана." end
    if spawnedCountFor(car.owner) >= cfg.maxSpawnedPerPlayer then
        return false, "Сначала припаркуйте вызванную машину: ALT на машине → «Припарковать»."
    end
    local pos = playerPos(player)
    if not pos then return false, "Позиция ещё не определена, попробуйте через секунду." end
    local o = cfg.spawnOffset
    local vehicleId, reason = Open77.vehicles.create({
        record = car.record,
        position = { x = pos.x + o.x, y = pos.y + o.y, z = pos.z + o.z },
        yaw = 0,
        bucket = pos.bucket or 0,
    })
    if vehicleId == nil then
        log(("spawn of car #%d (%s) failed: %s"):format(car.id, car.record, tostring(reason)))
        return false, "Не удалось вызвать машину: " .. tostring(reason)
    end
    local entry = { car = car, vehicleId = vehicleId, locked = false, ownerPlayer = player }
    spawned[car.id] = entry
    byVehicle[vehicleId] = car.id
    if cfg.lockedOnSpawn then
        local ok = Open77.vehicles.setLocked(vehicleId, true)
        entry.locked = ok == true
    end
    log(("car #%d (%s) spawned as vehicle %d for %d"):format(car.id, car.record, vehicleId, player))
    pushRights()
    return true, "«" .. car.label .. "» рядом с вами" .. (entry.locked and " (закрыта)." or ".")
end

local function parkEntry(carId)
    local entry = spawned[carId]
    if not entry then return end
    for _, id in ipairs(occupants(entry.vehicleId)) do
        pcall(Open77.vehicles.forcePlayerOutOfVehicle, id, entry.vehicleId)
    end
    forget(carId)
    pcall(Open77.vehicles.remove, entry.vehicleId)
end

AddEventHandler("onVehicleRemoved", function(vehicleIdStr)
    local carId = byVehicle[tonumber(vehicleIdStr) or -1]
    if carId then
        CreateThread(function() -- forget ждёт ответа rpp_inventory
            forget(carId)
            pushRights()
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Действия из ALT-меню
-- ---------------------------------------------------------------------------
local function throttled(player)
    local t = now()
    if lastAction[player] and t - lastAction[player] < 0.4 then return true end
    lastAction[player] = t
    return false
end

--- Обработчик действия с машиной: игрок, запись вызванной машины, его права.
local function vehicleAction(name, handler)
    RegisterNetEvent("rpp_vehicles:" .. name, function(vehicleId)
        local player = tonumber(source)
        vehicleId = tonumber(vehicleId)
        if not player or not vehicleId or throttled(player) then return end
        CreateThread(function()
            local carId = byVehicle[vehicleId]
            local entry = carId and spawned[carId]
            local right = rightsOf(player, entry)
            if not right then return notify(player, "error", "У вас нет ключей от этой машины.") end
            local ok, err = pcall(handler, player, entry, carId, right)
            if not ok then log(name .. " failed: " .. tostring(err)); notify(player, "error", "Не получилось.") end
        end)
    end)
end

vehicleAction("lock", function(player, entry)
    if not near(player, entry.vehicleId, cfg.interactDistance) then
        return notify(player, "error", "Подойдите ближе к машине.")
    end
    local want = not entry.locked
    local ok, reason = Open77.vehicles.setLocked(entry.vehicleId, want)
    if ok ~= true then return notify(player, "error", "Замок не сработал: " .. tostring(reason)) end
    entry.locked = want
    if Open77.vehicles.triggerHorn then pcall(Open77.vehicles.triggerHorn, entry.vehicleId, want and 120 or 60) end
    notify(player, "success", "«" .. entry.car.label .. "» " .. (want and "закрыта." or "открыта."))
    pushRights()
end)

vehicleAction("trunk", function(player, entry, carId)
    if isInside(player, entry.vehicleId) then return notify(player, "error", "Выйдите из машины, чтобы открыть багажник.") end
    local d = distanceTo(player, entry.vehicleId)
    if not d or d > cfg.trunkDistance then return notify(player, "error", "Подойдите к багажнику ближе.") end
    local promise, err = Open77.exports.call("rpp_inventory", "openContainer", player, "vehicle:" .. carId, {
        label = "Багажник «" .. entry.car.label .. "»", capacity = cfg.trunkCapacity,
    })
    local ok, reason = false, err
    if promise then ok, reason = promise:await() end
    if ok ~= true then return notify(player, "error", "Багажник не открылся: " .. tostring(reason)) end
    trunkOpen[player] = carId
end)

vehicleAction("eject", function(player, entry)
    if not near(player, entry.vehicleId, cfg.interactDistance) then
        return notify(player, "error", "Подойдите ближе к машине.")
    end
    local count = 0
    for _, id in ipairs(occupants(entry.vehicleId)) do
        if id ~= player then
            local ok = pcall(Open77.vehicles.forcePlayerOutOfVehicle, id, entry.vehicleId)
            if ok then
                count = count + 1
                notify(id, "warning", "Вас высадили из машины.")
            end
        end
    end
    notify(player, count > 0 and "success" or "info",
        count > 0 and ("Высажено пассажиров: " .. count .. ".") or "В машине никого, кроме вас.")
end)

-- Действия на игроке (ALT на игроке).
local function playerAction(name, handler)
    RegisterNetEvent("rpp_vehicles:" .. name, function(target)
        local player = tonumber(source)
        target = tonumber(target)
        if not player or not target or target == player or throttled(player) then return end
        CreateThread(function()
            local ok, err = pcall(handler, player, target)
            if not ok then log(name .. " failed: " .. tostring(err)); notify(player, "error", "Не получилось.") end
        end)
    end)
end

--- Машина, в которой сидит игрок: carId, запись — или nil.
local function carWithPassenger(target)
    for carId, entry in pairs(spawned) do
        if isInside(target, entry.vehicleId) then return carId, entry end
    end
    return nil
end

playerAction("ejectPlayer", function(player, target)
    local _, entry = carWithPassenger(target)
    if not entry then return notify(player, "error", "Этот человек не в вашей машине.") end
    if not rightsOf(player, entry) then return notify(player, "error", "У вас нет ключей от этой машины.") end
    if not near(player, entry.vehicleId, cfg.interactDistance) then return notify(player, "error", "Подойдите ближе к машине.") end
    local ok, reason = pcall(Open77.vehicles.forcePlayerOutOfVehicle, target, entry.vehicleId)
    if not ok then return notify(player, "error", "Не удалось высадить: " .. tostring(reason)) end
    notify(target, "warning", "Вас высадили из машины.")
    notify(player, "success", "Пассажир высажен.")
end)

--- Ближайшая вызванная машина, которой владеет игрок: запись или nil.
local function nearestOwned(player, limit)
    local guid = guidOf(player)
    local best, bestDistance = nil, limit
    for _, entry in pairs(spawned) do
        if entry.car.owner == guid then
            local d = isInside(player, entry.vehicleId) and 0 or distanceTo(player, entry.vehicleId)
            if d and d <= bestDistance then best, bestDistance = entry, d end
        end
    end
    return best
end

playerAction("giveKeys", function(player, target)
    local entry = nearestOwned(player, 30)
    if not entry then return notify(player, "error", "Рядом нет вашей машины. Вызовите её: /garage.") end
    local d = distanceBetween(player, target)
    if not d or d > cfg.interactDistance then return notify(player, "error", "Подойдите ближе к человеку.") end
    local targetGuid = guidOf(target)
    if not targetGuid then return notify(player, "error", "Игрок недоступен.") end
    if entry.car.keys[targetGuid] then return notify(player, "info", "У него уже есть ключи.") end
    entry.car.keys[targetGuid] = true
    local ok, err = RppVehStore.setKeys(entry.car.id, entry.car.keys)
    if not ok then
        entry.car.keys[targetGuid] = nil
        log("keys save failed: " .. tostring(err))
        return notify(player, "error", "Не удалось сохранить ключи.")
    end
    notify(player, "success", "Вы дали ключи от «" .. entry.car.label .. "».")
    notify(target, "success", "Вам дали ключи от «" .. entry.car.label .. "».")
    pushRights()
end)

playerAction("takeKeys", function(player, target)
    local guid, targetGuid = guidOf(player), guidOf(target)
    if not guid or not targetGuid then return end
    local cars, err = RppVehStore.listByOwner(guid)
    if not cars then log("list failed: " .. tostring(err)); return notify(player, "error", "Гараж недоступен.") end
    local taken = 0
    for _, car in ipairs(cars) do
        local live = spawned[car.id] and spawned[car.id].car or car
        if live.keys[targetGuid] then
            live.keys[targetGuid] = nil
            RppVehStore.setKeys(car.id, live.keys)
            taken = taken + 1
        end
    end
    if taken == 0 then return notify(player, "info", "У него нет ключей от ваших машин.") end
    -- Если он сейчас у багажника вашей машины — закрыть.
    local openCar = trunkOpen[target]
    if openCar and spawned[openCar] and not rightsOf(target, spawned[openCar]) then
        closeTrunksOf(openCar, nil)
    end
    notify(player, "success", "Вы забрали ключи (" .. taken .. ").")
    notify(target, "warning", "У вас забрали ключи от машины.")
    pushRights()
end)

-- ---------------------------------------------------------------------------
-- Команды игрока
-- ---------------------------------------------------------------------------
local function ownCars(player)
    local guid = guidOf(player)
    if not guid then return nil, "Не удалось определить аккаунт." end
    local cars, err = RppVehStore.listByOwner(guid)
    if not cars then log("list failed: " .. tostring(err)); return nil, "Гараж недоступен." end
    -- Вызванные машины — с актуальными ключами из памяти.
    for index, car in ipairs(cars) do
        if spawned[car.id] then cars[index] = spawned[car.id].car end
    end
    return cars
end

--- Окно гаража: список своих машин.
local function garageView(player)
    local cars, err = ownCars(player)
    if not cars then return nil, err end
    local list = {}
    for _, car in ipairs(cars) do
        local keys = 0
        for _ in pairs(car.keys) do keys = keys + 1 end
        list[#list + 1] = { id = car.id, label = car.label, model = modelLabel(car.record),
            spawned = spawned[car.id] ~= nil, keys = keys }
    end
    return { cars = list, max = cfg.maxSpawnedPerPlayer }
end

local function pushGarage(player, openWindow)
    local view, err = garageView(player)
    if not view then return notify(player, "error", err) end
    TriggerClientEvent("rpp_vehicles:garage", player, view, openWindow == true)
end

-- /garage — окно со своими машинами: выбрать и вызвать.
RegisterCommand("garage", function(player, _, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "garage — команда игрока") end
    CreateThread(function() pushGarage(player, true) end)
end, false)

-- Кнопка «Вызвать» в окне гаража.
RegisterNetEvent("rpp_vehicles:spawn", function(carId)
    local player = tonumber(source)
    carId = tonumber(carId)
    if not player or not carId or throttled(player) then return end
    CreateThread(function()
        local cars = ownCars(player) or {}
        local car
        for _, c in ipairs(cars) do if c.id == carId then car = c; break end end
        if not car then return notify(player, "error", "Это не ваша машина.") end
        local ok, message = spawnCar(player, car)
        notify(player, ok and "success" or "error", message)
        if ok then TriggerClientEvent("rpp_vehicles:garageClose", player) else pushGarage(player, false) end
    end)
end)

-- ALT на машине → «Припарковать»: убрать в гараж. Только владелец; пассажиров быть не должно.
vehicleAction("park", function(player, entry, carId, right)
    if right ~= "owner" then return notify(player, "error", "Припарковать в гараж может только владелец.") end
    if not near(player, entry.vehicleId, cfg.parkDistance) then return notify(player, "error", "Подойдите ближе к машине.") end
    for _, id in ipairs(occupants(entry.vehicleId)) do
        if id ~= player then return notify(player, "error", "В машине пассажиры: сначала высадите их.") end
    end
    local label = entry.car.label
    parkEntry(carId)
    pushRights()
    notify(player, "success", "«" .. label .. "» отправлена в гараж. Багажник сохранён.")
end)

-- /carkeys — забрать ключи от всех своих машин у всех.
RegisterCommand("carkeys", function(player, _, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "carkeys — команда игрока") end
    CreateThread(function()
        local cars, err = ownCars(player)
        if not cars then return reply(player, raw, false, err) end
        local count = 0
        for _, car in ipairs(cars) do
            if next(car.keys) then
                for _ in pairs(car.keys) do count = count + 1 end
                for guid in pairs(car.keys) do car.keys[guid] = nil end
                RppVehStore.setKeys(car.id, car.keys)
            end
        end
        for player2, openCar in pairs(trunkOpen) do
            if spawned[openCar] and not rightsOf(player2, spawned[openCar]) then closeTrunksOf(openCar, nil) end
        end
        pushRights()
        reply(player, raw, true, count > 0 and ("Ключи забраны у всех (" .. count .. ").") or "Ключей ни у кого не было.")
    end)
end, false)

-- ---------------------------------------------------------------------------
-- Команды админа (ограниченные: нужен command.<имя> в acl.jsonc)
-- ---------------------------------------------------------------------------
-- /givecar <ID игрока> <Vehicle.запись> [название]
RegisterCommand("givecar", function(player, args, raw)
    player = tonumber(player)
    CreateThread(function()
        local target, record = tonumber(args[1]), args[2]
        if not target or type(record) ~= "string" then
            return reply(player, raw, false, "Использование: /givecar <ID игрока> <Vehicle.запись> [название]")
        end
        if not record:match("^Vehicle%.") then record = "Vehicle." .. record end
        if #record > 128 or not record:match("^Vehicle%.[%w_]+$") then
            return reply(player, raw, false, "Неверная запись машины: " .. record)
        end
        local guid = guidOf(target)
        if not guid then return reply(player, raw, false, "Игрок " .. tostring(target) .. " не на сервере.") end
        local label = table.concat(args, " ", 3)
        if label == "" then label = modelLabel(record) end
        label = label:sub(1, 64)
        local car, err = RppVehStore.create(guid, record, label)
        if not car then return reply(player, raw, false, "Не удалось выдать: " .. tostring(err)) end
        log(("car #%d (%s) given to %s by %s"):format(car.id, record, guid, tostring(player)))
        notify(target, "success", "Вам выдали машину «" .. label .. "». Вызвать: /garage.")
        reply(player, raw, true, ("Машина #%d «%s» выдана игроку %d."):format(car.id, label, target))
    end)
end, true)

-- /delcar <номер машины в базе> — удалить машину вместе с багажником.
RegisterCommand("delcar", function(player, args, raw)
    player = tonumber(player)
    CreateThread(function()
        local carId = tonumber(args[1])
        if not carId then return reply(player, raw, false, "Использование: /delcar <номер машины> (номер — в /cars)") end
        local car = RppVehStore.get(carId)
        if not car then return reply(player, raw, false, "Машины #" .. carId .. " нет.") end
        parkEntry(carId)
        RppVehStore.delete(carId)
        pcall(function()
            local p = Open77.exports.call("rpp_inventory", "deleteContainer", "vehicle:" .. carId)
            if p then p:await() end
        end)
        pushRights()
        reply(player, raw, true, ("Машина #%d «%s» удалена."):format(carId, car.label))
    end)
end, true)

-- /cars <ID игрока> — машины игрока с номерами в базе.
RegisterCommand("cars", function(player, args, raw)
    player = tonumber(player)
    CreateThread(function()
        local target = tonumber(args[1])
        local guid = target and guidOf(target)
        if not guid then return reply(player, raw, false, "Использование: /cars <ID игрока онлайн>") end
        local cars = RppVehStore.listByOwner(guid) or {}
        local parts = {}
        for _, car in ipairs(cars) do parts[#parts + 1] = ("#%d %s (%s)"):format(car.id, car.label, car.record) end
        reply(player, raw, true, #parts > 0 and table.concat(parts, "; ") or "У игрока нет машин.")
    end)
end, true)

RegisterNetEvent("chat:ready", function()
    TriggerClientEvent("chat:addSuggestions", source, {
        { command = "/garage", help = "Гараж: выбрать свою машину и вызвать её к себе.", parameters = {} },
        { command = "/carkeys", help = "Забрать ключи от всех своих машин у всех.", parameters = {} },
    })
end)

-- ---------------------------------------------------------------------------
-- Жизненный цикл
-- ---------------------------------------------------------------------------
RegisterNetEvent("rpp_vehicles:hello", function()
    pushRights()
end)

AddEventHandler("onPlayerDisconnected", function(playerIdStr)
    local player = tonumber(playerIdStr)
    if not player then return end
    trunkOpen[player], lastAction[player] = nil, nil
    CreateThread(function() -- parkEntry ждёт ответа rpp_inventory
        if cfg.parkOnDisconnect then
            for carId, entry in pairs(spawned) do
                if entry.ownerPlayer == player then parkEntry(carId) end
            end
        end
        pushRights()
    end)
end)

-- Раз в секунду: багажник закрывается, если отошли или потеряли права;
-- машина, пропавшая из мира, забывается.
CreateThread(function()
    while true do
        Wait(1000)
        local lost = false
        for carId, entry in pairs(spawned) do
            if not vehicleSnapshot(entry.vehicleId) then forget(carId); lost = true end
        end
        if lost then pushRights() end
        for player, carId in pairs(trunkOpen) do
            local entry = spawned[carId]
            local reason = nil
            if not entry then reason = "Багажник закрыт: машины нет."
            elseif not rightsOf(player, entry) then reason = "Багажник закрыт: у вас нет ключей."
            else
                local d = distanceTo(player, entry.vehicleId)
                if d and d > cfg.trunkKeepDistance then reason = "Багажник закрыт: вы отошли." end
            end
            if not reason then
                -- Окно закрыл сам игрок?
                local ok, key = pcall(function()
                    local p = Open77.exports.call("rpp_inventory", "openedContainer", player)
                    return p and p:await() or nil
                end)
                if ok and key ~= "vehicle:" .. carId then trunkOpen[player] = nil end
            else
                trunkOpen[player] = nil
                pcall(function()
                    local p = Open77.exports.call("rpp_inventory", "closeContainer", player, reason)
                    if p then p:await() end
                end)
            end
        end
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then return end
    for carId, entry in pairs(spawned) do
        pcall(Open77.vehicles.remove, entry.vehicleId)
        spawned[carId] = nil
    end
end)

CreateThread(function()
    RppVehStore.init()
    log("ready")
end)
