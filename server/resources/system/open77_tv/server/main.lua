-- open77_tv -- server/main.lua: asks clients for a television; everything else is client-side.

local DEFAULT_URL = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

-- /tv [url]: a television in front of the player who typed it.
RegisterCommand("tv", function(source, args)
    if not source or source == 0 then return end
    TriggerClientEvent("open77_tv:here", source, args[1] or DEFAULT_URL)
end, false)

-- Started: everyone already in the session gets one in front of them.
AddEventHandler("onResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    SetTimeout(3000, function()
        TriggerClientEvent("open77_tv:here", -1, DEFAULT_URL)
    end)
end)
