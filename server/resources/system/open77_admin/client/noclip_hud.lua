-- The admin flight (noclip) strip on NativeUI (ui/noclip.rml).
--
-- client/menu.lua samples the flight at 10 Hz and hands the state here. The strip
-- replaces the WebUI panel the compact menu used to draw (web/menu.html keeps it as
-- the fallback for a client without NativeUI): one thin band at the bottom centre,
-- in the freeroam HUD's language, instead of a block over the view.
NoclipHud = {}
local M = NoclipHud

local MODE_LABELS = { boost = "BOOST x4", slow = "PRECISE x0.25", paused = "INPUT PAUSED" }

local function speedText(value)
    local speed = tonumber(value) or 0
    if speed < 1 then return ("%.2f"):format(speed) end
    if speed < 10 then return ("%.1f"):format(speed) end
    return ("%d"):format(math.floor(speed + 0.5))
end

--- The gauge as a share of the strip: logarithmic, 0.5 m/s .. 2000 m/s.
local function gauge(value)
    local speed = tonumber(value) or 0
    if speed <= 0.5 then return 0 end
    local share = math.log(speed / 0.5) / math.log(2000 / 0.5)
    return math.floor(math.max(0, math.min(1, share)) * 1000 + 0.5) / 10
end

--- The view model for one flight sample (pure; tested in tests/noclip_hud_test.lua).
function M.model(state)
    state = type(state) == "table" and state or {}
    local mode = ""
    if state.paused then mode = "paused" elseif state.boost then mode = "boost" elseif state.slow then mode = "slow" end
    return {
        active = state.active == true,
        speed = speedText(state.effective),
        mode = mode,
        modeLabel = MODE_LABELS[mode] or "",
        gauge = gauge(state.effective),
    }
end

--- Creates the strip, hidden. Returns nil and a reason when NativeUI is unavailable,
--- and the caller falls back to the WebUI panel.
function M.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    local doc, why = Open77.ui.create({ document = "ui/noclip.rml", layer = "hud", zIndex = 12, visible = true,
        models = { noclip = M.model(nil) } })
    if not doc then return nil, why end
    doc:onEvent("error", function(name, detail)
        Open77.log.warn("admin: noclip strip " .. tostring(name) .. ": " .. tostring(detail and detail.message))
    end)
    local shown = M.model(nil)
    local hud = {}
    function hud.update(state)
        local m = M.model(state)
        local changed = {}
        for key, value in pairs(m) do
            if shown[key] ~= value then changed[key] = value end
        end
        if next(changed) then doc:merge("noclip", changed) end
        shown = m
    end
    function hud.destroy()
        if doc then doc:destroy() end
        doc = nil
    end
    return hud
end
