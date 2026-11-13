-- The voice HUD on NativeUI (ui/voice.rml): one compact line in the bottom-right
-- corner. client/main.lua builds the payload and talks to this module as it
-- talked to the old WebUI page: page:on("open-voice:ready", fn),
-- page:send("open-voice:update", payload), page:show(), page:hide().
-- Presentation only: every decision (state, reach, errors) stays in main.lua and
-- on the server. Only the values that changed reach the document.
OpenVoiceHud = {}
local V = OpenVoiceHud

local STATES = { idle = true, detected = true, talking = true, muted = true, offline = true }
local STATE_LABELS = {
    idle = "Listening",
    detected = "Signal detected",
    talking = "Transmitting",
    muted = "Mic disabled",
    offline = "Voice offline",
}
local SEGMENTS = 12
local PIPS = 8 -- the server allows up to 8 presets; the document keeps 8 slots (no row is ever removed)

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function bounded(v, max) return tostring(v == nil and "" or v):sub(1, max) end

function V.safeColor(value)
    local text = tostring(value or "")
    return text:match("^#%x%x%x%x%x%x$") and text or "#FCEE0A"
end

function V.formatDistance(value)
    local metres = math.max(0, tonumber(value) or 0)
    if metres > 0 and metres < 10 and metres ~= math.floor(metres) then
        return ("%.1f"):format(metres)
    end
    return tostring(math.floor(metres + 0.5))
end

function V.resolveState(p, level)
    local supplied = bounded(p.state, 16):lower()
    if STATES[supplied] then return supplied end
    if p.configured ~= true or p.available == false then return "offline" end
    if p.captureEnabled ~= true then return "muted" end
    if p.transmitting == true then return "talking" end
    if p.microphoneDetected == true or level > 0.025 then return "detected" end
    return "idle"
end

--- The document's model from the payload client/main.lua publishes.
function V.model(p)
    p = type(p) == "table" and p or {}
    local level = clamp(tonumber(p.inputLevel) or 0, 0, 1)
    local state = V.resolveState(p, level)
    local heard = math.max(0, math.floor((tonumber(p.activeTalkers) or 0) + 0.5))
    local count = clamp(math.floor(tonumber(p.modeCount) or 1), 1, PIPS)
    local index = clamp(math.floor(tonumber(p.modeIndex) or 1), 1, count)
    local pips = {}
    for i = 1, PIPS do pips[i] = { used = i <= count, on = i <= index } end
    local err = bounded(p.error, 80)
    local enabled = state ~= "muted" and state ~= "offline"
    return {
        ready = true,
        visible = p.visible ~= false,
        state = state,
        stateLabel = STATE_LABELS[state],
        activation = p.activation == "vad" and "VAD" or "PTT",
        lit = enabled and math.floor(level * SEGMENTS + 0.5) or 0,
        label = bounded(p.mode or p.modeName or "Voice", 24):upper(),
        modeName = bounded(p.modeName or p.mode or "normal", 24):lower(),
        distance = V.formatDistance(p.distance),
        color = V.safeColor(p.color),
        key = bounded(p.key or "F11", 12):upper(),
        pips = pips,
        heard = heard,
        error = err,
        hasError = #err > 0,
    }
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, x in pairs(a) do if not same(x, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
V.same = same

local function defaults()
    local pips = {}
    for i = 1, PIPS do pips[i] = { used = i <= 3, on = i <= 2 } end
    return {
        ready = false, shown = false, visible = true, state = "offline", stateLabel = STATE_LABELS.offline,
        activation = "PTT", lit = 0, label = "ОБЫЧНО", modeName = "normal", distance = "20", color = "#FCEE0A",
        key = "F11", pips = pips, heard = 0, error = "", hasError = false,
    }
end

-- The line drifts a little against the camera's turns, like the HUD wings above it.
local FLOAT = { stiffness = 7, trail = 0.08, trailMax = 18, turn = 0.02, turnMax = 3, breath = { 0.8, 1.6 } }
V.FLOAT = FLOAT

local function cameraYawPitch()
    if type(Open77.camera) ~= "table" or type(Open77.camera.view) ~= "function" then return nil end
    local ok, v = pcall(Open77.camera.view)
    local f = ok and type(v) == "table" and v.forward
    if type(f) ~= "table" or (math.abs(f.x or 0) + math.abs(f.y or 0)) < 1e-4 then return nil end
    return math.deg(math.atan(-f.x, f.y)), math.deg(math.asin(clamp(f.z or 0, -1, 1)))
end

--- A surface with the page API client/main.lua uses: on, send, show, hide, destroy.
function V.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    if type(Open77.ui.loadFont) == "function" then pcall(Open77.ui.loadFont, "ui/fonts/Play-Bold.ttf", "RppPlay", true) end -- RPP: Cyrillic fallback face (docs/ui-theme.md)
    local ui, why = Open77.ui.create({
        document = "ui/voice.rml", layer = "hud", zIndex = 12, visible = true,
        models = { voice = defaults() },
    })
    if not ui then return nil, why end

    local page = { handlers = {} }
    local shown = nil      -- the model the document holds
    local wanted = true    -- show()/hide() from main.lua
    local covered = false  -- another interface holds the cursor
    local alive = true

    local function setShown()
        local value = wanted and not covered and (shown == nil or shown.visible ~= false)
        ui:set("voice", "shown", value)
    end

    local function ready()
        shown = nil
        local fn = page.handlers["open-voice:ready"]
        if fn then fn() end
    end
    ui:onEvent("loaded", ready)
    ui:onEvent("reloaded", ready)
    ui:onEvent("error", function(name, detail)
        print("[open-voice] HUD " .. tostring(name) .. ": " .. tostring(detail and detail.message))
    end)

    function page.on(_, name, fn) page.handlers[name] = fn end
    function page.show() wanted = true; ui:show(); setShown() end
    function page.hide() wanted = false; setShown(); ui:hide() end

    function page.send(_, name, payload)
        if name ~= "open-voice:update" then return end
        local m = V.model(payload)
        local changed = {}
        for k, v in pairs(m) do
            if not shown or not same(shown[k], v) then changed[k] = v end
        end
        if not next(changed) then return end
        local modeChanged = shown and shown.modeName ~= m.modeName
        local errorRaised = m.hasError and (not shown or shown.error ~= m.error)
        ui:merge("voice", changed)
        shown = m
        if changed.visible ~= nil then setShown() end
        -- a new range: the label and the distance drop in, the rule flashes, the pips pop
        if modeChanged then
            ui:animate("#range-label, #range-reach", { from = { opacity = 0, y = -9 }, to = { opacity = 1, y = 0 },
                spring = { duration = 0.42, bounce = 0.32 }, stagger = 0.05 })
            ui:animate("#rule", { from = { scaleY = 1.7 }, to = { scaleY = 1 }, spring = { duration = 0.45, bounce = 0.4 } })
            ui:animate("#pips", { from = { scale = 1.35 }, to = { scale = 1 }, spring = { duration = 0.4, bounce = 0.45 } })
        end
        if errorRaised then
            ui:animate("#error", { from = { x = 18 }, to = { x = 0 }, spring = { duration = 0.35, bounce = 0.35 } })
        end
    end

    -- another interface holds the cursor (pause menu, inventory, phone): step aside
    CreateThread(function()
        while alive do
            Wait(150)
            local busy = false
            if type(Open77.input) == "table" and type(Open77.input.isCaptured) == "function" then
                local ok, _, cursor = pcall(Open77.input.isCaptured)
                busy = ok and cursor == true
            end
            if busy ~= covered then
                covered = busy
                setShown()
            end
        end
    end)

    -- the float: one projection per frame at most, only when it moved
    CreateThread(function()
        local cfg = FLOAT
        local yaw0, pitch0, at0 = nil, nil, GetGameTimer()
        local sx, sy, ry = 0, 0, 0
        local sent = nil
        local phase = math.random() * 6.28
        while alive do
            Wait(0)
            local at = GetGameTimer()
            local dt = math.max(0.001, math.min(0.1, (at - at0) / 1000))
            at0 = at
            if wanted and not covered then
                local yaw, pitch = cameraYawPitch()
                local yawVel, pitchVel = 0, 0
                if yaw and yaw0 then
                    yawVel = ((yaw - yaw0 + 540) % 360 - 180) / dt
                    pitchVel = (pitch - pitch0) / dt
                end
                yaw0, pitch0 = yaw, pitch
                local k = 1 - math.exp(-dt * cfg.stiffness)
                sx = sx + (clamp(yawVel * cfg.trail, -cfg.trailMax, cfg.trailMax) - sx) * k
                sy = sy + (clamp(-pitchVel * cfg.trail * 0.7, -cfg.trailMax * 0.7, cfg.trailMax * 0.7) - sy) * k
                ry = ry + (clamp(-yawVel * cfg.turn, -cfg.turnMax, cfg.turnMax) - ry) * k
                local fy = math.sin(at / 1000 * cfg.breath[1] * 6.2832 / 6 + phase) * cfg.breath[2]
                local spec = {
                    rotateY = math.floor(ry * 100 + 0.5) / 100,
                    offset = { math.floor(sx * 10 + 0.5) / 10, math.floor((sy + fy) * 10 + 0.5) / 10, 0 },
                    perspective = 1600, origin = { 0.9, 0.9 },
                }
                local key = ("%.2f %.1f %.1f"):format(spec.rotateY, spec.offset[1], spec.offset[2])
                if key ~= sent then
                    sent = key
                    ui:projection(spec)
                end
            else
                yaw0 = nil
            end
        end
    end)

    function page.destroy()
        alive = false
        pcall(ui.destroy, ui)
    end
    return page
end
