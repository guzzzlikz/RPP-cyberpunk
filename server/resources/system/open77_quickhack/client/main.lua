-- open77_quickhack client/main.lua: the controller.
-- Hold the scanner key: the world goes to scanner vision, whatever hackable thing is under the
-- crosshair locks, the server scans it, and its data and the quickhacks that apply show up.
-- The client never decides an outcome: it asks the server (scan, execute) and draws the answer.

local cfg = QuickhackConfig
local UI = QuickhackUi
local KEY_PREFIX = "open77_quickhack_"

local catalogue = {}                    -- id -> public definition
local deck = { ram = 0, maxRam = cfg.deck.maxRam, regen = 0, enabled = true, cooldowns = {}, at = 0 }
local registry, auto = {}, { player = true }
local scanning, lock = false, nil
local candidate = nil                   -- { key, since } a target the crosshair moved to
local seq = 0
local uploads, alert = {}, nil
local vision = { native = false, tint = false }
local blocked = {}
local lastWheel, lastRam, lastRefresh = nil, -1, 0
local helpOn = false
local toggleTab                          -- defined with the key bindings

local function now() return GetGameTimer() end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end; return v end
local function int(v) return math.tointeger(tonumber(v)) or tonumber(v) end
local function tkey(kind, id) return tostring(kind) .. ":" .. tostring(kind == "point" and id or int(id)) end
-- a snapshot's position, whatever its shape ({x,y,z}, {position}, {transform = {position}})
local function posOf(snap)
    if type(snap) ~= "table" then return nil end
    local p = (type(snap.position) == "table" and snap.position) or (type(snap.transform) == "table" and snap.transform.position) or snap
    if type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) then return { x = p.x, y = p.y, z = p.z } end
    return nil
end

local function sfx(name)
    local ev = cfg.sounds[name]
    if ev and type(Open77.sfx) == "table" and type(Open77.sfx.play2d) == "function" then pcall(Open77.sfx.play2d, ev) end
end

local REASONS = {
    out_of_range = "OUT OF RANGE", insufficient_ram = "INSUFFICIENT RAM", upload_in_progress = "UPLOAD IN PROGRESS",
    target_gone = "TARGET LOST", not_hackable = "NO ACCESS", disabled = "CYBERDECK OFFLINE", not_in_deck = "NOT INSTALLED",
    uploading = "UPLOAD IN PROGRESS", cooldown = "COOLDOWN", blocked = "BLOCKED", hacker_gone = "CONNECTION LOST",
    self = "INVALID TARGET", invalid_target = "INVALID TARGET", unknown_quickhack = "UNKNOWN QUICKHACK", unavailable = "UNAVAILABLE",
    cancelled = "UPLOAD CANCELLED", noram = "INSUFFICIENT RAM", range = "OUT OF RANGE",
}
local function reasonText(r) return REASONS[r] or tostring(r or "REFUSED"):upper():gsub("_", " ") end

-- ---------------------------------------------------------------------------------- deck
local function ramNow()
    local t = now()
    deck.ram = math.min(deck.maxRam, deck.ram + deck.regen * (t - deck.at) / 1000)
    deck.at = t
    return deck.ram
end

-- the server's offer, overlaid with what the client knows better right now (RAM, cooldowns)
local function liveOffer(o)
    local def = catalogue[o.id]
    local out = { id = o.id, state = o.state, reason = o.reason }
    if not def then return out end
    local ends = deck.cooldowns[o.id]
    local t = now()
    local busy = false
    for _, up in pairs(uploads) do if up.def.id == o.id then busy = true end end
    if busy then out.state = "busy"
    elseif ends and ends > t then
        out.state = "cooldown"
        out.remainingS = (ends - t) / 1000
        out.cooldownFrac = clamp((ends - t) / math.max(1, (def.cooldown + def.upload) * 1000), 0, 1)
    elseif o.state == "cooldown" or o.state == "busy" or o.state == "noram" or o.state == "ready" then
        out.state = ramNow() + 1e-6 < def.ram and "noram" or "ready"
    end
    return out
end

-- ---------------------------------------------------------------------------------- vision
local function visionOn()
    vision.native, vision.tint = false, false
    if cfg.vision == "native" and type(Open77.braindance) == "table" and type(Open77.braindance.setHeatmap) == "function" then
        local okState, st = pcall(Open77.braindance.heatmap)
        local busy = okState and type(st) == "table" and st.enabled and not st.mine
        if not busy then
            local ok, res = pcall(Open77.braindance.setHeatmap, true, {
                radius = cfg.visionRadius, seeThroughWalls = true, npcs = true, players = true, vehicles = false,
                focusWorld = true, opacity = 1, maxTargets = cfg.visionMaxTargets or 24,
                colors = { npc = "hostile", player = "hostile", vehicle = "hackable", cool = "neutral",
                           warm = "hackable", hot = "weakspot", clue = "quest" },
            })
            -- the call answers true, or nothing at all, on success; false / nil, reason on refusal
            local st2 = ok and select(2, pcall(Open77.braindance.heatmap)) or nil
            vision.native = ok and res ~= false and (type(st2) ~= "table" or st2.enabled ~= false)
        end
    end
    if not vision.native and cfg.vision ~= "none" then vision.tint = true end
    UI.setTint(vision.tint)
end

local function visionOff()
    if vision.native then pcall(Open77.braindance.clearHeat); pcall(Open77.braindance.setHeatmap, false) end
    vision.native, vision.tint = false, false
    UI.setTint(false)
end

local function entityArg(t)
    if not t then return nil end
    if t.kind == "player" and Open77.players and Open77.players.entity then
        local ok, e = pcall(Open77.players.entity, t.id); if ok and e then return e end
    elseif t.kind == "npc" and Open77.npcs and Open77.npcs.entity then
        local ok, e = pcall(Open77.npcs.entity, t.id); if ok and e then return e end
    end
    if t.entity then return t.entity end
    if t.engineEntity then return { engineEntity = t.engineEntity } end
    return nil
end

local function highlight(t)
    if not vision.native then return end
    pcall(Open77.braindance.clearHeat)
    local e = t and entityArg(t)
    if e then pcall(Open77.braindance.setHeat, e, "hot") end
end

-- ---------------------------------------------------------------------------------- positions
-- Targets are followed through native anchors: the plugin projects them on every game frame
-- and Lua reads the results once per frame (Open77.anchors.list). Reading an entity's transform
-- from Lua (Open77.character.frame / bonePosition) costs ~0.6 s per call on another body and
-- froze the game: never call it per frame.
local anchors = {}                      -- target key -> { centre, head, refs, created }
local screens = {}                      -- anchor id -> last projection
local HUMAN = { player = true, npc = true }

local function readAnchors()
    screens = {}
    if not (Open77.anchors and Open77.anchors.list) then return end
    local ok, list, why = pcall(Open77.anchors.list)
    if cfg.debugAnchors and (not ok or type(list) ~= "table") and now() - (cfg._listLog or 0) > 1000 then
        cfg._listLog = now()
        print(("[open77_quickhack] anchors.list -> ok=%s list=%s why=%s"):format(tostring(ok), tostring(list), tostring(why)))
    end
    if not ok or type(list) ~= "table" then return end
    for _, a in ipairs(list) do screens[tostring(a.id)] = a end
    if cfg.debugAnchors and now() - (cfg._anchorLog or 0) > 1000 then
        cfg._anchorLog = now()
        print(("[open77_quickhack] anchors listed=%d"):format(#list))
        for _, a in ipairs(list) do
            print(("[open77_quickhack] anchor %s kind=%s entity=%s projected=%s onScreen=%s screen=%s dist=%s"):format(tostring(a.id), tostring(a.kind),
                tostring(a.entity), tostring(a.projected), tostring(a.onScreen), a.screen and ("%.2f,%.2f"):format(a.screen.x or -1, a.screen.y or -1) or "-",
                tostring(a.distance)))
        end
        for k, v in pairs(anchors) do print(("[open77_quickhack] tracked %s centre=%s head=%s"):format(k, tostring(v.centre), tostring(v.head))) end
    end
end

local function makeAnchor(t, dz)
    local spec = { render = "dot", visible = false, maxDistance = cfg.scanRange + 40 }
    local e = t.kind ~= "point" and entityArg(t) or nil
    if type(e) == "table" then e = e.engineEntity end
    if e then
        spec.entity, spec.offset = e, { x = 0, y = 0, z = dz }
    elseif t.position then
        spec.position = { x = t.position.x, y = t.position.y, z = t.position.z + dz }
    else
        return nil
    end
    local ok, id, why = pcall(Open77.anchors.create, spec)
    if not ok or not id then print("[open77_quickhack] anchor refused: " .. tostring(ok and why or id)) end
    return ok and id and tostring(id) or nil
end

local function track(t)
    local k = tkey(t.kind, t.id)
    local a = anchors[k]
    if not a and t.kind == "vehicle" then
        -- a vehicle follows its replicated snapshot (Open77.vehicles.get), read once per frame
        a = { refs = 0, created = now(), vehicle = true }
        anchors[k] = a
    elseif not a then
        local human, vehicle = HUMAN[t.kind], t.kind == "vehicle"
        a = { refs = 0, created = now(),
              centre = makeAnchor(t, human and 0.95 or vehicle and 0.8 or 0),
              head = makeAnchor(t, human and 1.85 or vehicle and 1.7 or 0.55),
              fallback = t.position }
        anchors[k] = a
    end
    a.refs = a.refs + 1
end

local function release(t)
    local k = tkey(t.kind, t.id)
    local a = anchors[k]
    if not a then return end
    a.refs = a.refs - 1
    if a.refs > 0 then return end
    anchors[k] = nil
    if a.centre then pcall(Open77.anchors.remove, a.centre) end
    if a.head then pcall(Open77.anchors.remove, a.head) end
end

local function projectPoint(p)
    if not p then return nil end
    local ok, s = pcall(Open77.camera.project, p)
    if not ok or type(s) ~= "table" or not s.onScreen then return nil end
    local w, h = UI.measure()
    return s.x * w, s.y * h, s.distance or s.depth
end

-- screen position of a tracked target: sx, sy, distance, hx, hy -- or nil, pending
local function screenOf(t)
    local a = anchors[tkey(t.kind, t.id)]
    if not a then return nil end
    local w, h = UI.measure()
    if a.vehicle then
        local ok, snap = pcall(Open77.vehicles.get, t.id)
        local p = ok and posOf(snap) or nil
        if not p then return nil end
        t.position = p
        local sx, sy, d = projectPoint({ x = p.x, y = p.y, z = p.z + 0.8 })
        if not sx then return nil end
        local hx, hy = projectPoint({ x = p.x, y = p.y, z = p.z + 1.9 })
        return sx, sy, d, hx or sx, hy or (sy - h * 0.08)
    end
    local c = a.centre and screens[a.centre]
    local hd = a.head and screens[a.head]
    if c and c.onScreen and c.screen then
        if c.resolved then t.position = { x = c.resolved.x, y = c.resolved.y, z = c.resolved.z } end
        local hx, hy = c.screen.x * w, c.screen.y * h - h * 0.08
        if hd and hd.onScreen and hd.screen then hx, hy = hd.screen.x * w, hd.screen.y * h end
        return c.screen.x * w, c.screen.y * h, c.distance, hx, hy
    end
    if not a.centre and a.fallback then
        local sx, sy, d = projectPoint(a.fallback)
        if sx then return sx, sy, d, sx, sy - h * 0.08 end
    end
    -- a fresh anchor has not been projected yet: not "off screen", just not known
    return nil, now() - a.created < 400
end

local project = projectPoint

-- ---------------------------------------------------------------------------------- targeting
local function isHackable(kind, id)
    if not kind then return false end
    return registry[tkey(kind, id)] ~= nil or auto[kind] == true
end

local function fromAimed(a)
    if type(a) ~= "table" then return nil end
    local kind, id
    if a.playerId then kind, id = "player", a.playerId
    elseif a.npcId then kind, id = "npc", a.npcId
    elseif a.vehicleId then kind, id = "vehicle", a.vehicleId
    elseif a.propId then kind, id = "prop", a.propId end
    if not kind or (a.distance and a.distance > cfg.scanRange) then return nil end
    if kind == "player" and Open77.players.localId and int(id) == Open77.players.localId() then return nil end
    if not isHackable(kind, id) then return nil end
    return { kind = kind, id = int(id), entity = a.entity, engineEntity = a.engineEntity, position = a.position }
end

-- Geometric pick: the look-at target the engine reports is often unavailable while the focus
-- vision is on, so every hackable body or point near the crosshair is projected and the closest
-- one to the centre of the screen wins. Bodies are tested as an upright box (0.9 m x 1.9 m).
local pickCache = { at = 0, result = nil }

-- Every hackable thing the client can place: registered points / NPCs / vehicles, and the
-- automatic kinds (network NPCs on screen, replicated vehicles, players). Read at most 10 times a second.
local function candidates()
    local list, seen = {}, {}
    local function add(t, pos, halfW, halfH, dz)
        local k = tkey(t.kind, t.id)
        if seen[k] or not pos then return end
        seen[k] = true
        t.position = t.position or pos
        list[#list + 1] = { t = t, pos = pos, halfW = halfW, halfH = halfH, dz = dz }
    end
    for _, reg in pairs(registry) do
        if reg.kind == "point" and reg.position then
            add({ kind = "point", id = reg.id, position = reg.position, name = reg.name }, reg.position, reg.radius or 1, reg.radius or 1, 0)
        elseif reg.kind == "npc" and Open77.npcs and Open77.npcs.get then
            local ok, snap = pcall(Open77.npcs.get, reg.id)
            add({ kind = "npc", id = int(reg.id) }, ok and posOf(snap) or nil, 0.45, 0.95, 0.95)
        elseif reg.kind == "vehicle" and Open77.vehicles and Open77.vehicles.get then
            local ok, snap = pcall(Open77.vehicles.get, reg.id)
            add({ kind = "vehicle", id = int(reg.id) }, ok and posOf(snap) or nil, 2.2, 0.9, 0.8)
        end
    end
    if auto.npc and Open77.npcs and Open77.npcs.all then
        local ok, all = pcall(Open77.npcs.all)
        for _, snap in ipairs(ok and type(all) == "table" and all or {}) do
            if snap.alive ~= false and snap.dead ~= true then
                add({ kind = "npc", id = int(snap.id) }, posOf(snap), 0.45, 0.95, 0.95)
            end
        end
    end
    if auto.vehicle and Open77.vehicles and Open77.vehicles.nearby then
        local ok, near = pcall(Open77.vehicles.nearby, cfg.scanRange)
        for _, snap in ipairs(ok and type(near) == "table" and near or {}) do
            if not snap.destroyed then add({ kind = "vehicle", id = int(snap.id) }, posOf(snap), 2.2, 0.9, 0.8) end
        end
    end
    if auto.player or next(registry) then
        local ok, near = pcall(Open77.players.nearby, cfg.scanRange)
        local me = Open77.players.localId and Open77.players.localId()
        for _, pl in ipairs(ok and type(near) == "table" and near or {}) do
            local pid = int(pl.playerId)
            local pos = type(pl.position) == "table" and pl.position or nil
            if pid and pid ~= me and isHackable("player", pid) then
                add({ kind = "player", id = pid, entity = pl.entity }, pos, 0.45, 0.95, 0.95)
            end
        end
    end
    return list
end

local function geometricPick()
    local t = now()
    if t - pickCache.at < 100 then return pickCache.result end
    pickCache.at = t
    local w, h = UI.measure()
    local cx, cy = w / 2, h / 2
    local best, bestScore
    for _, c in ipairs(candidates()) do
        local sx, sy, d = projectPoint({ x = c.pos.x, y = c.pos.y, z = c.pos.z + c.dz })
        if sx and d and d <= cfg.scanRange then
            local scale = h * 0.9 / math.max(d, 0.5)
            local rx = math.max(h * 0.025, c.halfW * scale)
            local ry = math.max(h * 0.04, c.halfH * scale)
            local nx, ny = math.abs(sx - cx) / rx, math.abs(sy - cy) / ry
            if nx <= 1 and ny <= 1 then
                local score = nx * nx + ny * ny + d * 0.002
                if not bestScore or score < bestScore then best, bestScore = c.t, score end
            end
        end
    end
    pickCache.result = best
    if cfg.debugAnchors and t - (cfg._pickLog or 0) > 1000 then
        cfg._pickLog = t
        print(("[open77_quickhack] pick best=%s:%s"):format(tostring(best and best.kind), tostring(best and best.id)))
    end
    return best
end

local function underCrosshair()
    local ok, aimed = pcall(Open77.character.aimedEntity)
    local t = ok and fromAimed(aimed) or nil
    if t then return t end
    return geometricPick()
end

-- every hackable thing on screen, left to right (1 / 3 cycle through it)
local function visibleTargets()
    local list = {}
    for _, c in ipairs(candidates()) do
        local sx = project({ x = c.pos.x, y = c.pos.y, z = c.pos.z + c.dz })
        if sx then list[#list + 1] = { t = c.t, x = sx } end
    end
    table.sort(list, function(a, b) return a.x < b.x end)
    return list
end

-- ---------------------------------------------------------------------------------- lock / scan
local function sendScan(silent)
    if not lock then return end
    seq = seq + 1
    lock.seq = seq
    lock.silent = silent
    TriggerServerEvent("open77_quickhack:scan", { seq = seq, target = { kind = lock.kind, id = lock.id } })
end

local function lockTarget(t)
    if lock and lock.key == tkey(t.kind, t.id) then return end
    if cfg.debugAnchors then print(("[open77_quickhack] lock %s:%s"):format(t.kind, tostring(t.id))) end
    if lock then UI.unlock(); release(lock) end
    lock = { key = tkey(t.kind, t.id), kind = t.kind, id = t.id, entity = t.entity, engineEntity = t.engineEntity,
             position = t.position, scanStart = now(), revealed = false, data = nil, offers = {}, selected = 1 }
    track(lock)
    local reg = registry[lock.key]
    UI.lock({ name = (reg and reg.name) or t.name or "SCANNING...", tone = (reg and reg.tone) or (t.kind == "point" and "device") or "hostile" })
    highlight(lock)
    sfx("scanStart")
    sendScan(false)
    TriggerEvent("open77_quickhack:targetLocked", { kind = t.kind, id = t.id })
end

local function unlockTarget()
    if not lock then return end
    release(lock)
    lock = nil
    UI.unlock()
    highlight(nil)
    sfx("scanStop")
end

local function offersIndex(list) local idx = {}; for _, o in ipairs(list) do idx[o.id] = o end; return idx end

local function liveOffers()
    local list = {}
    for i, o in ipairs(lock and lock.offers or {}) do list[i] = liveOffer(o) end
    return list
end

local function reveal()
    if not lock or lock.revealed or not lock.data then return end
    lock.revealed = true
    sfx("scanStop")
    sfx("scanDone")
    UI.scanProgress(1)
    local target = lock.data.target
    UI.lock({ name = target.name, tone = target.tone })
    UI.showData(target, lock.offers, catalogue, { ram = ramNow(), maxRam = deck.maxRam, regen = deck.regen })
    if lock.data.enabled == false then
        UI.setOffers({}, catalogue, 1, true)
        UI.toast("OFFLINE", "CYBERDECK OFFLINE", true)
    else
        UI.setOffers(liveOffers(), catalogue, 1, true)
        sfx("menuOpen")
    end
end

local refusedUntil = {}                 -- target key -> time: a refused target is not re-locked at once

RegisterNetEvent("open77_quickhack:scanResult", function(r)
    if type(r) ~= "table" or not lock or r.seq ~= lock.seq then return end
    if not r.ok then
        refusedUntil[lock.key] = now() + 1500
        if not lock.revealed then
            UI.toast("ACCESS", reasonText(r.reason), true, 1.2)
            sfx("denied")
            unlockTarget()
        end
        return
    end
    lock.data = r
    lock.offers = r.offers or {}
    if lock.revealed then
        -- a silent refresh: keep the list, update its states (and rebuild when the set changed)
        local before, same = UI.rowCount(), true
        if before ~= #lock.offers then same = false end
        if same then UI.updateRowStates(offersIndex(liveOffers()))
        else UI.setOffers(liveOffers(), catalogue, 1, false) end
    end
end)

-- ---------------------------------------------------------------------------------- execute
local function execute()
    if not scanning or not lock or not lock.revealed then return end
    local row, index = UI.selected()
    if not row then return end
    local o = liveOffer(row.offer)
    if o.state ~= "ready" then
        sfx("refused")
        UI.shakeRow(index)
        UI.toast("REFUSED", reasonText(o.reason or o.state), true, 1.2)
        return
    end
    seq = seq + 1
    lock.pendingIndex = index
    UI.flashRow(index)
    sfx("execute")
    TriggerServerEvent("open77_quickhack:execute", { seq = seq, target = { kind = lock.kind, id = lock.id }, quickhack = row.def.id })
end

RegisterNetEvent("open77_quickhack:executeResult", function(r)
    if type(r) ~= "table" or r.ok then return end
    sfx("denied")
    if lock and lock.pendingIndex then UI.shakeRow(lock.pendingIndex) end
    UI.toast("REFUSED", reasonText(r.reason), true, 1.4)
    if lock then sendScan(true) end
end)

RegisterNetEvent("open77_quickhack:upload", function(u)
    if type(u) ~= "table" then return end
    local def = catalogue[u.quickhack]
    if not def then return end
    local before = math.floor(ramNow() + 1e-6)
    deck.ram = math.max(0, deck.ram - (u.ram or def.ram))
    UI.spendRam(before, u.ram or def.ram)
    local t = { kind = u.target.kind, id = u.target.kind == "point" and u.target.id or int(u.target.id) }
    if lock and lock.key == tkey(t.kind, t.id) then t.entity, t.engineEntity, t.position = lock.entity, lock.engineEntity, lock.position end
    local reg = registry[tkey(t.kind, t.id)]
    if t.kind == "point" and reg then t.position = reg.position end
    uploads[u.uploadId] = { def = def, target = t, started = now(), duration = u.duration or 0 }
    track(t)
    UI.uploadStart(u.uploadId, def, true)
    sfx("uploadLoop")
    lastRam = -1
end)

RegisterNetEvent("open77_quickhack:uploadEnd", function(r)
    if type(r) ~= "table" then return end
    local up = uploads[r.uploadId]
    uploads[r.uploadId] = nil
    if up then release(up.target) end
    UI.uploadEnd(r.uploadId, r.ok)
    sfx("uploadStop")
    if r.ok then
        sfx("uploadDone"); sfx("granted")
        UI.toast("UPLOADED", (up and up.def.label or r.quickhack or ""):upper(), false, 1.4)
    else
        sfx("denied")
        UI.toast("FAILED", reasonText(r.reason), true, 1.6)
    end
    if lock and lock.revealed then sendScan(true) end
end)

-- ---------------------------------------------------------------------------------- the hacked side
RegisterNetEvent("open77_quickhack:incoming", function(u)
    if type(u) ~= "table" then return end
    alert = { uploadId = u.uploadId, started = now(), duration = u.duration or 0 }
    UI.alertStart({ label = u.label, icon = u.icon, from = u.from })
    sfx("incoming")
end)

-- A local preview of the warning a hacked player sees: TriggerEvent("open77_quickhack:previewIncoming",
-- { label = "Short Circuit", icon = "short_circuit", from = "Someone", duration = 3000, ok = true })
AddEventHandler("open77_quickhack:previewIncoming", function(spec)
    spec = type(spec) == "table" and spec or {}
    local uid = -now()
    alert = { uploadId = uid, started = now(), duration = tonumber(spec.duration) or 3000 }
    UI.alertStart({ label = spec.label or "Short Circuit", icon = spec.icon or "short_circuit", from = spec.from or "UNKNOWN" })
    sfx("incoming")
    SetTimeout(alert.duration, function()
        if alert and alert.uploadId == uid then
            alert = nil
            UI.alertEnd(spec.ok ~= false)
            sfx("incomingStop")
            sfx(spec.ok ~= false and "denied" or "granted")
        end
    end)
end)

RegisterNetEvent("open77_quickhack:incomingEnd", function(r)
    if type(r) ~= "table" or not alert or alert.uploadId ~= r.uploadId then return end
    alert = nil
    UI.alertEnd(r.ok)
    sfx("incomingStop")
    sfx(r.ok and "denied" or "granted")
end)

-- ---------------------------------------------------------------------------------- report cards
-- exports.open77_quickhack:report(playerId, card) on the server: what a Ping found, a scan log...
RegisterNetEvent("open77_quickhack:report", function(card)
    if type(card) ~= "table" then return end
    UI.report(card)
    sfx("scanDone")
end)

-- ---------------------------------------------------------------------------------- server state
RegisterNetEvent("open77_quickhack:catalogue", function(p)
    catalogue = {}
    for _, def in ipairs(type(p) == "table" and p.quickhacks or {}) do catalogue[def.id] = def end
end)

RegisterNetEvent("open77_quickhack:deck", function(d)
    if type(d) ~= "table" then return end
    deck.ram, deck.maxRam, deck.regen = tonumber(d.ram) or deck.ram, tonumber(d.maxRam) or deck.maxRam, tonumber(d.regen) or 0
    deck.enabled = d.enabled ~= false
    deck.at = now()
    deck.cooldowns = {}
    for id, ms in pairs(type(d.cooldowns) == "table" and d.cooldowns or {}) do deck.cooldowns[id] = now() + (tonumber(ms) or 0) end
    lastRam = -1
    if not deck.enabled and scanning then
        UI.toast("OFFLINE", "CYBERDECK OFFLINE", true)
    end
end)

RegisterNetEvent("open77_quickhack:targets", function(p)
    registry = {}
    for _, t in ipairs(type(p) == "table" and p.targets or {}) do
        local id = t.kind == "point" and t.id or int(t.id)
        registry[tkey(t.kind, id)] = { kind = t.kind, id = id, position = t.position, radius = t.radius, name = t.name, tone = t.tone }
    end
    auto = type(p) == "table" and type(p.auto) == "table" and p.auto or auto
end)

-- ---------------------------------------------------------------------------------- input
-- While the scanner is open, as in the game: no firing, no melee, no grenade, and the weapon
-- cannot change (wheel cycling, slot keys, holster, radial wheels). The mouse wheel still
-- reaches Open77.input.axis, which walks the quickhack list.
local SCANNER_BLOCKS = { "Attack", "Melee", "Grenade", "NextWeapon", "SwitchItem", "RadialWheels" }
local function setBlocks(on)
    if not (Open77.input and Open77.input.setActionBlocked) then return end
    for _, action in ipairs(SCANNER_BLOCKS) do
        if on and not blocked[action] then
            local ok, res, why = pcall(Open77.input.setActionBlocked, action, true)
            blocked[action] = ok and res ~= false
            if not blocked[action] then print(("[open77_quickhack] cannot block %s: %s"):format(action, tostring(ok and why or res))) end
        elseif not on and blocked[action] then pcall(Open77.input.setActionBlocked, action, false); blocked[action] = nil end
    end
    if cfg.debugAnchors and Open77.input.isActionBlocked then
        local parts = {}
        for _, action in ipairs(SCANNER_BLOCKS) do parts[#parts + 1] = action .. "=" .. tostring(select(2, pcall(Open77.input.isActionBlocked, action))) end
        print("[open77_quickhack] blocks (" .. (on and "open" or "closed") .. ") " .. table.concat(parts, " "))
    end
end

local function openScanner()
    if scanning or not UI.ready() then return end
    scanning = true
    candidate, lastRam, helpOn = nil, -1, false
    lastWheel = Open77.input and Open77.input.axis and select(2, pcall(Open77.input.axis, "mouseWheel")) or nil
    visionOn()
    setBlocks(true)
    UI.open({ ram = ramNow(), maxRam = deck.maxRam })
    sfx("open"); sfx("openLoop")
    TriggerEvent("open77_quickhack:scannerOpened")
end

local function closeScanner()
    if not scanning then return end
    scanning = false
    if lock then
        if lock.revealed then sfx("menuClose") end
        release(lock)
        lock = nil
    end
    visionOff()
    setBlocks(false)
    UI.close()
    sfx("close"); sfx("closeLoop")
    TriggerEvent("open77_quickhack:scannerClosed")
end

local function moveSelection(delta)
    if not scanning or not lock or not lock.revealed then return end
    local _, index = UI.selected()
    local n = UI.rowCount()
    if n == 0 then return end
    local nextIndex = clamp((index or 1) + delta, 1, n)
    if nextIndex ~= index then
        UI.select(nextIndex)
        sfx("hover")
        lastRam = -1
    end
end

local function cycleTarget(delta)
    if not scanning then return end
    local list = visibleTargets()
    if #list == 0 then return end
    local current = 0
    for i, e in ipairs(list) do if lock and tkey(e.t.kind, e.t.id) == lock.key then current = i end end
    local nextIndex = current == 0 and (delta > 0 and 1 or #list) or ((current - 1 + delta) % #list) + 1
    local under = underCrosshair()
    lockTarget(list[nextIndex].t)
    -- a target picked with 1 / 3 stays locked until the crosshair moves off what it was on
    candidate = { key = lock.key, since = now(), forcedSeen = under and tkey(under.kind, under.id) or "none" }
    sfx("targetChange")
end

toggleTab = function()
    if not scanning or not lock or not lock.revealed then return end
    lock.tab = lock.tab == "hacking" and "data" or "hacking"
    UI.setTab(lock.tab); sfx("tab")
end

local function bind(id, label, key, onPressed, onReleased)
    local spec = { id = KEY_PREFIX .. id, name = "Quickhack: " .. label, key = key, onPressed = onPressed }
    if onReleased then spec.hold, spec.onReleased = true, onReleased end
    local ok, res = pcall(Open77.input.registerKeyMapping, spec)
    if not ok or res == false then print("[open77_quickhack] key " .. id .. " refused: " .. tostring(res)) end
end

local function keyLabel(id, fallback)
    if Open77.input and Open77.input.keyFor then
        local ok, k = pcall(Open77.input.keyFor, KEY_PREFIX .. id)
        if ok and type(k) == "string" and k ~= "" then return k end
    end
    return fallback
end

-- ---------------------------------------------------------------------------------- frame loop
-- section timer: the worst duration of each part of the frame, printed once a second when a
-- frame cost more than 3 ms (the resume deadline is real time, so slow host calls show here)
local prof = { worst = {}, at = 0, clock = Open77.time and Open77.time.monotonic }
local function mark(name, t0)
    if not prof.clock then return end
    local ms = (prof.clock() - t0) * 1000
    if ms > (prof.worst[name] or 0) then prof.worst[name] = ms end
end
local function profNow() return prof.clock and prof.clock() or 0 end
local function profFlush(t)
    if t - prof.at < 1000 then return end
    prof.at = t
    local total, parts = 0, {}
    for k, v in pairs(prof.worst) do total = math.max(total, v); parts[#parts + 1] = ("%s=%.1f"):format(k, v) end
    if total > 8 then print("[open77_quickhack] frame ms worst: " .. table.concat(parts, " ")) end
    prof.worst = {}
end

local function frame()
    local t = now()
    local p0 = profNow()
    UI.tick()
    if scanning or next(uploads) then readAnchors() end
    mark("tick", p0); p0 = profNow()
    -- uploads stay over their target after the scanner closes
    for uid, up in pairs(uploads) do
        local _, _, _, hx, hy = screenOf(up.target)
        local p = up.duration > 0 and (t - up.started) / up.duration or 1
        UI.uploadUpdate(uid, hx or 0, hy or 0, p, up.duration - (t - up.started), hx ~= nil)
    end
    if alert then UI.alertProgress(alert.duration > 0 and (t - alert.started) / alert.duration or 1) end
    mark("uploads", p0); p0 = profNow()
    if not scanning then profFlush(t); return end

    -- what the crosshair is on (a new target must hold for a moment before it steals the lock)
    local seen = underCrosshair()
    if seen and (refusedUntil[tkey(seen.kind, seen.id)] or 0) > t then seen = nil end
    mark("aim", p0); p0 = profNow()
    local seenKey = seen and tkey(seen.kind, seen.id) or "none"
    if candidate and candidate.forcedSeen and seenKey ~= candidate.forcedSeen then candidate = nil end
    if seen then
        local k = seenKey
        if not lock then lockTarget(seen)
        elseif k ~= lock.key and not (candidate and candidate.forcedSeen) then
            if candidate and candidate.key == k then
                if t - candidate.since > 140 then lockTarget(seen); candidate = nil end
            else candidate = { key = k, since = t } end
        end
    end

    mark("lockswitch", p0); p0 = profNow()
    if lock then
        local sx, sy, dist, hx, hy = screenOf(lock)
        local pending = sx == nil and sy == true      -- screenOf answers nil, pending
        mark("project", p0); p0 = profNow()
        if pending then
            -- the anchor is being created: wait a frame or two
        elseif not sx then
            -- off screen: the game drops the lock when the target leaves the view
            if lock.revealed then sfx("menuClose") end
            unlockTarget()
        else
            local scale = clamp(9 / math.max(dist or 9, 1), 0.45, 1.5)
            UI.place(sx, sy, scale, hx or sx, hy or sy, dist, true)
            mark("place", p0); p0 = profNow()
            if not lock.revealed then
                local p = clamp((t - lock.scanStart) / (cfg.scanSeconds * 1000), 0, 1)
                UI.scanProgress(p)
                if p >= 1 and lock.data then reveal() end
            elseif t - lastRefresh > 2000 then
                lastRefresh = t
                sendScan(true)
            end
        end
    end

    mark("lockrest", p0); p0 = profNow()
    -- mouse wheel walks the list (the counter is cumulative: compare with the last reading)
    if lock and lock.revealed and Open77.input and Open77.input.axis then
        local ok, wheel = pcall(Open77.input.axis, "mouseWheel")
        if ok and type(wheel) == "number" then
            if lastWheel and wheel ~= lastWheel then moveSelection(wheel < lastWheel and 1 or -1) end
            lastWheel = wheel
        end
    end

    -- RAM bar: live regen, the selected quickhack's cost previewed on the cells
    local ram = ramNow()
    local cost = 0
    if lock and lock.revealed then
        local row = UI.selected()
        if row then cost = row.def.ram end
        if t - (lock.statesAt or 0) > 200 then
            lock.statesAt = t
            UI.updateRowStates(offersIndex(liveOffers()))
        end
    end
    local stamp = math.floor(ram * 10) * 100 + cost
    if stamp ~= lastRam then lastRam = stamp; UI.setRam(ram, deck.maxRam, cost) end
    mark("rows+ram", p0)
    profFlush(t)
end

-- ---------------------------------------------------------------------------------- start
CreateThread(function()
    local ok, why = UI.create(cfg)
    if not ok then print("[open77_quickhack] NativeUI unavailable: " .. tostring(why)); return end
    local k = cfg.keys
    bind("scanner", "Scanner", k.scanner, openScanner, closeScanner)
    bind("execute", "Upload quickhack", k.execute, execute)
    bind("prev", "Previous target", k.prev, function() cycleTarget(-1) end)
    bind("next", "Next target", k.next, function() cycleTarget(1) end)
    bind("up", "Previous quickhack", k.up, function() moveSelection(-1) end)
    bind("down", "Next quickhack", k.down, function() moveSelection(1) end)
    bind("tab", "Data / hacking tab", k.tab, function() toggleTab() end)
    bind("help", "Scanner help", k.help, function()
        if not scanning then return end
        helpOn = not helpOn
        UI.toggleHelp(helpOn); sfx("tab")
    end)
    UI.setKeys({ scanner = keyLabel("scanner", k.scanner), execute = keyLabel("execute", k.execute), prev = keyLabel("prev", k.prev),
        next = keyLabel("next", k.next), up = keyLabel("up", k.up), down = keyLabel("down", k.down), tab = keyLabel("tab", k.tab),
        help = keyLabel("help", k.help) })
    UI.setVendor(cfg.vendor)
    TriggerServerEvent("open77_quickhack:hello")
    while true do
        local okFrame, err = pcall(frame)
        if not okFrame then print("[open77_quickhack] frame: " .. tostring(err)) end
        Wait((scanning or next(uploads) or alert) and 0 or 120)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= (GetCurrentResourceName and GetCurrentResourceName() or "open77_quickhack") then return end
    if scanning then visionOff(); setBlocks(false) end
    UI.destroy()
end)

-- ---------------------------------------------------------------------------------- client exports
exports("isScanning", function() return scanning end)
exports("getLockedTarget", function() return lock and { kind = lock.kind, id = lock.id, revealed = lock.revealed } or nil end)
exports("open", function() openScanner(); return scanning end)
exports("close", function() closeScanner(); return true end)
exports("playSound", function(name) local ev = cfg.sounds[name] or name; if type(ev) == "string" then pcall(Open77.sfx.play2d, ev) end; return true end)
exports("setTheme", function(theme) return UI.setTheme(theme) end)
-- drive the menu from another input scheme (a gamepad layer, a test): move, upload, retarget
exports("selectNext", function() moveSelection(1); return true end)
exports("selectPrevious", function() moveSelection(-1); return true end)
exports("execute", function() execute(); return true end)
exports("nextTarget", function() cycleTarget(1); return true end)
exports("previousTarget", function() cycleTarget(-1); return true end)
exports("toggleTab", function() if toggleTab then toggleTab() end; return true end)
