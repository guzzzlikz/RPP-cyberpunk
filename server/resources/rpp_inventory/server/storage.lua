-- Хранилище инвентарей.
--
-- Основное: MySQL (база `open77`). Таблица создаётся сама:
--   rpp_inventories  user_id (GetPlayerIdentifier), money, data (JSON:
--                    рюкзак, оружие в слотах, надетая одежда), updated_at
-- Запасное, если базы нет: Open77.kvp, ключ rpp.inv.<user_id>.
--
-- Функции, кроме backend(), ждут ответа базы: вызывать внутри CreateThread.
RppInvStore = {}

local JSON = json or (Open77 and Open77.json)
local backend = nil -- nil | "mysql" | "kvp"

local function log(text) print("[rpp_inventory] " .. text) end
local function safe(guid) return (tostring(guid):gsub("[^%w%-_]", "_")) end

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS rpp_inventories (
    user_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    money BIGINT NOT NULL DEFAULT 0,
    data MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

function RppInvStore.init()
    if MySQL ~= nil then
        local ok, err = pcall(MySQL.update.await, SCHEMA)
        if ok then
            backend = "mysql"
            log("inventories are stored in MySQL (table rpp_inventories)")
            return backend
        end
        log("MySQL unavailable, inventories fall back to kvp: " .. tostring(err))
    else
        log("no database.access, inventories are stored in kvp")
    end
    backend = "kvp"
    return backend
end

function RppInvStore.backend() return backend end

local function waitReady()
    while backend == nil do Wait(50) end
end

--- Возвращает { money, data } или nil, если записи нет. Второе значение — ошибка.
function RppInvStore.load(guid)
    waitReady()
    if backend == "mysql" then
        local ok, row = pcall(MySQL.single.await,
            "SELECT money, data FROM rpp_inventories WHERE user_id = ? LIMIT 1", { guid })
        if not ok then return nil, tostring(row) end
        if type(row) ~= "table" then return nil end
        local data = JSON.decode(tostring(row.data or ""))
        return { money = tonumber(row.money) or 0, data = type(data) == "table" and data or {} }
    end
    local ok, text = pcall(Open77.kvp.get, "rpp.inv." .. safe(guid))
    if not ok then return nil, tostring(text) end
    if text == nil or text == "" then return nil end
    local decoded = JSON.decode(text)
    if type(decoded) ~= "table" then return nil, "corrupt" end
    return { money = tonumber(decoded.money) or 0, data = type(decoded.data) == "table" and decoded.data or {} }
end

function RppInvStore.save(guid, money, data)
    waitReady()
    local text = JSON.encode(data)
    if type(text) ~= "string" then return false, "encode_failed" end
    if backend == "mysql" then
        local ok, err = pcall(MySQL.update.await, [[
            INSERT INTO rpp_inventories (user_id, money, data) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE money = VALUES(money), data = VALUES(data)
        ]], { guid, math.floor(money), text })
        return ok, not ok and tostring(err) or nil
    end
    local record = JSON.encode({ money = math.floor(money), data = data })
    local ok, stored, reason = pcall(Open77.kvp.set, "rpp.inv." .. safe(guid), record)
    if not ok then return false, tostring(stored) end
    if stored ~= true then return false, tostring(reason or "store_unavailable") end
    return true
end
