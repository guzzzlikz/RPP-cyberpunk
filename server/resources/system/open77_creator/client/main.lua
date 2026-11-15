-- open77_creator client: a complete character creator on the runtime body API.
--
-- The catalogue is the game's own (Open77.body.catalog); the preview is the player, re-dressed live
-- (Open77.body.compose + Open77.body.switch); a camera rig travels between a shot per category; the
-- confirmed look goes to the server (open77_creator:save), which makes it the character's.

local C = CreatorConfig
local T = CreatorText
local ui, uiReady = nil, false

local S = nil -- the open session (nil when closed)
local Actions = {} -- the document's data events, by name (also driven by the debug command)
local catalogs, indexes = {}, {}
local pending = false -- the server has a creator waiting for this player
local worldReadyAt = nil
local closeToken = 0
local ROWS_MAX = 16  -- option rows of a category (see blankRow)
local CELLS_MAX = 0  -- the most choices of any option in either catalogue, set when a catalogue is indexed

-- Line icons of the categories (24 x 24 path data), by category id.
local ICONS = {
    body = "M9.6 5 a2.4 2.4 0 1 0 4.8 0 a2.4 2.4 0 1 0 -4.8 0 Z M7.5 10 H16.5 L15.6 15.5 H14.4 L13.8 21.5 H10.2 L9.6 15.5 H8.4 Z",
    face = "M7 9.5 C7 5.4 9.3 3 12 3 C14.7 3 17 5.4 17 9.5 V12 C17 16.4 14.6 20.5 12 20.5 C9.4 20.5 7 16.4 7 12 Z M9.6 10.6 H10.9 M13.1 10.6 H14.4 M10.6 15.6 H13.4",
    eyes = "M2.5 12 C5.4 7.6 8.6 6 12 6 C15.4 6 18.6 7.6 21.5 12 C18.6 16.4 15.4 18 12 18 C8.6 18 5.4 16.4 2.5 12 Z M9.2 12 a2.8 2.8 0 1 0 5.6 0 a2.8 2.8 0 1 0 -5.6 0 Z",
    hair = "M5 15 V11 C5 6.2 8 3 12 3 C16 3 19 6.2 19 11 V15 M8.2 20.5 V12.4 C8.2 9.8 9.8 8.4 12 8.4 C14.2 8.4 15.8 9.8 15.8 12.4 V20.5",
    makeup = "M4 20 L5.2 15.6 L15.8 5 L19 8.2 L8.4 18.8 Z M13.6 7.2 L16.8 10.4",
    marks = "M6.5 12 a5.5 5.5 0 1 0 11 0 a5.5 5.5 0 1 0 -11 0 Z M12 2.5 V5.5 M12 18.5 V21.5 M2.5 12 H5.5 M18.5 12 H21.5 M10.6 12 a1.4 1.4 0 1 0 2.8 0 a1.4 1.4 0 1 0 -2.8 0 Z",
}
local TAB_STEP = 45   -- dp between two tabs (ui/creator.rcss: .tab height + its hairline)
local SEG_STEP = 188  -- dp between the two body type buttons

-- ------------------------------------------------------------------------------- catalogue
local function loadCatalog(family)
    if catalogs[family] then return catalogs[family] end
    for _ = 1, 200 do
        local catalog, reason = Open77.body.catalog(family)
        if catalog then
            catalogs[family] = catalog
            return catalog
        end
        if reason ~= "catalog_loading" then return nil, reason end
        Wait(100)
    end
    return nil, "catalog_loading"
end

-- slot -> { option, ... } and part:name -> option, for one family.
local function indexOf(family)
    if indexes[family] then return indexes[family] end
    local catalog = catalogs[family]
    local index = { bySlot = {}, byKey = {} }
    for _, option in ipairs(catalog.options) do
        index.byKey[option.part .. ":" .. option.name] = option
        local follower = option.link ~= nil and not option.linkController
        if #option.choices > CELLS_MAX then CELLS_MAX = #option.choices end
        if not option.hidden and option.applied and not follower and #option.choices > 0 then
            local slot = option.uiSlot or option.name
            index.bySlot[slot] = index.bySlot[slot] or {}
            table.insert(index.bySlot[slot], option)
        end
    end
    indexes[family] = index
    return index
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function emptyChoices() return { head = {}, body = {}, arms = {} } end

local function choiceOf(option, choices)
    local part = choices[option.part]
    local index = part and part[option.name]
    if index == nil then index = option.default end
    for position, choice in ipairs(option.choices) do
        if choice.index == index then return choice, position end
    end
    return option.choices[1], 1
end

-- English names only: the game's labels follow the game's language.
local function choiceLabel(option, choice, position)
    if option.kind == "morph" then return T.shape .. " " .. position end
    if option.kind == "switcher" then
        local none = #(choice.options or {}) > 0
        for _, name in ipairs(choice.options or {}) do
            if not (name:match("_none$") or name:match("_00$")) then none = false end
        end
        return none and T.none or (T.style .. " " .. position)
    end
    return CreatorInternalName(choice.name) or (T.option .. " " .. position)
end

local function optionLabel(option)
    return T.slots[option.uiSlot or ""] or T.slots[option.name] or option.name
end

local function thumbOf(family, option, position)
    local seq = CreatorThumbs.options[family] and CreatorThumbs.options[family][option.name]
    local part = seq and CreatorThumbs.seq[seq][position]
    if part then return "/ui/thumbs/" .. part .. ".png" end
    return ""
end

-- ------------------------------------------------------------------------------- feedback
-- What reached the creator, counted per kind and logged the first time (creatordebug inputs):
-- the proof that a wheel, a drag or a sound works on a given client without watching it.
local seen = {}
local function note(kind, detail)
    seen[kind] = (seen[kind] or 0) + 1
    if seen[kind] == 1 then print(("[open77_creator] first %s%s"):format(kind, detail and (" " .. tostring(detail)) or "")) end
end

local lastSound = 0
local function sound(kind)
    local name = C.sounds and C.sounds[kind]
    if not name or not (Open77.sfx and Open77.sfx.play2d) then return end
    local now = GetGameTimer()
    if kind == "hover" and now - lastSound < 70 then return end
    lastSound = now
    local called, ok, why = pcall(Open77.sfx.play2d, name)
    note("sound:" .. kind, (called and ok) and "played " .. name or ("refused " .. tostring(called and why or ok)))
end

-- ------------------------------------------------------------------------------- presentation
-- The lists of the document keep a fixed length, the unused entries hidden (`show`): RmlUi reads
-- the removed entries of a data-for that shrinks, which logged a warning per field and per entry
-- (~1200 per session) at every category or option change.

local function blankRow()
    return { show = false, key = "", label = "", value = "", position = 0, count = 0, fill = 0, selected = false }
end

local function blankCell()
    return { show = false, on = false, src = "", swatch = false, plain = false, color = "#00000000", n = "" }
end

local function fillOf(position, count)
    return count > 1 and math.floor((position - 1) / (count - 1) * 100 + 0.5) or 100
end

local function rowsOf(category)
    local family, choices = S.family, S.choices[S.family]
    local index = indexOf(family)
    local active = Open77.body.active(family, choices) or {}
    local rows, options = {}, {}
    for _, slot in ipairs(category.slots) do
        for _, option in ipairs(index.bySlot[slot] or {}) do
            if active[option.part] and active[option.part][option.name] then
                table.insert(options, option)
            end
        end
    end
    local cells = {}
    for i, option in ipairs(options) do
        if i > ROWS_MAX then break end
        local choice, position = choiceOf(option, choices)
        local selected = S.selected[category.id] == option.part .. ":" .. option.name
            or (S.selected[category.id] == nil and i == 1)
        local count = #option.choices
        if selected then
            for p, c in ipairs(option.choices) do
                local src = thumbOf(family, option, p)
                local swatch = src == "" and type(c.color) == "table" and (c.color.a or 0) > 0
                cells[p] = {
                    show = true, on = p == position, src = src, swatch = swatch, plain = src == "" and not swatch,
                    color = swatch and string.format("#%02x%02x%02x", c.color.r, c.color.g, c.color.b) or "#00000000",
                    n = string.format("%02d", p),
                }
            end
        end
        rows[i] = {
            show = true,
            key = option.part .. ":" .. option.name,
            label = optionLabel(option),
            value = choiceLabel(option, choice, position),
            position = position, count = count, fill = fillOf(position, count),
            selected = selected,
        }
    end
    local used, shown = #rows, #cells
    for i = used + 1, ROWS_MAX do rows[i] = blankRow() end
    for p = shown + 1, math.max(CELLS_MAX, shown) do cells[p] = blankCell() end
    S.options = options
    return rows, used, cells, shown
end

local function categoryById(id)
    for i, category in ipairs(C.categories) do
        if category.id == id then return category, i end
    end
    return C.categories[1], 1
end

local function lookImage(name)
    local file = C.looks and C.looks[tostring(name):lower()]
    return file and ("/ui/looks/" .. file .. ".png") or ""
end

-- Writes the model, then the option gauges: a gauge that moved is tweened, the others are set.
local function refresh()
    if not S or not ui then return end
    local category, position = categoryById(S.category)
    local categories = {}
    for i, c in ipairs(C.categories) do
        categories[i] = { id = c.id, label = T.categories[c.id] or c.id,
            icon = ('<path view-box="0 0 24 24" d="%s"/>'):format(ICONS[c.id] or ICONS.marks) }
    end
    local presets = {}
    for _, preset in ipairs(catalogs[S.family].presets or {}) do
        local label = T.presetNames[preset.name] or preset.name
        table.insert(presets, { name = preset.name, label = label, initial = label:sub(1, 1):upper(),
            img = lookImage(preset.name) })
    end
    local rows, used, cells, shown = rowsOf(category)
    local later = S.reason == "new_character" or S.reason == "unfinished"
    ui:merge("cc", {
        rows = rows, hasRows = used > 0, cells = cells, hasCells = shown > 0, veilText = T.rebuilding,
        open = true, t = T, family = S.family, category = S.category,
        categoryLabel = T.categories[S.category] or S.category,
        categoryIndex = string.format("%02d", position), categoryCount = string.format("%02d", #C.categories),
        categories = categories, presets = presets, hasPresets = #presets > 0, preset = S.preset or "",
        busy = S.busy or (S.status or "") ~= "", saving = S.saving == true, status = S.status or "",
        cancelLabel = later and T.later or T.cancel,
        confirmLabel = S.saving and T.saving or T.save,
    })
    S.fills = S.fills or {}
    local fills = {}
    for i, row in ipairs(rows) do
        if not row.show then break end
        local before = S.fills[row.key]
        local to = { width = row.fill .. "%" }
        if before and before ~= row.fill then
            ui:animate("#row" .. (i - 1) .. " .fill", { from = { width = before .. "%" }, to = to, duration = 0.32, easing = "emphasized" })
        else
            ui:animate("#row" .. (i - 1) .. " .fill", { to = to, instant = true })
        end
        fills[row.key] = row.fill
    end
    S.fills = fills
end

-- The options of a category arrive one after the other; its title slides in and the rule draws.
local function rowsIn(delay)
    if not ui then return end
    ui:animate(".row", { from = { x = 28, opacity = 0 }, to = { x = 0, opacity = 1 }, preset = "calm", stagger = 0.035, delay = delay or 0 })
    ui:animate("#cat-title", { from = { x = -16, opacity = 0 }, to = { x = 0, opacity = 1 }, preset = "snappy", delay = delay or 0 })
    ui:animate(".cat-count", { from = { y = 9, opacity = 0 }, to = { y = 0, opacity = 1 }, preset = "snappy", delay = (delay or 0) + 0.05 })
    ui:animate("#cat-rule-fill", { from = { width = "0%" }, to = { width = "100%" }, duration = 0.7, easing = "emphasized", delay = delay or 0 })
end

local function moveThumbs(instant)
    if not S or not ui then return end
    local _, position = categoryById(S.category)
    -- Lengths with a unit, not the x / y channels: those are physical pixels, and the tabs are
    -- laid out in dp (measured at 1440p: the highlight stopped at three quarters of the way).
    local tab = { top = ((position - 1) * TAB_STEP) .. "dp" }
    local seg = { left = (S.family == "female" and SEG_STEP or 0) .. "dp" }
    if instant then
        ui:animate("#tab-thumb", { to = tab, instant = true })
        ui:animate("#seg-thumb", { to = seg, instant = true })
    else
        ui:animate("#tab-thumb", { to = tab, spring = { duration = 0.42, bounce = 0.24 } })
        ui:animate("#seg-thumb", { to = seg, spring = { duration = 0.45, bounce = 0.28 } })
    end
end

-- ------------------------------------------------------------------------------- camera rig
local function playerPosition()
    local a, b, c = Open77.character.position()
    if type(a) == "table" then return vector3(a) end
    if type(a) == "number" then return vector3(a, b, c) end
    return nil
end

local function frame()
    -- The player is frozen while the creator is open: its frame is read once.
    local o = Open77.character.offsetToWorld(vector3(0, 0, 0))
    local f = Open77.character.offsetToWorld(vector3(0, 1, 0))
    local r = Open77.character.offsetToWorld(vector3(1, 0, 0))
    if not (o and f and r) then return nil end
    return { o = vector3(o), f = vector3(f) - vector3(o), r = vector3(r) - vector3(o) }
end

local function shotOf(categoryId)
    local shot = C.shots[categoryById(categoryId).shot] or C.shots.body
    return { distance = shot.distance, height = shot.height, look = shot.look, side = shot.side, fov = shot.fov, angle = 0 }
end

local function smooth(t) return t * t * t * (t * (t * 6 - 15) + 10) end
local function approach(value, target, rate, dt) return value + (target - value) * (1 - math.exp(-rate * dt)) end

-- Starts a travelling toward the shot of a category: eased along the way, with a swing around
-- the character and a pull back in the middle that grow with how far the next shot is.
local function travelTo(categoryId, seconds)
    local r = S.rig
    local to = shotOf(categoryId)
    local covered = math.abs(to.distance - r.cur.distance)
    local amount = math.min(1, covered / 1.4 + math.abs(to.height - r.cur.height) / 0.55)
    local span = C.camera.travelSeconds
    r.from, r.to, r.t = copy(r.cur), to, 0
    r.dur = seconds or (span.min + (span.max - span.min) * amount)
    r.side = -(r.side or -1) -- one side, then the other
    r.swing = C.camera.swingDegrees * math.max(0.18, amount) * r.side
    r.lift = C.camera.liftRatio * covered
    S.zoomTarget, S.panTarget = 1, 0
end

-- One step of the rig: the travelling, the zoom, the turn (keys ease in and out, a drag carries
-- on), the pan, and a slow sway while nothing is touched.
local function stepRig(dt, now)
    local r = S.rig
    r.swingNow, r.liftNow = 0, 0
    if r.t < 1 then
        r.t = math.min(1, r.t + dt / r.dur)
        local e = smooth(r.t)
        for key, to in pairs(r.to) do r.cur[key] = r.from[key] + (to - r.from[key]) * e end
        local arc = math.sin(math.pi * e)
        r.swingNow, r.liftNow = r.swing * arc, r.lift * arc
    end
    S.zoom = approach(S.zoom, S.zoomTarget, 9, dt)
    S.pan = approach(S.pan, S.panTarget, 10, dt)
    if not S.dragging then
        S.turnVelocity = approach(S.turnVelocity, S.turn * C.turnSpeed, S.turn ~= 0 and 8 or 4.5, dt)
        if math.abs(S.turnVelocity) < 0.05 and S.turn == 0 then S.turnVelocity = 0 end
        S.angle = (S.angle + S.turnVelocity * dt) % 360
    end
    local idle = r.t >= 1 and S.turn == 0 and not S.dragging and now - (S.touched or 0) > 1500
    r.drift = approach(r.drift or 0, idle and 1 or 0, 1.2, dt)
    local seconds = now / 1000
    r.driftAngle = C.camera.driftDegrees * r.drift * math.sin(seconds * 0.31)
    r.driftHeight = C.camera.driftHeight * r.drift * math.sin(seconds * 0.43 + 1.3)
end

-- The pose of the shot right now, in the player's frame: the camera on a circle in front of the
-- player, shifted to the camera's right so the character stands between the two panels.
local function poseNow()
    local r, fr = S.rig, S.frame
    local a = math.rad(S.angle + r.cur.angle + (r.swingNow or 0) + (r.driftAngle or 0))
    local d = (r.cur.distance + (r.liftNow or 0)) * S.zoom
    local side = r.cur.side
    local rx, ry = -math.cos(a), math.sin(a)
    local function world(x, y, z) return fr.o + fr.r * x + fr.f * y + vector3(0, 0, z) end
    local position = world(math.sin(a) * d + rx * side, math.cos(a) * d + ry * side, r.cur.height + S.pan + (r.driftHeight or 0))
    local look = world(rx * side, ry * side, r.cur.look + S.pan)
    return position, look, r.cur.fov
end

-- True once the shot is up. A camera lives on the player's body: when a body type change spawns a
-- new body the old camera is gone, and the game refuses a camera while the new body takes over
-- (camera_unavailable). The frame loop then retries until it is accepted (S.reframe).
local function placeCamera(blendMs)
    if not S then return false end
    S.frame = S.frame or frame()
    if not S.frame then return false end
    local position, look, fov = poseNow()
    if not S.camera then
        S.camera = Open77.camera.create({ position = position, lookAt = look, fov = fov, thirdPersonBody = true })
        if not S.camera then return false end
    else
        Open77.camera.setTransform(S.camera, { position = position, fov = fov })
        Open77.camera.lookAt(S.camera, look)
    end
    local view = Open77.camera.cameras()
    if not view or view.activeCamera ~= S.camera then
        local ok, why = Open77.camera.activate(S.camera, { blendMs = blendMs or 500 })
        if not ok then
            print("[open77_creator] camera refused: " .. tostring(why))
            if tostring(why) == "camera_not_found" then S.camera = nil end -- created again next try
            return false
        end
    end
    return true
end

-- Every frame: the rig moves the camera it holds (a dolly is a transform per frame).
local function pushPose()
    if not S.camera or S.reframe or not S.frame then return false end
    local position, look, fov = poseNow()
    local r = S.rig
    local stamp = ("%.4f %.4f %.4f %.3f %.4f %.4f"):format(position.x, position.y, position.z, fov, r.cur.look + S.pan, r.cur.side)
    if stamp == r.stamp then return false end
    r.stamp = stamp
    Open77.camera.setTransform(S.camera, { position = position, fov = fov })
    Open77.camera.lookAt(S.camera, look)
    return true
end

-- A new body: drop the old camera, and put the shot back up as soon as the game lets us.
local function reframe()
    if not S then return end
    if S.camera then pcall(Open77.camera.destroy, S.camera) end
    S.camera = nil -- the frame stays: the shot is where the creator opened, whatever the new body faces
    S.rig.stamp = nil
    S.reframe = GetGameTimer()
end

-- A new body is being spawned: the scene behind the panels is veiled until it is dressed and framed.
local function veil(on)
    if not S or not ui then return end
    if on then S.veiled = GetGameTimer() elseif not S.veiled then return else S.veiled = nil end
    ui:set("cc", "veiled", on == true)
end

-- ------------------------------------------------------------------------------- preview
local function schedulePreview()
    S.dirty = GetGameTimer() + C.previewDelayMs
    S.busy, S.status = true, T.applying
end

local function apply()
    local family = S.family
    local body, reason = Open77.body.compose(family, S.choices[family])
    if not body then
        S.busy, S.status = false, tostring(reason)
        return refresh()
    end
    S.body = body
    local ok, why = Open77.body.switch(family, body)
    if not ok then
        S.busy, S.status = false, tostring(why)
        return refresh()
    end
    S.waiting = GetGameTimer() + 8000
end

local function setChoice(option, index)
    local choices = S.choices[S.family]
    choices[option.part] = choices[option.part] or {}
    choices[option.part][option.name] = index
    S.preset = nil
    schedulePreview()
    refresh()
end

-- ------------------------------------------------------------------------------- open / close
-- The panels hang in space: turned toward the player, leaning, and drifting slowly. Each element
-- gets its own period so that nothing moves in step.
local FLOATS = {
    { sel = "#left", turn = 1, period = 7.3 },
    { sel = "#right", turn = -1, period = 8.1 },
    { sel = "#hints", lean = 1, period = 6.4 },
    { sel = "#actions", lean = 1, period = 6.9 },
    { sel = "#top", lean = -0.7, period = 9.2 },
}

local function restOf(float)
    local D = C.depth
    return { perspective = D.perspective, rotateY = (float.turn or 0) * D.tilt, rotateX = (float.lean or 0) * D.lean }
end

local function startFloats()
    local D = C.depth
    for i, float in ipairs(FLOATS) do
        local rest = restOf(float)
        local phase = (i % 2 == 0) and 1 or -1
        if D.float > 0 then
            ui:keyframes(float.sel, { channel = "z", duration = float.period, iterations = -1, delay = 0.1 * i, stops = {
                { offset = 0, value = 0 }, { offset = 0.25, value = D.float * 3 * phase, easing = "ease-in-out" },
                { offset = 0.75, value = -D.float * 3 * phase, easing = "ease-in-out" }, { offset = 1, value = 0, easing = "ease-in-out" } } })
        end
        if D.sway > 0 then
            local channel = float.turn and "rotateY" or "rotateX"
            local at = rest[channel]
            ui:keyframes(float.sel, { channel = channel, duration = float.period * 1.3, iterations = -1, delay = 1.4 + 0.1 * i, stops = {
                { offset = 0, value = at }, { offset = 0.25, value = at + D.sway * phase, easing = "ease-in-out" },
                { offset = 0.75, value = at - D.sway * phase, easing = "ease-in-out" }, { offset = 1, value = at, easing = "ease-in-out" } } })
        end
    end
end

local function stopFloats()
    for _, float in ipairs(FLOATS) do ui:stop(float.sel) end
end

-- An entrance: the element comes from `offset`, turned further than where it rests.
local function enter(float, offset, transition, delay)
    local rest = restOf(float)
    local from = { perspective = rest.perspective, rotateY = rest.rotateY * 2.6, rotateX = rest.rotateX * 2.4, opacity = 0, z = -60 }
    local to = { perspective = rest.perspective, rotateY = rest.rotateY, rotateX = rest.rotateX, opacity = 1, z = 0 }
    for key, value in pairs(offset) do from[key], to[key] = value, 0 end
    ui:animate(float.sel, { from = from, to = to, spring = transition, delay = delay })
end

local function animateIn()
    ui:class("#root", "in", true)
    enter(FLOATS[5], { y = -22 }, { duration = 0.5, bounce = 0 }, 0)
    enter(FLOATS[1], { x = -90 }, { duration = 0.7, bounce = 0.16 }, 0.1)
    enter(FLOATS[2], { x = 90 }, { duration = 0.7, bounce = 0.16 }, 0.2)
    enter(FLOATS[3], { y = 46 }, { duration = 0.6, bounce = 0.1 }, 0.32)
    enter(FLOATS[4], { y = 46 }, { duration = 0.6, bounce = 0.2 }, 0.4)
    startFloats()
    ui:animate(".tab", { from = { x = -22, opacity = 0 }, to = { x = 0, opacity = 1 }, preset = "calm", stagger = 0.05, delay = 0.36 })
    ui:animate("#tab-thumb", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.4, easing = "ease-out", delay = 0.7 })
    ui:animate("#looks", { from = { y = 18, opacity = 0 }, to = { y = 0, opacity = 1 }, preset = "calm", delay = 0.62 })
    ui:animate("#random", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.4, easing = "ease-out", delay = 0.74 })
    rowsIn(0.42)
end

local function close(keep)
    if not S then return end
    local session = S
    S = nil
    closeToken = closeToken + 1
    local token = closeToken
    if ui then
        -- The document is already gone when the resource stops.
        pcall(function()
            ui:blur()
            ui:class("#root", "in", false)
            stopFloats()
            ui:animate("#top", { to = { y = -22, opacity = 0 }, preset = "snappy" })
            ui:animate("#left", { to = { x = -70, z = -80, rotateY = C.depth.tilt * 2.4, opacity = 0 }, preset = "snappy" })
            ui:animate("#right", { to = { x = 70, z = -80, rotateY = -C.depth.tilt * 2.4, opacity = 0 }, preset = "snappy" })
            ui:animate("#hints", { to = { y = 40, opacity = 0 }, preset = "snappy" })
            ui:animate("#actions", { to = { y = 40, opacity = 0 }, preset = "snappy" })
        end)
        SetTimeout(300, function()
            if S or token ~= closeToken or not ui then return end
            pcall(function()
                ui:set("cc", "open", false)
                ui:projection(false)
                ui:hide()
            end)
        end)
    end
    pcall(Open77.camera.deactivate, { blendMs = 550 })
    if session.camera then pcall(Open77.camera.destroy, session.camera) end
    pcall(Open77.character.setFrozen, false)
    if not keep and session.original and session.changed then
        Open77.body.switch(session.original.family, session.original)
    end
    -- open77_appearance takes the body back: the server's answer to a saved look, or the original.
    TriggerEvent("open77:appearance:hold", false)
    TriggerEvent("open77_creator:visibility", false)
    if Open77.hud and Open77.hud.setCinematic then pcall(Open77.hud.setCinematic, false) end
end

local function touch() if S then S.touched = GetGameTimer() end end

local function ensureUi()
    if ui then return true end
    CreatorEffects.register()
    local handle, why = Open77.ui.create({
        document = "ui/creator.rml",
        layer = "menu",
        visible = false,
        models = { cc = {
            open = false, t = T, family = "male", category = "body", categoryLabel = "", categoryIndex = "01", categoryCount = "06",
            veilText = "", veiled = false, categories = {}, presets = {}, preset = "", rows = {}, cells = {}, hasCells = false, busy = false, saving = false,
            status = "", cancelLabel = "", confirmLabel = T.save, hasRows = false, hasPresets = false,
        } },
        events = { cc = { "family", "tab", "preset", "random", "select", "step", "pick", "save", "cancel", "hover" } },
    })
    if not handle then return false, why end
    ui = handle

    Actions["family"] = (function(family)
        if not S or (family ~= "male" and family ~= "female") or family == S.family then return end
        local catalog = loadCatalog(family)
        if not catalog then return end
        sound("press")
        S.family = family
        S.choices[family] = S.choices[family] or emptyChoices()
        veil(true)
        S.selected, S.preset, S.fills = {}, nil, {}
        S.changed = true
        schedulePreview(); refresh()
        moveThumbs()
        rowsIn(0.1)
    end)
    Actions["tab"] = (function(id)
        if not S or tostring(id) == S.category then return end
        sound("press")
        S.category = tostring(id)
        S.fills = {}
        refresh()
        moveThumbs()
        rowsIn()
        travelTo(S.category)
        touch()
    end)
    Actions["preset"] = (function(name)
        if not S then return end
        for _, preset in ipairs(catalogs[S.family].presets or {}) do
            if preset.name == name then
                sound("press")
                local choices = copy(preset.choices)
                choices.head, choices.body, choices.arms = choices.head or {}, choices.body or {}, choices.arms or {}
                S.choices[S.family] = choices
                S.changed = true
                S.preset = name
                schedulePreview(); refresh()
                rowsIn()
            end
        end
    end)
    Actions["random"] = (function()
        if not S then return end
        sound("press")
        local choices = emptyChoices()
        local index = indexOf(S.family)
        for _, category in ipairs(C.categories) do
            for _, slot in ipairs(category.slots) do
                for _, option in ipairs(index.bySlot[slot] or {}) do
                    if option.part ~= "body" or slot ~= "genitals_switcher" then
                        choices[option.part][option.name] = option.choices[math.random(#option.choices)].index
                    end
                end
            end
        end
        S.choices[S.family] = choices
        S.changed = true
        S.preset = nil
        schedulePreview(); refresh()
        rowsIn()
    end)
    Actions["select"] = (function(i)
        if not S or not S.options then return end
        local option = S.options[(tonumber(i) or 0) + 1]
        if not option then return end
        local key = option.part .. ":" .. option.name
        if S.selected[S.category] == key then return end
        sound("press")
        S.selected[S.category] = key
        refresh()
        ui:animate("#row" .. (tonumber(i) or 0) .. " .grid", { from = { y = -10, opacity = 0 }, to = { y = 0, opacity = 1 }, preset = "calm" })
    end)
    -- The value of a row changed: its text flicks in from the side it moved to.
    local function flick(i, direction)
        ui:animate("#row" .. i .. " .row-value", { from = { y = 8 * direction, opacity = 0 }, to = { y = 0, opacity = 1 }, preset = "snappy" })
        ui:animate("#row" .. i .. " .row-count", { from = { opacity = 0.2 }, to = { opacity = 1 }, duration = 0.3, easing = "ease-out" })
    end
    Actions["step"] = (function(i, delta)
        if not S or not S.options then return end
        i = tonumber(i) or 0
        local option = S.options[i + 1]
        if not option then return end
        sound("press")
        local opened = S.selected[S.category] ~= option.part .. ":" .. option.name
        S.selected[S.category] = option.part .. ":" .. option.name
        local _, position = choiceOf(option, S.choices[S.family])
        local count = #option.choices
        delta = tonumber(delta) or 0
        position = ((position - 1 + delta) % count) + 1
        S.changed = true
        setChoice(option, option.choices[position].index)
        flick(i, delta < 0 and -1 or 1)
        if opened then
            ui:animate("#row" .. i .. " .grid", { from = { y = -10, opacity = 0 }, to = { y = 0, opacity = 1 }, preset = "calm" })
        end
    end)
    Actions["pick"] = (function(i, j)
        if not S or not S.options then return end
        i = tonumber(i) or 0
        local option = S.options[i + 1]
        local choice = option and option.choices[(tonumber(j) or 0) + 1]
        if not choice then return end
        sound("press")
        local _, before = choiceOf(option, S.choices[S.family])
        S.changed = true
        setChoice(option, choice.index)
        flick(i, ((tonumber(j) or 0) + 1) < before and -1 or 1)
    end)
    Actions["hover"] = (function() sound("hover") end)
    Actions["turn"] = (function(direction) if S then S.turn = tonumber(direction) or 0; touch() end end)
    Actions["cancel"] = (function() sound("press"); close(false) end)
    Actions["save"] = (function()
        if not S or S.saving then return end
        local family = S.family
        local body, reason = Open77.body.compose(family, S.choices[family])
        if not body then S.status = tostring(reason); return refresh() end
        sound("press")
        -- One JSON string: a network event carries at most 1024 values, and a detailed look (beard,
        -- tattoos, piercings, makeup...) as tables went over it -- the event was refused on the
        -- client, nothing reached the server, and the button stayed on "Saving" (2026-11-12,
        -- de-unstable). A string counts once (64 KiB at most).
        local encoded, why = Open77.json.encode({ body = body, choices = S.choices[family] })
        if not encoded then S.status = tostring(why or "encode_failed"); return refresh() end
        local sent, refused = TriggerServerEvent("open77_creator:save", family, encoded)
        if sent == false then
            print("[open77_creator] save not sent: " .. tostring(refused))
            S.status = tostring(refused or "not_sent")
            return refresh()
        end
        S.saving, S.busy, S.status = true, true, T.saving
        S.saveDeadline = GetGameTimer() + 15000
        refresh()
    end)

    for name, fn in pairs(Actions) do
        if name ~= "turn" then ui:onModel(name, fn) end
    end

    ui:on("keydown", function(e)
        if not S then return end
        local key = tostring(e.key or "")
        note("key", key)
        if key == "escape" then Actions.cancel()
        elseif key == "enter" then Actions.save()
        elseif key == "q" or key == "a" or key == "left" then S.turn = -1; touch()
        elseif key == "e" or key == "d" or key == "right" then S.turn = 1; touch() end
    end)
    ui:on("keyup", function(e)
        if not S then return end
        local key = tostring(e.key or "")
        if key == "q" or key == "a" or key == "left" or key == "e" or key == "d" or key == "right" then S.turn = 0; touch() end
    end)
    -- Over the character only: the wheel zooms, a drag turns (sideways) and pans (up and down).
    ui:on("mousescroll", "#stage", function(e)
        if not S then return end
        local delta = tonumber(e.wheel_delta_y or e.wheel_delta or 0) or 0
        if delta == 0 then return end
        -- wheel up (negative delta) comes closer
        S.zoomTarget = math.max(0.5, math.min(1.7, S.zoomTarget * (1 + C.zoomStep * (delta > 0 and 1 or -1))))
        note("wheel", ("delta=%s zoom=%.2f"):format(tostring(delta), S.zoomTarget))
        touch()
    end)
    -- A press on the character starts a drag; it follows the mouse wherever it goes and ends when
    -- the button is released (plain mouse events: RmlUi only sends drag events to elements that
    -- ask for them, and stops them at the element's edge).
    ui:on("mousedown", "#stage", function(e)
        if not S or (tonumber(e.button) or 0) ~= 0 then return end
        S.dragging = { x = tonumber(e.mouse_x) or 0, y = tonumber(e.mouse_y) or 0, at = GetGameTimer(), velocity = 0 }
        note("press", ("at %s,%s"):format(tostring(e.mouse_x), tostring(e.mouse_y)))
        S.turnVelocity = 0
        touch()
    end)
    local function drag(e)
        if not S or not S.dragging then return end
        local x, y = tonumber(e.mouse_x), tonumber(e.mouse_y)
        if not x or not y then return end
        local now = GetGameTimer()
        local dx, dy = x - S.dragging.x, y - S.dragging.y
        if dx == 0 and dy == 0 then return end
        local turned = -dx * C.camera.dragDegrees
        S.angle = (S.angle + turned) % 360
        note("drag", ("dx=%s dy=%s angle=%.1f"):format(tostring(dx), tostring(dy), S.angle))
        local limit = C.camera.panLimit
        S.panTarget = math.max(-limit, math.min(limit, S.panTarget + dy * C.camera.panMetres))
        local elapsed = math.max(4, now - S.dragging.at) / 1000
        S.dragging.velocity = S.dragging.velocity + (turned / elapsed - S.dragging.velocity) * 0.5
        S.dragging.x, S.dragging.y, S.dragging.at = x, y, now
        touch()
    end
    ui:on("mouseup", function()
        if not S or not S.dragging then return end
        -- the turn carries on and eases out (nothing if the mouse had stopped before the release)
        note("release")
        local still = GetGameTimer() - S.dragging.at > 120
        S.turnVelocity = still and 0 or math.max(-260, math.min(260, S.dragging.velocity or 0))
        S.dragging = nil
        touch()
    end)
    -- The interface leans after the mouse (see the frame loop).
    ui:on("mousemove", function(e)
        if not S then return end
        note("move")
        drag(e)
        local state = S.screen
        if not state then return end
        local x, y = tonumber(e.mouse_x), tonumber(e.mouse_y)
        if not x or not y then return end
        S.mouse = { x = math.max(-1, math.min(1, x / state.w * 2 - 1)), y = math.max(-1, math.min(1, y / state.h * 2 - 1)) }
    end)
    ui:onEvent("loaded", function() uiReady = true end)
    return true
end

-- The whole interface leans a little: after the mouse, and against the camera while it turns
-- (the panels trail the move, then settle). One matrix per change, no layout.
local function stepParallax(dt, now)
    local D = C.depth
    if D.parallax <= 0 and D.inertia <= 0 then return end
    if not S.screen or now >= (S.screenAt or 0) then
        S.screenAt = now + 1000
        local state = ui:state()
        if type(state) == "table" and (tonumber(state.width) or 0) > 0 then S.screen = { w = state.width, h = state.height } end
    end
    local mouse = S.mouse or { x = 0, y = 0 }
    local turning = S.dragging and (S.dragging.velocity or 0) or S.turnVelocity
    local travel = (S.rig.swingNow or 0) * 0.08
    local wantY = mouse.x * D.parallax + math.max(-2.2, math.min(2.2, -turning * D.inertia)) + travel
    local wantX = -mouse.y * D.parallax * 0.6
    S.leanY = approach(S.leanY or 0, wantY, 5, dt)
    S.leanX = approach(S.leanX or 0, wantX, 5, dt)
    local ry, rx = math.floor(S.leanY * 100 + 0.5) / 100, math.floor(S.leanX * 100 + 0.5) / 100
    if ry ~= S.sentY or rx ~= S.sentX then
        S.sentY, S.sentX = ry, rx
        ui:projection({ rotateY = ry, rotateX = rx, perspective = 2400 })
    end
end

local function open(reason, stored)
    if S then return end
    local state = Open77.body.state()
    if not state then return end
    for _ = 1, 100 do
        state = Open77.body.state()
        if state and not state.busy then break end
        Wait(100)
    end
    local family = state.family
    -- Each step in its own frame: a resume has a time budget, and a catalogue is ~900 options.
    local catalog, why = loadCatalog(family)
    if not catalog then return print("[open77_creator] " .. string.format(T.failed, tostring(why))) end
    Wait(0)
    indexOf(family)
    Wait(0)
    local other = family == "male" and "female" or "male" -- a body type change never waits in a UI callback
    loadCatalog(other)
    Wait(0)
    if catalogs[other] then indexOf(other) end
    Wait(0)
    local ok, err = ensureUi()
    if not ok then return print("[open77_creator] " .. string.format(T.failed, tostring(err))) end

    local current = Open77.body.capture()
    local choices = stored and stored[family]
    if type(choices) ~= "table" then choices = current and Open77.body.decompose(current) or nil end
    Wait(0)
    choices = choices or emptyChoices()
    choices.head, choices.body, choices.arms = choices.head or {}, choices.body or {}, choices.arms or {}

    local first = C.categories[1].id
    S = {
        reason = reason, family = family, original = current,
        choices = { [family] = choices }, category = first, selected = {}, fills = {},
        angle = 0, zoom = 1, zoomTarget = 1, pan = 0, panTarget = 0, turn = 0, turnVelocity = 0,
        busy = false, status = "", openedAt = GetGameTimer(), touched = GetGameTimer(),
    }
    -- The opening move: from further back and to one side, travelling in to the first shot.
    local intro, target = C.camera.intro, shotOf(first)
    local start = copy(target)
    start.distance, start.height, start.angle = target.distance * intro.distance, target.height + intro.height, intro.angle
    S.rig = { cur = start, from = copy(start), to = target, t = 0, dur = intro.seconds, swing = 0, lift = 0, side = -1 }
    if stored then
        for f, c in pairs(stored) do
            if f ~= family and type(c) == "table" then S.choices[f] = copy(c) end
        end
    end
    print(("[open77_creator] open reason=%s family=%s stored=%s"):format(tostring(reason), family, stored and "yes" or "no"))
    -- The shot is framed once, where the creator opens: a new body (a body type change) does not move it.
    S.frame = frame()
    Open77.character.setFrozen(true)
    TriggerEvent("open77:appearance:hold", true)
    -- Other interfaces drawn over the world (a gamemode HUD) step aside while the creator is open:
    --   AddEventHandler("open77_creator:visibility", function(open) ... end)
    TriggerEvent("open77_creator:visibility", true)
    -- A clean view: no vanilla HUD and no game notifications while the creator is open (a body type
    -- change makes the save's quests announce their items again on the new body).
    if Open77.hud and Open77.hud.setCinematic then pcall(Open77.hud.setCinematic, true, 0.01) end
    -- Put the player in a runtime body straight away: later edits only re-dress it, and the camera
    -- is not cut by the first switch.
    if not state.switched then
        S.changed = false
        veil(true)
        apply()
    end
    refresh()
    ui:show()
    ui:layout("#rows", { preset = "growth" })
    moveThumbs(true)
    animateIn()
    ui:focus({ keyboard = true, cursor = true })
    if not placeCamera(800) then S.reframe = GetGameTimer() + 250 end
end

-- ------------------------------------------------------------------------------- frame loop
CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(0)
        local now = GetGameTimer()
        local dt = math.min(0.1, (now - last) / 1000)
        last = now
        if S then
            if S.dirty and now >= S.dirty then
                S.dirty = nil
                apply()
            end
            if S and S.saving and S.saveDeadline and now > S.saveDeadline then
                -- No answer: give the button back rather than leave it on "Saving".
                print("[open77_creator] the server did not answer the save")
                S.saving, S.busy, S.status, S.saveDeadline = false, false, T.noAnswer, nil
                refresh()
            end
            if S and S.waiting and now > S.waiting then
                S.waiting, S.busy, S.status = nil, false, ""
                refresh()
            end
        end
        if S then
            -- Lift the veil once the new body is dressed and the shot is back (and not before 600 ms,
            -- so that it never flashes).
            if S.veiled and not S.busy and not S.reframe and not S.dirty and now - S.veiled > 600 then veil(false) end
            if S.reframe and now >= S.reframe then
                if placeCamera(300) then S.reframe = nil else S.reframe = now + 250 end
            end
            -- The game can take the shot away while the creator is open (a perspective fallback
            -- during a re-dress was measured once in ~30 edits): take it back rather than leave the
            -- player looking at the world through the creator's panels.
            if not S.reframe and S.camera and now >= (S.cameraCheck or 0) then
                S.cameraCheck = now + 500
                local view = Open77.camera.cameras()
                if view and view.activeCamera ~= S.camera then
                    print("[open77_creator] shot lost, taking it back")
                    S.reframe = now
                end
            end
            stepRig(dt, now)
            pushPose()
            stepParallax(dt, now)
        end
    end
end)

AddEventHandler("open77:body:changed", function(event)
    if not S then return end
    event = tostring(event or "")
    if event == "switched" or event == "redressed" or event == "unchanged" or event:sub(1, 7) == "failed:" then
        S.waiting = nil
        if not S.saving then S.busy = false end
        S.status = event:sub(1, 7) == "failed:" and event:sub(8) or (S.saving and T.saving or "")
        -- A new body (another family, or the first switch) takes the camera with the old one.
        if event == "switched" then reframe() end
        refresh()
    end
end)

RegisterNetEvent("open77_creator:open", function(reason, stored)
    CreateThread(function() open(tostring(reason or "requested"), type(stored) == "table" and stored or nil) end)
end)

RegisterNetEvent("open77_creator:pending", function() pending = true end)

-- Laboratory (server convar open77_creator_debug "true"): drives the same handlers as the document,
-- e.g. `creatordebug tab face`, `creatordebug pick 0 5`, `creatordebug family female`, plus:
--   dropshot   the game taking the shot away (as a perspective fallback would)
--   ui off|on  hides the document (a clean view of the character)
--   zoom n, angle n, pan n   the rig's targets
local DebugActions = {
    dropshot = function() pcall(Open77.camera.deactivate, { blendMs = 0 }) end,
    ui = function(state) if ui then if state == "off" then ui:hide() else ui:show() end end end,
    zoom = function(value) if S then S.zoomTarget = tonumber(value) or 1 end end,
    angle = function(value) if S then S.angle = tonumber(value) or 0 end end,
    pan = function(value) if S then S.panTarget = tonumber(value) or 0 end end,
    still = function() if S then S.touched = GetGameTimer() + 600000 end end,
    inputs = function()
        local parts = {}
        for kind, count in pairs(seen) do parts[#parts + 1] = kind .. "=" .. count end
        table.sort(parts)
        print("[open77_creator] inputs " .. (#parts > 0 and table.concat(parts, " ") or "none"))
    end,
}

RegisterNetEvent("open77_creator:debug", function(name, a, b)
    local fn = Actions[tostring(name)] or DebugActions[tostring(name)]
    if not fn then return print("[open77_creator] debug: unknown action " .. tostring(name)) end
    local x = tonumber(a) or a
    local y = tonumber(b) or b
    fn(x, y)
    print(("[open77_creator] debug %s %s %s -> family=%s category=%s busy=%s"):format(tostring(name), tostring(a),
        tostring(b), S and S.family or "-", S and S.category or "-", S and tostring(S.busy) or "-"))
end)

RegisterNetEvent("open77_creator:saved", function(ok, reason)
    if not S then return end
    S.saveDeadline = nil
    if ok then
        print("[open77_creator] " .. T.saved)
        close(true)
    else
        S.saving, S.busy, S.status = false, false, tostring(reason)
        refresh()
    end
end)

-- In the world and settled: ask the server whether a creator waits (a new character). "Settled"
-- is strict on purpose: the world loads before the player is initialized and placed (the
-- gamemode's join spawn can teleport them seconds later), and a body switch in the middle of the
-- player's initialization breaks it. So: the player reset completed, then 5 s with the body still,
-- alive, and no body switch in flight.
local resetDone = false
AddEventHandler("open77:worldReady", function() worldReadyAt = GetGameTimer(); resetDone = false end)
AddEventHandler("open77:playerReset:complete", function() resetDone = true end)
-- The gamemode placed the player: watch for stillness again from here.
RegisterNetEvent("open77_creator:settle", function() worldReadyAt = GetGameTimer(); resetDone = true end)
CreateThread(function()
    local stillSince, lastPos = nil, nil
    while true do
        Wait(500)
        if worldReadyAt and resetDone and not S then
            local state = Open77.body.state()
            local pos = playerPosition()
            local alive = Open77.character.isAlive()
            local moved = not (pos and lastPos) or #(pos - lastPos) > 0.5
            lastPos = pos
            if not pos or not alive or not state or state.busy or moved then
                stillSince = nil
            elseif not stillSince then
                stillSince = GetGameTimer()
            elseif GetGameTimer() - stillSince > 5000 then
                worldReadyAt, stillSince, lastPos = nil, nil, nil
                TriggerServerEvent("open77_creator:ready")
            end
        end
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == Open77.resource.name() then close(true) end
end)
