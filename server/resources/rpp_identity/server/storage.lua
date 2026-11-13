-- Хранилище паспортов и знакомств.
--
-- Основное: MySQL (та же база `open77`, где open77_appearance хранит
-- персонажей). Таблицы создаются сами при старте ресурса:
--
--   rpp_citizens        citizen_id (номер жителя, AUTO_INCREMENT с 1001),
--                       user_id (GetPlayerIdentifier — тот же ключ, что
--                       open77_characters.user_id), first_name, last_name
--   rpp_acquaintances   user_id -> known_user_id (по строке на направление)
--
-- Запасное, если базы нет: Open77.kvp (файл kvp.json ресурса на сервере):
--   rpp.citizen.seq / rpp.citizen.<guid> / rpp.known.<guid>
-- Записи из kvp при первом запуске с базой переносятся в MySQL.
--
-- Все функции, кроме ready/backend, ждут ответа базы (*.await), поэтому
-- вызываются только внутри CreateThread.
RppStore = {}

local JSON = json or (Open77 and Open77.json)
local VERSION = 1
local SEQ_KEY = "rpp.citizen.seq"
local MAX_KNOWN = 2000
local backend = nil -- nil (ещё не готово) | "mysql" | "kvp"

local function log(text) print("[rpp_identity] " .. text) end

-- ---------------------------------------------------------------------------
-- kvp
-- ---------------------------------------------------------------------------
local function safe(guid)
    return (tostring(guid):gsub("[^%w%-_]", "_"))
end

local function kvpRead(key)
    local ok, text, reason = pcall(Open77.kvp.get, key)
    if not ok then return nil, tostring(text) end
    if text == nil or text == "" then return nil, reason end
    local decoded = JSON.decode(text)
    if type(decoded) ~= "table" then return nil, "corrupt" end
    return decoded
end

local function kvpWrite(key, value)
    local text = JSON.encode(value)
    if type(text) ~= "string" then return false, "encode_failed" end
    local ok, stored, reason = pcall(Open77.kvp.set, key, text)
    if not ok then return false, tostring(stored) end
    if stored ~= true then return false, tostring(reason or "store_unavailable") end
    return true
end

local function kvpCitizen(record)
    if type(record) ~= "table" or tonumber(record.id) == nil
        or type(record.first) ~= "string" or type(record.last) ~= "string" then
        return nil
    end
    return { id = math.floor(tonumber(record.id)), first = record.first, last = record.last }
end

local function kvpNextId()
    local ok, text = pcall(Open77.kvp.get, SEQ_KEY)
    local current = ok and tonumber(text) or nil
    if current == nil or current < RppIdentityConfig.firstCitizenId then
        current = RppIdentityConfig.firstCitizenId
    end
    local called, stored = pcall(Open77.kvp.set, SEQ_KEY, tostring(current + 1))
    if not called or stored ~= true then return nil, "sequence_store_failed" end
    return current
end

-- ---------------------------------------------------------------------------
-- MySQL
-- ---------------------------------------------------------------------------
local SCHEMA = {
    ([[
CREATE TABLE IF NOT EXISTS rpp_citizens (
    citizen_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    first_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    last_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (citizen_id),
    UNIQUE KEY uq_rpp_citizens_user (user_id)
) ENGINE=InnoDB AUTO_INCREMENT=%d DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]):format(RppIdentityConfig.firstCitizenId),
    [[
CREATE TABLE IF NOT EXISTS rpp_acquaintances (
    user_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    known_user_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, known_user_id)
) ENGINE=InnoDB
]],
}

local function sqlCitizen(row)
    if type(row) ~= "table" or tonumber(row.citizen_id) == nil then return nil end
    return { id = math.floor(tonumber(row.citizen_id)), first = tostring(row.first_name), last = tostring(row.last_name) }
end

-- Перенос записей, накопленных в kvp, пока базы не было.
local function migrateKvp()
    local ok, keys = pcall(Open77.kvp.keys, "rpp.citizen.", 10000)
    if not ok or type(keys) ~= "table" then return end
    local moved = 0
    for _, key in ipairs(keys) do
        local guid = key:sub(#"rpp.citizen." + 1)
        if key ~= SEQ_KEY and guid ~= "" then
            local citizen = kvpCitizen(kvpRead(key))
            if citizen then
                local inserted = MySQL.update.await([[
                    INSERT IGNORE INTO rpp_citizens (citizen_id, user_id, first_name, last_name)
                    VALUES (?, ?, ?, ?)
                ]], { citizen.id, guid, citizen.first, citizen.last })
                if tonumber(inserted) and tonumber(inserted) > 0 then moved = moved + 1 end
            end
            local known = kvpRead("rpp.known." .. guid)
            if type(known) == "table" and type(known.guids) == "table" then
                for _, other in ipairs(known.guids) do
                    if type(other) == "string" then
                        MySQL.update.await("INSERT IGNORE INTO rpp_acquaintances (user_id, known_user_id) VALUES (?, ?)",
                            { guid, other })
                    end
                end
            end
        end
    end
    if moved > 0 then log(("moved %d passport(s) from kvp to MySQL"):format(moved)) end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Выбирает хранилище. Вызывается один раз при старте, в CreateThread.
function RppStore.init()
    if MySQL ~= nil then
        local ok, err = pcall(function()
            for _, statement in ipairs(SCHEMA) do MySQL.update.await(statement) end
        end)
        if ok then
            local migrated, migrateError = pcall(migrateKvp)
            if not migrated then log("kvp -> MySQL migration failed: " .. tostring(migrateError)) end
            backend = "mysql"
            log("passports are stored in MySQL (tables rpp_citizens, rpp_acquaintances)")
            return backend
        end
        log("MySQL unavailable, passports fall back to kvp: " .. tostring(err))
    else
        log("no database.access, passports are stored in kvp")
    end
    backend = "kvp"
    return backend
end

function RppStore.backend() return backend end

--- Ждёт окончания init(). Только внутри CreateThread.
function RppStore.waitReady()
    while backend == nil do Wait(50) end
end

function RppStore.getCitizen(guid)
    RppStore.waitReady()
    if backend == "mysql" then
        local ok, row = pcall(MySQL.single.await,
            "SELECT citizen_id, first_name, last_name FROM rpp_citizens WHERE user_id = ? LIMIT 1", { guid })
        if not ok then log("getCitizen failed: " .. tostring(row)); return nil end
        return sqlCitizen(row)
    end
    return kvpCitizen(kvpRead("rpp.citizen." .. safe(guid)))
end

--- Выдаёт новый номер жителя и сохраняет паспорт. Возвращает citizen или nil, ошибка.
function RppStore.createCitizen(guid, first, last)
    RppStore.waitReady()
    if backend == "mysql" then
        local ok, id = pcall(MySQL.insert.await,
            "INSERT INTO rpp_citizens (user_id, first_name, last_name) VALUES (?, ?, ?)", { guid, first, last })
        if not ok or type(id) ~= "number" then return nil, tostring(id) end
        return { id = math.floor(id), first = first, last = last }
    end
    local id, idError = kvpNextId()
    if not id then return nil, idError end
    local citizen = { id = id, first = first, last = last }
    local saved, saveError = kvpWrite("rpp.citizen." .. safe(guid),
        { v = VERSION, id = id, first = first, last = last })
    if not saved then return nil, saveError end
    return citizen
end

function RppStore.deleteCitizen(guid)
    RppStore.waitReady()
    if backend == "mysql" then
        local ok, err = pcall(MySQL.update.await, "DELETE FROM rpp_citizens WHERE user_id = ?", { guid })
        return ok, not ok and tostring(err) or nil
    end
    local ok, result, reason = pcall(Open77.kvp.delete, "rpp.citizen." .. safe(guid))
    if not ok then return false, tostring(result) end
    return result ~= false, reason
end

function RppStore.getKnown(guid)
    RppStore.waitReady()
    local set = {}
    if backend == "mysql" then
        local ok, rows = pcall(MySQL.query.await,
            "SELECT known_user_id FROM rpp_acquaintances WHERE user_id = ? LIMIT " .. MAX_KNOWN, { guid })
        if not ok then log("getKnown failed: " .. tostring(rows)); return set end
        for _, row in ipairs(rows or {}) do set[tostring(row.known_user_id)] = true end
        return set
    end
    local record = kvpRead("rpp.known." .. safe(guid))
    if type(record) == "table" and type(record.guids) == "table" then
        for _, other in ipairs(record.guids) do
            if type(other) == "string" then set[other] = true end
        end
    end
    return set
end

--- Запоминает, что `guid` знает `other` (одно направление).
--- `set` — полный список знакомых `guid` (нужен только для kvp).
function RppStore.addKnown(guid, other, set)
    RppStore.waitReady()
    if backend == "mysql" then
        local ok, err = pcall(MySQL.update.await,
            "INSERT IGNORE INTO rpp_acquaintances (user_id, known_user_id) VALUES (?, ?)", { guid, other })
        if not ok then log("addKnown failed: " .. tostring(err)) end
        return ok
    end
    local list = {}
    for known in pairs(set) do
        list[#list + 1] = known
        if #list >= MAX_KNOWN then break end
    end
    table.sort(list)
    return kvpWrite("rpp.known." .. safe(guid), { v = VERSION, guids = list })
end
