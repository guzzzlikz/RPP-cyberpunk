-- rpp_music, клиент: невидимое WebUI-окно с <audio>, которое играет трек
-- при заходе и затихает после появления персонажа.
local cfg = RppMusicConfig
local RESOURCE = GetCurrentResourceName()
local MUTE_KEY = "rpp_music.muted"

local page, ready, playing = nil, false, false
local queue = {}

local function log(text) print("[" .. RESOURCE .. "] " .. text) end

local function send(event, payload)
    if not page then return end
    if not ready then queue[#queue + 1] = { event, payload }; return end
    page:send("music:" .. event, payload or {})
end

local function muted()
    if type(Open77.kvp) ~= "table" then return false end
    local ok, value = pcall(Open77.kvp.get, MUTE_KEY, false)
    return ok and (value == true or value == "1")
end

local function setMuted(value)
    if type(Open77.kvp) == "table" then pcall(Open77.kvp.set, MUTE_KEY, value and "1" or "0") end
end

local function inWorld()
    if type(Open77.session) ~= "table" or type(Open77.session.characterBootstrap) ~= "function" then return false end
    local ok, bootstrap = pcall(Open77.session.characterBootstrap)
    return ok and type(bootstrap) == "table" and bootstrap.phase == "ready"
end

local function ensurePage()
    if page then return true end
    local reason
    page, reason = WebUI.create({
        entry = "web/index.html", layer = "system",
        width = 8, height = 8, fps = 1, zIndex = -200,
        transparent = true, visible = true,
    })
    if not page then
        log("WebUI failed: " .. tostring(reason))
        return false
    end
    page:on("music:ready", function()
        ready = true
        for _, item in ipairs(queue) do page:send("music:" .. item[1], item[2] or {}) end
        queue = {}
    end)
    page:on("music:status", function(payload)
        if type(payload) ~= "table" then return end
        if payload.state == "error" then
            log("track failed: " .. tostring(payload.src) .. " — " .. tostring(payload.reason))
        elseif payload.state == "ended" then
            playing = false
        end
    end)
    return true
end

local function stop(fadeMs)
    if not playing then return end
    playing = false
    send("stop", { fadeOutMs = fadeMs or cfg.fadeOutMs })
end

local stopToken = 0
local function scheduleStop()
    if not playing then return end
    local delay = cfg.stopAfterWorldReadySec
    if delay < 0 then
        send("noloop") -- доиграть трек до конца
        return
    end
    stopToken = stopToken + 1
    local token = stopToken
    CreateThread(function()
        Wait(math.floor(delay * 1000))
        if token == stopToken then stop() end
    end)
end

local function start()
    if not cfg.enabled or playing or muted() or #cfg.tracks == 0 then return end
    local already = inWorld()
    if cfg.skipIfAlreadyInWorld and already then return end
    if not ensurePage() then return end
    playing = true
    local track = cfg.tracks[math.random(#cfg.tracks)]
    send("play", {
        src = track, volume = cfg.volume, fadeInMs = cfg.fadeInMs,
        loop = cfg.loop and cfg.stopAfterWorldReadySec >= 0,
    })
    if already then scheduleStop() end
end

AddEventHandler("onClientResourceStart", function(name)
    if name == RESOURCE then start() end
end)

AddEventHandler("open77:worldReady", scheduleStop)

-- /music — выключить сейчас и больше не включать; ещё раз — включить снова.
RegisterCommand("music", function()
    if muted() then
        setMuted(false)
        TriggerEvent("chat:addMessage", { type = "system", text = "Музыка при заходе включена." })
    else
        setMuted(true)
        stop(1200)
        TriggerEvent("chat:addMessage", { type = "system", text = "Музыка при заходе выключена. /music — включить снова." })
    end
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    page, ready, playing = nil, false, false
end)
