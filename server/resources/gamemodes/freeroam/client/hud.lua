-- The freeroam HUD on NativeUI (ui/hud.rml): vitals bottom-left, weapons and the
-- chat commands bottom-right, both turned toward the centre of the screen, and a
-- head-up speedometer laid back on the road. client/main.lua keeps building the
-- same view (hudView) and talks to this module as it talked to the WebUI page:
-- page:on("freeroam:hud:ready", fn), page:send("freeroam:hud", view). Only the
-- values that changed reach the document (one data-model update each).
FreeroamHud = {}
local H = FreeroamHud

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function whole(v) return math.max(0, math.floor((tonumber(v) or 0) + 0.5)) end
local function ratio(v, m)
    m = tonumber(m) or 0
    return m > 0 and clamp((tonumber(v) or 0) / m, 0, 1) or 0
end

local MELEE = { "melee", "katana", "knife", "blade", "blunt", "machete", "bat", "hammer" }
local function isMelee(category)
    local c = tostring(category or ""):lower()
    for _, word in ipairs(MELEE) do if c:find(word, 1, true) then return true end end
    return false
end

--- The document's model from the view client/main.lua builds (the same rules as web/hud.js).
function H.model(view, previous)
    view = type(view) == "table" and view or {}
    local health = type(view.health) == "table" and view.health or {}
    local stamina = type(view.stamina) == "table" and view.stamina or {}
    local hp = whole(health.value)
    local hpMax = math.max(1, whole(health.maximum) > 0 and whole(health.maximum) or 100)
    local hpRatio = ratio(hp, hpMax)
    local armor = whole(view.armor)
    local m = {
        ready = view.ready == true,
        hp = hp,
        hpMax = hpMax,
        hpPct = math.floor(hpRatio * 1000 + 0.5) / 10,
        critical = hpRatio <= 0.25,
        armor = armor,
        armorPct = math.floor(clamp(armor / 100, 0, 1) * 100 + 0.5),
        staPct = math.floor(ratio(stamina.value, stamina.maximum) * 100 + 0.5),
        hintsVisible = view.ready == true and hp > 0 and view.hintsVisible ~= false,
    }
    -- the ghost bar follows a drop of health after a moment (the damage taken stays visible)
    m.hpGhost = previous and previous.hpGhost and math.max(m.hpPct, previous.hpGhost) or m.hpPct

    -- weapons: the drawn ones, at most two (right hand first)
    local list = type(view.weapons) == "table" and view.weapons or { view.weapon }
    local weapons = {}
    for _, w in ipairs(list) do
        if type(w) == "table" and w.equipped == true and #weapons < 2 then
            local ammoKnown = w.ammoKnown == true and (tonumber(w.capacity) or -1) >= 0
            local magazine, capacity = whole(w.magazine), whole(w.capacity)
            local segs = {}
            if ammoKnown then
                local cap = math.max(1, capacity)
                local count = math.min(40, cap)
                local live = math.floor(clamp(magazine, 0, cap) * count / cap + 0.5)
                for i = 1, count do segs[i] = i <= live end
            end
            weapons[#weapons + 1] = {
                slot = whole(w.slot) > 0 and whole(w.slot) or 1,
                label = tostring(w.label or w.record or "WEAPON"),
                hand = (w.hand == "left" or (tonumber(w.slot) or 0) > 3) and "LEFT" or "RIGHT",
                category = tostring(w.category or (isMelee(w.category) and "MELEE" or "RANGED")),
                state = w.reloading == true and "RELOADING" or (w.drawn == true and "DRAWN" or "HOLSTERED"),
                drawn = w.drawn == true,
                reloading = w.reloading == true,
                melee = isMelee(w.category),
                ammoKnown = ammoKnown,
                magazine = ammoKnown and magazine or 0,
                reserve = (ammoKnown and w.reserveKnown ~= false) and tostring(whole(w.reserve)) or "--",
                low = ammoKnown and capacity > 0 and magazine <= math.ceil(capacity * 0.25),
                segs = segs,
            }
        end
    end
    m.weapons = weapons
    m.weaponCount = #weapons

    local v = type(view.vehicle) == "table" and view.vehicle or {}
    m.inVehicle = v.active == true
    if m.inVehicle then
        local kph = whole(v.speedKph)
        local speedMax = math.max(1, whole(v.speedMaxKph) > 0 and whole(v.speedMaxKph) or 300)
        m.speed = ("%03d"):format(math.min(kph, 999))
        -- the leading zeros are drawn dim, the number lit
        m.speedLead = m.speed:match("^(0*)") or ""
        if m.speedLead == m.speed then m.speedLead = m.speed:sub(1, -2) end
        m.speedNum = m.speed:sub(#m.speedLead + 1)
        m.speedArc = math.floor(ratio(kph, speedMax) * 1000 + 0.5) / 1000
        m.rpm = tostring(whole(v.rpm))
        m.rpmPct = math.floor(ratio(v.rpm, v.rpmMax) * 100 + 0.5)
        m.gear = tostring(v.gearLabel or "N")
        m.integrity = math.floor(clamp(tonumber(v.health) or 1, 0, 1) * 100 + 0.5)
        m.airborne = v.onGround == false
        m.motion = m.airborne and "AIRBORNE" or "ON ROAD"
        m.vehicleLabel = tostring(v.label or "VEHICLE")
    end
    return m
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, x in pairs(a) do if not same(x, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local DEFAULTS = {
    ready = false, hidden = false, hp = 0, hpMax = 100, hpPct = 0, hpGhost = 0, critical = false, hurt = false,
    armor = 0, armorPct = 0, staPct = 0, hintsVisible = false, weapons = {}, weaponCount = 0,
    inVehicle = false, speed = "000", speedLead = "00", speedNum = "0", speedArc = 0, rpm = "0", rpmPct = 0, gear = "N", integrity = 100,
    airborne = false, motion = "ON ROAD", vehicleLabel = "VEHICLE",
}

local function cameraAngles()
    if type(Open77.camera) ~= "table" or type(Open77.camera.view) ~= "function" then return nil end
    local ok, v = pcall(Open77.camera.view)
    local f = ok and type(v) == "table" and v.forward
    if type(f) ~= "table" or (math.abs(f.x or 0) + math.abs(f.y or 0)) < 1e-4 then return nil end
    return math.deg(math.atan(-f.x, f.y)), math.deg(math.asin(clamp(f.z or 0, -1, 1)))
end

-- The two documents float on their own: each is one projection per frame (no relayout).
--   stiffness: how fast it catches up with the camera; trail: dp per degree/second of turn;
--   turn: degrees of yaw per degree/second; breath: { cycles per 6 s, dp }; shake / lean: what moves it
local FLOAT = {
    wings = { stiffness = 7, trail = 0.10, trailMax = 26, turn = 0.025, turnMax = 3.5, pitch = 0.02,
              breath = { 0.9, 2.2 }, shake = true, lean = false, kick = 1.0, perspective = 1600, origin = { 0.5, 0.5 } },
    speedo = { stiffness = 3.2, trail = 0.18, trailMax = 40, turn = 0.05, turnMax = 6, pitch = 0.03,
               breath = { 1.35, 3.0 }, shake = false, lean = true, kick = 0.55, perspective = 1200, origin = { 0.66, 0.72 } },
}
H.FLOAT = FLOAT

local function startFloat(doc, cfg, motion, alive)
    CreateThread(function()
        local yaw0, pitch0, at0 = nil, nil, GetGameTimer()
        local sx, sy, rx, ry = 0, 0, 0, 0
        local sent = nil
        local phase = math.random() * 6.28
        while alive() do
            Wait(0)
            local at = GetGameTimer()
            local dt = math.max(0.001, math.min(0.1, (at - at0) / 1000))
            at0 = at
            local yaw, pitch = cameraAngles()
            local yawVel, pitchVel = 0, 0
            if yaw and yaw0 then
                local d = (yaw - yaw0 + 540) % 360 - 180
                yawVel, pitchVel = d / dt, (pitch - pitch0) / dt
            end
            yaw0, pitch0 = yaw, pitch
            -- it trails the turn (offset against it) and turns a little with it
            local k = 1 - math.exp(-dt * cfg.stiffness)
            sx = sx + (clamp(yawVel * cfg.trail, -cfg.trailMax, cfg.trailMax) - sx) * k
            sy = sy + (clamp(-pitchVel * cfg.trail * 0.7, -cfg.trailMax * 0.7, cfg.trailMax * 0.7) - sy) * k
            ry = ry + (clamp(-yawVel * cfg.turn, -cfg.turnMax, cfg.turnMax) - ry) * k
            local lean = cfg.lean and motion.lean or 0
            rx = rx + (clamp(pitchVel * cfg.pitch, -cfg.turnMax * 0.7, cfg.turnMax * 0.7) + lean - rx) * k
            local jx, jy = 0, 0
            if cfg.shake and motion.shake > 0.05 then
                jx = (math.random() * 2 - 1) * motion.shake
                jy = (math.random() * 2 - 1) * motion.shake * 0.6
            end
            local t = at / 1000
            local fy = math.sin(t * cfg.breath[1] * 6.2832 / 6 + phase) * cfg.breath[2]
            local kick = (motion.kick or 0) * (cfg.kick or 0)
            if kick > 0.01 then
                jx = jx + (math.random() * 2 - 1) * kick * 2.2
                jy = jy + kick * 5 + (math.random() * 2 - 1) * kick * 1.2
            end
            local spec = {
                rotateX = math.floor((rx + kick * 1.6) * 100 + 0.5) / 100, rotateY = math.floor(ry * 100 + 0.5) / 100,
                rotateZ = math.floor((jx * 0.05 + (math.random() * 2 - 1) * kick * 0.35) * 100 + 0.5) / 100,
                offset = { math.floor((sx + jx) * 10 + 0.5) / 10, math.floor((sy + jy + fy) * 10 + 0.5) / 10,
                           math.floor(-kick * 38 * 10 + 0.5) / 10 },
                perspective = cfg.perspective, origin = cfg.origin,
            }
            local key = ("%.2f %.2f %.2f %.1f %.1f %.1f"):format(spec.rotateX, spec.rotateY, spec.rotateZ, spec.offset[1], spec.offset[2], spec.offset[3])
            if key ~= sent and not motion.hidden then
                sent = key
                doc:projection(spec)
            end
        end
    end)
end

--- A surface with the page API client/main.lua uses: on(name, fn), send(name, view).
function H.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    local function makeModels() local t = {} for k, v in pairs(DEFAULTS) do t[k] = v end return t end
    local ui, why = Open77.ui.create({ document = "ui/hud.rml", layer = "hud", zIndex = 10, visible = true, models = { hud = makeModels() } })
    if not ui then return nil, why end
    -- the speedometer is its own document: it floats apart from the vitals and the weapons
    local speedo = Open77.ui.create({ document = "ui/speedo.rml", layer = "hud", zIndex = 11, visible = true, models = { hud = makeModels() } })
    local docs = { ui, speedo }
    local page = { handlers = {} }
    local shown, last = nil, nil
    local ghostAt = 0
    local motion = { shake = 0, kick = 0, lean = 0, speed = nil, speedAt = 0, hidden = false }
    local alive = true

    ui:onEvent("loaded", function()
        local fn = page.handlers["freeroam:hud:ready"]
        if fn then fn() end
    end)
    for _, doc in ipairs(docs) do
        doc:onEvent("error", function(name, detail) print("[freeroam] HUD " .. tostring(name) .. ": " .. tostring(detail and detail.message)) end)
    end

    function page.on(_, name, fn) page.handlers[name] = fn end

    function page.send(_, name, view)
        if name ~= "freeroam:hud" then return end
        local m = H.model(view, last)
        local now = GetGameTimer()
        -- the ghost bar catches up with the health 0.6 s after the last hit
        if last and m.hp < last.hp then
            motion.shake = math.min(16, motion.shake + 4 + (last.hp - m.hp) * 0.4)
            ghostAt = now + 600
            ui:class("#vitals", "hurt", false)
            CreateThread(function() Wait(0); if alive then ui:class("#vitals", "hurt", true) end end)
        end
        if now >= ghostAt then m.hpGhost = m.hpPct end
        -- the car's acceleration (km/h per second) leans the speedometer: back when it pulls, forward when it brakes
        local kph = m.inVehicle and tonumber(m.speed) or nil
        if kph and motion.speed and now > motion.speedAt then
            local accel = (kph - motion.speed) / ((now - motion.speedAt) / 1000)
            motion.lean = clamp(accel * 0.08, -7, 7)
        elseif not kph then
            motion.lean = 0
        end
        motion.speed, motion.speedAt = kph, now
        m.hidden = motion.hidden
        local changed = {}
        for k, v in pairs(m) do
            if not shown or not same(shown[k], v) then changed[k] = v end
        end
        if next(changed) then
            for _, doc in ipairs(docs) do doc:merge("hud", changed) end
        end
        shown, last = m, m
    end

    -- the hit shake and the shot kick decay on their own clock; a shot is a new count on the
    -- weapons' shot counters (Open77.weapons.shotCounters, both hands), read every frame
    CreateThread(function()
        local at0 = GetGameTimer()
        local shots, generation = nil, nil
        local counters = type(Open77.weapons) == "table" and Open77.weapons.shotCounters or nil
        while alive do
            Wait(0)
            local at = GetGameTimer()
            local dt = math.min(0.1, (at - at0) / 1000)
            at0 = at
            motion.shake = motion.shake * math.exp(-dt * 7)
            motion.kick = motion.kick * math.exp(-dt * 14)
            if counters then
                local ok, c = pcall(counters)
                if ok and type(c) == "table" and tonumber(c.total) then
                    local total = tonumber(c.total)
                    if shots and generation == c.generation and total > shots then
                        -- rapid fire stacks up to a ceiling, like recoil
                        motion.kick = math.min(1.8, motion.kick + 0.75 * math.min(3, total - shots))
                    end
                    shots, generation = total, c.generation
                end
            end
        end
    end)
    startFloat(ui, FLOAT.wings, motion, function() return alive end)
    if speedo then startFloat(speedo, FLOAT.speedo, motion, function() return alive end) end

    -- another interface holds the cursor (pause menu, inventory, phone): step aside,
    -- NativeUI draws above WebUI pages
    CreateThread(function()
        while alive do
            Wait(150)
            local busy = false
            if type(Open77.input) == "table" and type(Open77.input.isCaptured) == "function" then
                local ok, _, cursor = pcall(Open77.input.isCaptured)
                busy = ok and cursor == true
            end
            if busy ~= motion.hidden then
                motion.hidden = busy
                for _, doc in ipairs(docs) do doc:set("hud", "hidden", busy) end
            end
        end
    end)

    function page.destroy()
        alive = false
        for _, doc in ipairs(docs) do pcall(doc.destroy, doc) end
    end
    return page
end
