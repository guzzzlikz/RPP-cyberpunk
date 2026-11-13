-- Хранилище паспортов и знакомств на Open77.kvp (встроенное key-value
-- хранилище сервера; MySQL не нужна). Ключ игрока — GetPlayerIdentifier(),
-- GUID, привязанный к аккаунту Open77, а не ник.
--
--   rpp.citizen.seq           следующий свободный номер жителя
--   rpp.citizen.<guid>        {"v":1,"id":1001,"first":"Имя","last":"Фамилия"}
--   rpp.known.<guid>          {"v":1,"guids":["<guid>", ...]}
RppStore = {}

local JSON = json or (Open77 and Open77.json)
local VERSION = 1
local SEQ_KEY = "rpp.citizen.seq"
local MAX_KNOWN = 2000

local function safe(guid)
    return (tostring(guid):gsub("[^%w%-_]", "_"))
end

local function read(key)
    local ok, text, reason = pcall(Open77.kvp.get, key)
    if not ok then return nil, tostring(text) end
    if text == nil or text == "" then return nil, reason end
    local decoded = JSON.decode(text)
    if type(decoded) ~= "table" then return nil, "corrupt" end
    return decoded
end

local function write(key, value)
    local text = JSON.encode(value)
    if type(text) ~= "string" then return false, "encode_failed" end
    local ok, stored, reason = pcall(Open77.kvp.set, key, text)
    if not ok then return false, tostring(stored) end
    if stored ~= true then return false, tostring(reason or "store_unavailable") end
    return true
end

function RppStore.getCitizen(guid)
    local record = read("rpp.citizen." .. safe(guid))
    if type(record) ~= "table" or tonumber(record.id) == nil
        or type(record.first) ~= "string" or type(record.last) ~= "string" then
        return nil
    end
    return { id = math.floor(tonumber(record.id)), first = record.first, last = record.last }
end

function RppStore.saveCitizen(guid, citizen)
    return write("rpp.citizen." .. safe(guid), {
        v = VERSION, id = citizen.id, first = citizen.first, last = citizen.last,
    })
end

function RppStore.deleteCitizen(guid)
    local ok, result, reason = pcall(Open77.kvp.delete, "rpp.citizen." .. safe(guid))
    if not ok then return false, tostring(result) end
    return result ~= false, reason
end

--- Выдаёт следующий номер. Сервер однопоточный для Lua, поэтому
--- чтение-увеличение-запись здесь атомарны относительно других обработчиков.
function RppStore.nextCitizenId()
    local ok, text = pcall(Open77.kvp.get, SEQ_KEY)
    local current = ok and tonumber(text) or nil
    if current == nil or current < RppIdentityConfig.firstCitizenId then
        current = RppIdentityConfig.firstCitizenId
    end
    local called, stored = pcall(Open77.kvp.set, SEQ_KEY, tostring(current + 1))
    if not called or stored ~= true then return nil, "sequence_store_failed" end
    return current
end

function RppStore.getKnown(guid)
    local record = read("rpp.known." .. safe(guid))
    local set = {}
    if type(record) == "table" and type(record.guids) == "table" then
        for _, other in ipairs(record.guids) do
            if type(other) == "string" then set[other] = true end
        end
    end
    return set
end

function RppStore.saveKnown(guid, set)
    local list = {}
    for other in pairs(set) do
        list[#list + 1] = other
        if #list >= MAX_KNOWN then break end
    end
    table.sort(list)
    return write("rpp.known." .. safe(guid), { v = VERSION, guids = list })
end
