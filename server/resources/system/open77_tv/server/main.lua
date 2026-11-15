-- open77_tv -- server/main.lua: asks clients for a television; everything else is client-side.

local DEFAULT_URL = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

-- /tv [url]: a television in front of the player who typed it.
RegisterCommand("tv", function(source, args)
    if not source or source == 0 then return end
    TriggerClientEvent("open77_tv:here", source, args[1] or DEFAULT_URL)
end, true) -- RPP: только с правом command.tv (как было у open77_media)

-- RPP: штатный open77_tv при старте ставил телевизор перед каждым игроком.
-- На RP-сервере это мешает, поэтому телевизор появляется только по /tv.
