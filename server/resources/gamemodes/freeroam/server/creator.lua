-- Freeroam makes characters in the world: no main-menu creator. A new player spawns with the male
-- body, and open77_creator opens by itself to build the character; /creator reopens it any time.
-- This is the reference setup for other servers: one call when the gamemode starts.
-- Called by the join spawn once the player is placed (server/main.lua).
function FreeroamCreatorPlaced(playerId)
    pcall(function() return exports.open77_creator:playerPlaced(playerId) end)
end

CreateThread(function()
    local reason
    -- Exports answer once every resource of the start has finished loading (resource_preparing).
    for _ = 1, 200 do
        local ok, result, why = pcall(function() return exports.open77_appearance:setCreationMode("runtime") end)
        if ok and result then
            -- The creator opens once the join spawn has landed (FreeroamCreatorPlaced above).
            if FreeroamConfig and FreeroamConfig.spawn and FreeroamConfig.spawn.forceOnJoin then
                pcall(function() return exports.open77_creator:expectPlacement(true) end)
            end
            return
        end
        reason = ok and why or result
        Wait(50)
    end
    print("[freeroam] runtime character creation unavailable: " .. tostring(reason))
end)
