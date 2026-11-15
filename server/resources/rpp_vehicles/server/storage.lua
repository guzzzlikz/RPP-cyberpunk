-- Хранилище личных машин.
--
-- Основное: MySQL (база `open77`). Таблица создаётся сама:
--   rpp_vehicles  id (AUTO_INCREMENT), owner (GetPlayerIdentifier владельца),
--                 record (Vehicle.*), label, key_holders (JSON: { [guid] = true }),
--                 created_at
-- Запасное, если базы нет: Open77.kvp, ключ rpp.vehicles (весь список одним JSON).
-- Багажник хранит rpp_inventory (таблица rpp_containers, ключ vehicle:<id>).
--
-- Функции, кроме backend(), ждут ответа базы: вызывать внутри CreateThread.
RppVehStore = {}

local JSON = json or (Open77 and Open77.json)
local backend = nil -- nil | "mysql" | "kvp"
local KVP_KEY = "rpp.vehicles"

local function log(text) print("[rpp_vehicles] " .. text) end

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS rpp_vehicles (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    label VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    key_holders TEXT CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY owner_idx (owner)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

function RppVehStore.init()
    if MySQL ~= nil then
        local ok, err = pcall(MySQL.update.await, SCHEMA)
        if ok then
            backend = "mysql"
            log("vehicles are stored in MySQL (table rpp_vehicles)")
            return backend
        end
        log("MySQL unavailable, vehicles fall back to kvp: " .. tostring(err))
    else
        log("no database.access, vehicles are stored in kvp")
    end
    backend = "kvp"
    return backend
end

function RppVehStore.backend() return backend end

local function waitReady()
    while backend == nil do Wait(50) end
end

local function decodeKeys(text)
    local keys = JSON.decode(tostring(text or ""))
    local out = {}
    if type(keys) == "table" then
        for guid, value in pairs(keys) do
            if value == true and type(guid) == "string" then out[guid] = true end
        end
    end
    return out
end

local function row(id, owner, record, label, keys)
    return { id = math.floor(tonumber(id)), owner = tostring(owner), record = tostring(record),
        label = tostring(label), keys = keys or {} }
end

-- kvp: { nextId, cars = { ["<id>"] = { owner, record, label, keys } } }
local function kvpRead()
    local ok, text = pcall(Open77.kvp.get, KVP_KEY)
    if not ok then return nil, tostring(text) end
    if text == nil or text == "" then return { nextId = 1, cars = {} } end
    local data = JSON.decode(text)
    if type(data) ~= "table" or type(data.cars) ~= "table" then return nil, "corrupt" end
    data.nextId = math.floor(tonumber(data.nextId) or 1)
    return data
end

local function kvpWrite(data)
    local text = JSON.encode(data)
    if type(text) ~= "string" then return false, "encode_failed" end
    local ok, stored, reason = pcall(Open77.kvp.set, KVP_KEY, text)
    if not ok then return false, tostring(stored) end
    if stored ~= true then return false, tostring(reason or "store_unavailable") end
    return true
end

--- Машины владельца: список { id, owner, record, label, keys }. Второе значение — ошибка.
function RppVehStore.listByOwner(guid)
    waitReady()
    local list = {}
    if backend == "mysql" then
        local ok, rows = pcall(MySQL.query.await,
            "SELECT id, owner, record, label, key_holders FROM rpp_vehicles WHERE owner = ? ORDER BY id", { guid })
        if not ok then return nil, tostring(rows) end
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            list[#list + 1] = row(r.id, r.owner, r.record, r.label, decodeKeys(r.key_holders))
        end
        return list
    end
    local data, err = kvpRead()
    if not data then return nil, err end
    for id, car in pairs(data.cars) do
        if car.owner == guid then list[#list + 1] = row(id, car.owner, car.record, car.label, car.keys) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- Одна машина по id или nil.
function RppVehStore.get(id)
    waitReady()
    if backend == "mysql" then
        local ok, r = pcall(MySQL.single.await,
            "SELECT id, owner, record, label, key_holders FROM rpp_vehicles WHERE id = ? LIMIT 1", { id })
        if not ok then return nil, tostring(r) end
        if type(r) ~= "table" then return nil end
        return row(r.id, r.owner, r.record, r.label, decodeKeys(r.key_holders))
    end
    local data, err = kvpRead()
    if not data then return nil, err end
    local car = data.cars[tostring(id)]
    return car and row(id, car.owner, car.record, car.label, car.keys) or nil
end

--- Новая машина. Возвращает её строку или nil, ошибка.
function RppVehStore.create(owner, record, label)
    waitReady()
    if backend == "mysql" then
        local ok, id = pcall(MySQL.insert.await,
            "INSERT INTO rpp_vehicles (owner, record, label, key_holders) VALUES (?, ?, ?, '{}')", { owner, record, label })
        if not ok or type(id) ~= "number" then return nil, tostring(id) end
        return row(id, owner, record, label, {})
    end
    local data, err = kvpRead()
    if not data then return nil, err end
    local id = data.nextId
    data.nextId = id + 1
    data.cars[tostring(id)] = { owner = owner, record = record, label = label, keys = {} }
    local ok, writeErr = kvpWrite(data)
    if not ok then return nil, writeErr end
    return row(id, owner, record, label, {})
end

function RppVehStore.setKeys(id, keys)
    waitReady()
    if backend == "mysql" then
        local ok, err = pcall(MySQL.update.await,
            "UPDATE rpp_vehicles SET key_holders = ? WHERE id = ?", { JSON.encode(next(keys) and keys or {}) or "{}", id })
        return ok, not ok and tostring(err) or nil
    end
    local data, err = kvpRead()
    if not data then return false, err end
    local car = data.cars[tostring(id)]
    if not car then return false, "not_found" end
    car.keys = keys
    return kvpWrite(data)
end

function RppVehStore.delete(id)
    waitReady()
    if backend == "mysql" then
        local ok, err = pcall(MySQL.update.await, "DELETE FROM rpp_vehicles WHERE id = ?", { id })
        return ok, not ok and tostring(err) or nil
    end
    local data, err = kvpRead()
    if not data then return false, err end
    data.cars[tostring(id)] = nil
    return kvpWrite(data)
end
