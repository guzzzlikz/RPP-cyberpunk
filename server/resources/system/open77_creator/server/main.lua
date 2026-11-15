-- open77_creator server: when the creator opens, and what a confirmed look becomes.
--
-- The look itself is owned by open77_appearance: a confirmed body goes through
-- exports.open77_appearance:setBodyFamily(player, family, body, true), which puts the player in it,
-- shows it to everyone, stores it per character and body type, and saves the body type. This
-- resource keeps the creator CHOICES next to it (open77_creator_looks), so reopening the creator
-- shows exactly what the player picked.

local C = CreatorConfig

local SCHEMA_SQL = [[
CREATE TABLE IF NOT EXISTS open77_creator_looks (
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    character_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'default',
    body_family VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    choices_json MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, character_key, body_family),
    CONSTRAINT chk_open77_creator_family CHECK (body_family IN ('female', 'male'))
) ENGINE=InnoDB
]]

local dbReady = false
-- A gamemode that places joining players (a spawn point, a teleport) says so with expectPlacement:
-- the creator then waits for its playerPlaced before opening, so that the shot is not framed where
-- the player will be teleported away from.
local placementSignals = false
local placed = {}
local looks = {}      -- player -> { male = choices, female = choices, done = bool }
local pendingOpen = {} -- player -> reason, until the client says it can open
local saving = {}

local function identity(player)
    local ok, info = pcall(function() return exports.open77_appearance:character(player) end)
    if ok and type(info) == "table" and info.userId then return info end
    return nil
end

local function validChoices(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for part, options in pairs(value) do
        if part ~= "head" and part ~= "body" and part ~= "arms" then return false end
        if type(options) ~= "table" then return false end
        for name, index in pairs(options) do
            count = count + 1
            if type(name) ~= "string" or #name > 64 or type(index) ~= "number" or index % 1 ~= 0
                or index < 0 or index > 4096 or count > 2048 then return false end
        end
    end
    return true
end

local function loadLooks(player, info)
    looks[player] = { done = false }
    if not dbReady or not info then return end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT body_family, choices_json FROM open77_creator_looks
        WHERE user_id = @user AND character_key = @character
    ]], { user = info.userId, character = info.characterKey })
    if not ok or type(rows) ~= "table" then return end
    for _, row in ipairs(rows) do
        local choices = json.decode(tostring(row.choices_json or ""))
        if validChoices(choices) then
            looks[player][tostring(row.body_family)] = choices
            looks[player].done = true
        end
    end
end

local function openFor(player, reason)
    local stored = looks[player] or {}
    TriggerClientEvent("open77_creator:open", player, reason, { male = stored.male, female = stored.female })
end

-- open77_appearance resolved the character: remember its looks, and open the creator for a new
-- character (or one that never confirmed a look) once the client is in the world.
AddEventHandler("open77:appearance:characterReady", function(player, info)
    CreateThread(function()
        loadLooks(player, info)
        if C.openForNewCharacters and info and info.runtimeCreation and (info.isNew or not looks[player].done) then
            pendingOpen[player] = info.isNew and "new_character" or "unfinished"
            TriggerClientEvent("open77_creator:pending", player, pendingOpen[player])
        end
    end)
end)

-- The client is in the world and its body settled: it asks whether a creator is waiting.
RegisterNetEvent("open77_creator:ready", function()
    local player = source
    local reason = pendingOpen[player]
    if reason and placementSignals and not placed[player] then return end -- the gamemode places the player first
    if reason then
        pendingOpen[player] = nil
        openFor(player, reason)
    end
end)

RegisterNetEvent("open77_creator:save", function(family, body, choices)
    local player = source
    print(("[open77_creator] save received from player=%s family=%s payload=%s"):format(tostring(player),
        tostring(family), type(body) == "string" and (#body .. " bytes") or type(body)))
    -- Every path answers: the client waits for open77_creator:saved.
    if saving[player] then return TriggerClientEvent("open77_creator:saved", player, false, "busy") end
    -- The look arrives as one JSON string { body, choices } (a network event carries at most 1024
    -- values, which a detailed look exceeded as tables); the two-table form still works.
    if type(body) == "string" then
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= "table" then
            return TriggerClientEvent("open77_creator:saved", player, false, "invalid_look")
        end
        body, choices = data.body, data.choices
    end
    family = tostring(family or "")
    if (family ~= "male" and family ~= "female") or type(body) ~= "table" or body.family ~= family
        or not validChoices(choices) then
        return TriggerClientEvent("open77_creator:saved", player, false, "invalid_look")
    end
    saving[player] = true
    CreateThread(function()
        -- Whatever fails in here, the player gets an answer and can save again.
        local done, result, reason = pcall(function()
            local ok, why = exports.open77_appearance:setBodyFamily(player, family, body, true)
            if not ok then return false, why or "rejected" end
            looks[player] = looks[player] or {}
            looks[player][family] = choices
            looks[player].done = true
            local info = identity(player)
            if dbReady and info then
                local stored, failure = pcall(MySQL.update.await, [[
                    INSERT INTO open77_creator_looks (user_id, character_key, body_family, choices_json)
                    VALUES (@user, @character, @family, @choices)
                    ON DUPLICATE KEY UPDATE choices_json = VALUES(choices_json)
                ]], { user = info.userId, character = info.characterKey, family = family, choices = json.encode(choices) })
                if not stored then print("[open77_creator] choices not stored: " .. tostring(failure)) end
            end
            return true
        end)
        saving[player] = nil
        if not done then
            print(("[open77_creator] save failed for player=%s: %s"):format(tostring(player), tostring(result)))
            return TriggerClientEvent("open77_creator:saved", player, false, "save_error")
        end
        if not result then
            print(("[open77_creator] save refused for player=%s: %s"):format(tostring(player), tostring(reason)))
            return TriggerClientEvent("open77_creator:saved", player, false, reason)
        end
        print(("[open77_creator] player=%s saved a %s look"):format(tostring(player), family))
        TriggerClientEvent("open77_creator:saved", player, true)
    end)
end)

-- The gamemode places joining players and will call playerPlaced (see `placementSignals`).
--   exports.open77_creator:expectPlacement(true)
exports("expectPlacement", function(on)
    placementSignals = on ~= false
    return true
end)

-- The gamemode put the player where they play (its join spawn landed): a waiting creator may open
-- once the client is still again.
--   exports.open77_creator:playerPlaced(playerId)
exports("playerPlaced", function(player)
    player = tonumber(player)
    if not player then return false end
    placed[player] = true
    if pendingOpen[player] then TriggerClientEvent("open77_creator:settle", player) end
    return true
end)

-- Opens the creator for a player (other resources: a barber, a ripperdoc, a character menu).
--   exports.open77_creator:open(playerId)
exports("open", function(player)
    player = tonumber(player)
    if not player or not GetPlayerName(player) then return false, "invalid_player" end
    openFor(player, "requested")
    return true
end)

if C.command and C.command ~= "" then
    RegisterCommand(C.command, function(player)
        if not player or player <= 0 then return end
        openFor(player, "command")
    end, false)
end

-- Laboratory only: drives the creator's own handlers from the server console or the debug bridge.
if type(GetConvar) == "function" and GetConvar("open77_creator_debug", "false") == "true" then
    RegisterCommand("creatordebug", function(player, args)
        if not player or player <= 0 then return end
        TriggerClientEvent("open77_creator:debug", player, args[1] or "", args[2], args[3])
    end, false)
end

AddEventHandler("playerDropped", function()
    local player = source
    looks[player], pendingOpen[player], saving[player], placed[player] = nil, nil, nil, nil
end)

CreateThread(function()
    local ok, reason = pcall(MySQL.update.await, SCHEMA_SQL)
    if not ok then
        return print("[open77_creator] no database, looks last for the session only: " .. tostring(reason))
    end
    dbReady = true
    print("[open77_creator] database ready")
end)
