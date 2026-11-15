-- open77_quickhack server: the authority.
-- Resources declare quickhacks and targets through exports. Players ask (scan, execute) through
-- net events, and this file decides: target, bucket, range, RAM, cooldown, the owner's canUse.
-- It runs the upload timer and calls the owner's onExecute export.
-- Hooks are export NAMES in the owner resource (closures do not cross resources).

local cfg = QuickhackConfig
local KINDS = { player = true, npc = true, vehicle = true, prop = true, point = true }
local TONES = { hostile = true, neutral = true, friendly = true, device = true }
local THREATS = { low = 1, medium = 2, high = 3, extreme = 4 }

local defs, order = {}, {}            -- id -> definition, registration order
local decks = {}                       -- playerId -> deck
local targets = {}                     -- "kind:id" -> registered target
local playerInfo = {}                  -- playerId -> DATA panel info
local uploads, uploadOf = {}, {}       -- uploadId -> upload, hacker -> uploadId
local scanBudget = {}                  -- playerId -> { windowStart, count }
local autoTargets = {}
for k, v in pairs(cfg.autoTargets) do autoTargets[k] = v end
local uploadSerial = 0
local SELF = GetCurrentResourceName and GetCurrentResourceName() or "open77_quickhack"

local function now() return GetGameTimer() end
local function clamp(v, lo, hi) v = tonumber(v) or lo; if v < lo then return lo elseif v > hi then return hi end; return v end
local function str(v, max) if type(v) ~= "string" then return nil end; v = v:gsub("[%c]", " "); if #v > max then v = v:sub(1, max) end; return v end
local function caller() return (GetInvokingResource and GetInvokingResource()) or SELF end
local function key(kind, id) return tostring(kind) .. ":" .. tostring(id) end
local function vec(p)
    if type(p) ~= "table" then return nil end
    local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z }
end
local function dist(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z; return math.sqrt(dx * dx + dy * dy + dz * dz) end
local function log(fmt, ...) print(("[open77_quickhack] " .. fmt):format(...)) end

-- ---------------------------------------------------------------------------------- hooks
local function hookName(v) return type(v) == "string" and v:match("^[%a_][%w_]*$") and #v <= 64 and v or nil end

-- canUse runs inline (sync export) so a preview can show "BLOCKED" with the owner's reason.
local function callGate(def, source, target, check)
    if not def.canUse then return true end
    local ok, allowed, reason = pcall(Open77.exports.callSync, def.owner, def.canUse,
        { source = source, target = target, quickhack = def.id, check = check == true })
    if not ok then
        log("canUse %s.%s failed: %s", def.owner, def.canUse, tostring(allowed))
        return false, "unavailable"
    end
    if allowed == false then return false, str(reason, 40) or "blocked" end
    return true
end

-- the other hooks are fire-and-forget (they may take their time)
local function callHook(def, name, payload)
    local export = def[name]
    if not export then return end
    local promise, why = Open77.exports.call(def.owner, export, payload)
    if not promise then log("%s %s.%s refused: %s", name, def.owner, export, tostring(why)) end
end

-- ---------------------------------------------------------------------------------- definitions
local function publicDef(def)
    return { id = def.id, label = def.label, description = def.description, icon = def.icon, category = def.category,
             ram = def.ram, upload = def.upload, cooldown = def.cooldown, range = def.range, targets = def.targetList,
             order = def.order }
end

local catalogueDirty = false
local function broadcastCatalogue()
    if catalogueDirty then return end
    catalogueDirty = true
    SetTimeout(50, function()
        catalogueDirty = false
        local list = {}
        for _, id in ipairs(order) do if defs[id] then list[#list + 1] = publicDef(defs[id]) end end
        TriggerClientEvent("open77_quickhack:catalogue", -1, { quickhacks = list })
    end)
end

local function normalizeDef(spec, owner)
    if type(spec) ~= "table" then return nil, "definition_required" end
    local id = type(spec.id) == "string" and spec.id:match("^[a-z0-9_]+$") and #spec.id <= 48 and spec.id
    if not id then return nil, "invalid_id" end
    local icon = spec.icon
    if type(icon) ~= "string" or not (icon:match("^[a-z0-9_]+$") or icon:match("^nui://[%w_%-]+/[%w_%-/%.]+%.png$")) then
        icon = "generic"
    end
    local category = QuickhackCategories[spec.category] and spec.category or "covert"
    local list, set = {}, {}
    for _, kind in ipairs(type(spec.targets) == "table" and spec.targets or { "player", "npc", "vehicle", "prop", "point" }) do
        if KINDS[kind] and not set[kind] then set[kind] = true; list[#list + 1] = kind end
    end
    if #list == 0 then return nil, "no_target_kind" end
    return {
        id = id, owner = owner,
        label = str(spec.label, 40) or id:upper(),
        description = str(spec.description, 240) or "",
        icon = icon, category = category,
        ram = math.floor(clamp(spec.ram, 0, 99)),
        upload = clamp(spec.upload or 1.5, 0, 30),
        cooldown = clamp(spec.cooldown or 0, 0, 3600),
        range = clamp(spec.range or cfg.scanRange, 1, 250),
        targetSet = set, targetList = list,
        uploadDetected = spec.uploadDetected ~= false,
        impactSound = type(spec.impactSound) == "string" and spec.impactSound:match("^[a-z0-9_]+$") and #spec.impactSound <= 96
            and spec.impactSound or nil,
        order = tonumber(spec.order) or (QuickhackCategories[category] * 100),
        canUse = hookName(spec.canUse), onStart = hookName(spec.onStart),
        onExecute = hookName(spec.onExecute), onCancel = hookName(spec.onCancel),
    }
end

local function register(spec)
    local owner = caller()
    local def, why = normalizeDef(spec, owner)
    if not def then return false, why end
    local existing = defs[def.id]
    if existing and existing.owner ~= owner then return false, "id_taken" end
    if not existing then order[#order + 1] = def.id end
    defs[def.id] = def
    broadcastCatalogue()
    return true
end

local function registerPreset(presetId, overrides)
    local preset = QuickhackPresets[presetId]
    if not preset then return false, "unknown_preset" end
    local spec = { id = presetId }
    for k, v in pairs(preset) do spec[k] = v end
    for k, v in pairs(type(overrides) == "table" and overrides or {}) do spec[k] = v end
    return register(spec)
end

-- Internal: drop a definition whatever its owner (the bundled examples switch themselves off).
function QuickhackRemove(id)
    if not defs[id] then return false end
    defs[id] = nil
    for i = #order, 1, -1 do if order[i] == id then table.remove(order, i) end end
    broadcastCatalogue()
    return true
end
QuickhackRegister = function(spec) return register(spec) end

local function unregister(id)
    local def = defs[id]
    if not def then return false, "unknown" end
    if def.owner ~= caller() then return false, "not_owner" end
    defs[id] = nil
    for i = #order, 1, -1 do if order[i] == id then table.remove(order, i) end end
    broadcastCatalogue()
    return true
end

-- ---------------------------------------------------------------------------------- decks
local function deckOf(pid)
    local deck = decks[pid]
    if not deck then
        deck = { ram = cfg.deck.ram, maxRam = cfg.deck.maxRam, regen = cfg.deck.regen, slots = nil, enabled = true,
                 cooldowns = {}, at = now() }
        if #cfg.deck.slots > 0 then deck.slots = { table.unpack(cfg.deck.slots) } end
        decks[pid] = deck
    end
    local t = now()
    deck.ram = math.min(deck.maxRam, deck.ram + deck.regen * (t - deck.at) / 1000)
    deck.at = t
    return deck
end

local function pushDeck(pid)
    local deck = deckOf(pid)
    local t, cds = now(), {}
    for id, ends in pairs(deck.cooldowns) do
        if ends > t then cds[id] = ends - t else deck.cooldowns[id] = nil end
    end
    TriggerClientEvent("open77_quickhack:deck", pid, { ram = deck.ram, maxRam = deck.maxRam, regen = deck.regen,
        enabled = deck.enabled, cooldowns = cds, slots = deck.slots or false })
end

-- ---------------------------------------------------------------------------------- targets
local function sanitizeInfo(info)
    info = type(info) == "table" and info or {}
    local out = {
        name = str(info.name, 48), affiliation = str(info.affiliation, 48), description = str(info.description, 200),
        tone = TONES[info.tone] and info.tone or nil,
        threat = THREATS[info.threat] or (tonumber(info.threat) and math.floor(clamp(info.threat, 0, 4))) or nil,
        bounty = tonumber(info.bounty) and math.floor(clamp(info.bounty, 0, 1e9)) or nil,
        streetCred = tonumber(info.streetCred) and math.floor(clamp(info.streetCred, 0, 1e6)) or nil,
        stars = tonumber(info.stars) and math.floor(clamp(info.stars, 0, 5)) or nil,
        wanted = str(info.wanted, 32),
        fields = {}, abilities = {}, vulnerabilities = {},
    }
    for i, f in ipairs(type(info.fields) == "table" and info.fields or {}) do
        if i > 8 then break end
        local k, v = str(f[1] or f.label, 32), str(f[2] or f.value, 48)
        if k and v then out.fields[#out.fields + 1] = { k, v } end
    end
    for i, a in ipairs(type(info.abilities) == "table" and info.abilities or {}) do
        if i > 6 then break end
        local label = str(type(a) == "table" and (a.label or a[1]) or a, 32)
        local icon = type(a) == "table" and type(a.icon) == "string" and a.icon:match("^[a-z0-9_]+$") or "generic"
        if label then out.abilities[#out.abilities + 1] = { label = label, icon = icon } end
    end
    for i, v in ipairs(type(info.vulnerabilities) == "table" and info.vulnerabilities or {}) do
        if i > 8 then break end
        local s = str(v, 40)
        if s then out.vulnerabilities[#out.vulnerabilities + 1] = s end
    end
    return out
end

-- A readable name from a TweakDB record: "Vehicle.v_sport2_quadra_type66" -> "QUADRA TYPE66".
local function recordName(record, fallback)
    if type(record) ~= "string" or record == "" or record == "record" then return fallback end
    local short = record:gsub("^[%w]+%.", ""):gsub("^v_", ""):gsub("^[a-z]+%d*_", "", 1)
    short = short:gsub("_", " "):upper()
    return #short > 0 and short:sub(1, 40) or fallback
end

-- Another resource's NPC snapshot (record, health) for names and Ping; cached one second.
local foreignNpcs, foreignAt = {}, -10000
local function foreignNpc(id)
    if now() - foreignAt > 1000 then
        foreignAt, foreignNpcs = now(), {}
        local ok, list = pcall(Open77.npcs.all, { includeForeign = true })
        for _, snap in ipairs(ok and type(list) == "table" and list or {}) do foreignNpcs[math.tointeger(tonumber(snap.id)) or snap.id] = snap end
    end
    return foreignNpcs[id]
end

-- Position, bucket and a snapshot of an NPC, vehicle or prop, or nil.
local function entitySnapshot(kind, id)
    if kind == "npc" then
        local ok, snap = pcall(Open77.npcs.get, id)                      -- one of ours
        if ok and type(snap) == "table" then return vec(snap), tonumber(snap.bucket), snap end
        local okP, presence, whyP = pcall(Open77.npcs.presence, id)      -- any resource's (npcs.foreign)
        if cfg.debugAnchors then log("presence(%s) -> ok=%s %s %s", tostring(id), tostring(okP), tostring(presence), tostring(whyP)) end
        if okP and type(presence) == "table" then
            if presence.alive == false then return nil end
            return vec(presence), tonumber(presence.bucket), foreignNpc(id) or presence
        end
        return nil
    end
    local api = kind == "vehicle" and Open77.vehicles or kind == "prop" and Open77.props
    if not api or type(api.get) ~= "function" then return nil end
    local ok, snap, why = pcall(api.get, id)
    if cfg.debugAnchors and (not ok or type(snap) ~= "table") then
        log("%s.get(%s %s) -> ok=%s %s %s", kind, tostring(id), math.type(id) or type(id), tostring(ok), tostring(snap), tostring(why))
        if kind == "vehicle" then
            local okA, all, whyA = pcall(Open77.vehicles.all)
            local ids = {}
            for _, v in ipairs(okA and type(all) == "table" and all or {}) do ids[#ids + 1] = ("%s(%s)"):format(tostring(v.id), math.type(v.id) or type(v.id)) end
            log("vehicles.all -> %d %s %s", #ids, table.concat(ids, " "):sub(1, 300), tostring(whyA))
        end
    end
    if not ok or type(snap) ~= "table" then return nil end
    if snap.destroyed or snap.exploded then return nil end
    local pos = vec(snap.position) or vec(snap.transform and snap.transform.position) or vec(snap)
    return pos, tonumber(snap.bucket), snap
end

-- What the server knows about a target right now, or nil, reason.
local function resolve(t)
    if type(t) ~= "table" or not KINDS[t.kind] then return nil, "invalid_target" end
    local kind = t.kind
    local id = kind == "point" and str(t.id, 64) or math.tointeger(tonumber(t.id))
    if not id then return nil, "invalid_target" end
    local reg = targets[key(kind, id)]
    local out = { kind = kind, id = id }
    if kind == "player" then
        if not reg and not autoTargets.player then return nil, "not_hackable" end
        local pos = Open77.players.position(id)
        if not pos then return nil, "target_gone" end
        out.position, out.bucket = vec(pos), tonumber(pos.bucket)
        local info = playerInfo[id] or {}
        out.info = info
        out.name = info.name or Open77.players.name(id) or ("PLAYER " .. id)
        out.tone = info.tone or "hostile"
    elseif kind == "point" then
        if not reg then return nil, "target_gone" end
        out.position = reg.position
        out.bucket = reg.bucket
    else
        if not reg and not autoTargets[kind] then return nil, "not_hackable" end
        local pos, bucket, snap = entitySnapshot(kind, id)
        out.snapshot = snap
        if snap then
            out.name = recordName(snap.record, nil)
            out.tone = kind == "vehicle" and "device" or nil
        end
        -- entities another resource owns (its NPCs): that resource tells where they are
        if not pos and reg and reg.locate then
            local ok, where = pcall(Open77.exports.callSync, reg.owner, reg.locate, { kind = kind, id = id })
            if ok and type(where) == "table" then pos, bucket = vec(where), tonumber(where.bucket)
            elseif cfg.debugAnchors then log("locate %s.%s(%s) -> ok=%s %s", reg.owner, reg.locate, tostring(id), tostring(ok), tostring(where)) end
        end
        if not pos then return nil, "target_gone" end
        out.position, out.bucket = pos, bucket
    end
    if reg then
        out.info = reg.info
        out.name = reg.info.name or reg.name or out.name
        out.tone = reg.info.tone or reg.tone or out.tone
        out.quickhacks = reg.quickhacks
        out.radius = reg.radius
    end
    out.info = out.info or {}
    out.name = out.name or (kind == "vehicle" and "VEHICLE" or kind == "npc" and "UNKNOWN" or "DEVICE")
    out.tone = out.tone or (kind == "npc" and "hostile" or "device")
    return out
end

local pointsDirty = false
local function broadcastTargets(pid)
    local function payload()
        local list = {}
        for _, reg in pairs(targets) do
            list[#list + 1] = { kind = reg.kind, id = reg.id, position = reg.position, radius = reg.radius,
                                name = reg.info.name or reg.name, tone = reg.info.tone or reg.tone }
        end
        return { targets = list, auto = autoTargets }
    end
    if pid then TriggerClientEvent("open77_quickhack:targets", pid, payload()); return end
    if pointsDirty then return end
    pointsDirty = true
    SetTimeout(80, function() pointsDirty = false; TriggerClientEvent("open77_quickhack:targets", -1, payload()) end)
end

local function addTarget(spec)
    if type(spec) ~= "table" or not KINDS[spec.kind] then return false, "invalid_kind" end
    local kind = spec.kind
    local id = kind == "point" and str(spec.id, 64) or math.tointeger(tonumber(spec.id))
    if not id or (kind == "point" and not id:match("^[%w_%-%.:]+$")) then return false, "invalid_id" end
    local k = key(kind, id)
    local owner = caller()
    if targets[k] and targets[k].owner ~= owner then return false, "id_taken" end
    local reg = { kind = kind, id = id, owner = owner, info = sanitizeInfo(spec.info),
                  name = str(spec.name, 48), tone = TONES[spec.tone] and spec.tone or nil,
                  radius = clamp(spec.radius or 1.2, 0.2, 30), bucket = tonumber(spec.bucket) or 0,
                  locate = hookName(spec.locate) }
    if spec.name and not reg.info.name then reg.info.name = reg.name end
    if spec.tone and not reg.info.tone then reg.info.tone = reg.tone end
    if kind == "point" then
        reg.position = vec(spec.position)
        if not reg.position then return false, "position_required" end
    end
    if type(spec.quickhacks) == "table" then
        reg.quickhacks = {}
        for _, q in ipairs(spec.quickhacks) do if type(q) == "string" then reg.quickhacks[#reg.quickhacks + 1] = q end end
    end
    targets[k] = reg
    broadcastTargets()
    return true, k
end

local function findTarget(idOrSpec)
    if type(idOrSpec) == "table" then return key(idOrSpec.kind, idOrSpec.id) end
    if targets[key("point", idOrSpec)] then return key("point", idOrSpec) end
    return idOrSpec
end

local function updateTarget(idOrSpec, patch)
    local k = findTarget(idOrSpec)
    local reg = targets[k]
    if not reg then return false, "unknown" end
    if reg.owner ~= caller() then return false, "not_owner" end
    patch = type(patch) == "table" and patch or {}
    if patch.position then reg.position = vec(patch.position) or reg.position end
    if patch.radius then reg.radius = clamp(patch.radius, 0.2, 30) end
    if patch.info then
        local merged = {}
        for k2, v in pairs(reg.info) do merged[k2] = v end
        for k2, v in pairs(patch.info) do merged[k2] = v end
        reg.info = sanitizeInfo(merged)
    end
    if type(patch.quickhacks) == "table" then reg.quickhacks = patch.quickhacks end
    broadcastTargets()
    return true
end

local function removeTarget(idOrSpec)
    local k = findTarget(idOrSpec)
    local reg = targets[k]
    if not reg then return false, "unknown" end
    if reg.owner ~= caller() then return false, "not_owner" end
    targets[k] = nil
    broadcastTargets()
    return true
end

-- ---------------------------------------------------------------------------------- offers
local function hackerPosition(pid)
    local pos = Open77.players.position(pid)
    return pos and vec(pos), pos and tonumber(pos.bucket)
end

local function candidateIds(deck, target)
    local ids = target.quickhacks or deck.slots
    if not ids then return order end
    return ids
end

local function evaluate(pid, def, target, deck, from, check)
    if not def.targetSet[target.kind] then return "blocked", "invalid_target" end
    local t = now()
    local cd = deck.cooldowns[def.id]
    if uploadOf[pid] and uploads[uploadOf[pid]] and uploads[uploadOf[pid]].def.id == def.id then return "busy", "uploading" end
    if cd and cd > t then return "cooldown", nil, cd - t end
    if from and target.position and dist(from, target.position) > def.range + cfg.rangeTolerance then return "range", "out_of_range" end
    if deck.ram + 1e-6 < def.ram then return "noram", "insufficient_ram" end
    local ok, reason = callGate(def, pid, { kind = target.kind, id = target.id, position = target.position }, check)
    if not ok then return "blocked", reason end
    return "ready"
end

local function offers(pid, target)
    local deck = deckOf(pid)
    local from = hackerPosition(pid)
    local list = {}
    for _, id in ipairs(candidateIds(deck, target)) do
        local def = defs[id]
        if def and def.targetSet[target.kind] then
            local state, reason, remaining = evaluate(pid, def, target, deck, from, true)
            list[#list + 1] = { id = id, state = state, reason = reason, remaining = remaining }
        end
    end
    table.sort(list, function(a, b)
        local da, db = defs[a.id], defs[b.id]
        if da.order ~= db.order then return da.order < db.order end
        return da.ram < db.ram
    end)
    return list
end

local function publicTarget(target)
    local info = target.info or {}
    return { kind = target.kind, id = target.id, name = target.name, tone = target.tone, info = info }
end

-- ---------------------------------------------------------------------------------- uploads
local function finishUpload(uid, ok, reason)
    local up = uploads[uid]
    if not up then return end
    uploads[uid] = nil
    if uploadOf[up.hacker] == uid then uploadOf[up.hacker] = nil end
    local payload = { uploadId = uid, ok = ok, reason = reason, quickhack = up.def.id }
    TriggerClientEvent("open77_quickhack:uploadEnd", up.hacker, payload)
    if up.victim then TriggerClientEvent("open77_quickhack:incomingEnd", up.victim, payload) end
    local target = { kind = up.target.kind, id = up.target.id, position = up.target.position }
    if ok then
        -- the game's impact sound, heard around the target (players, NPCs, vehicles, props)
        if up.def.impactSound and target.kind ~= "point" and Open77.effects and Open77.effects.sound then
            local played, why = pcall(Open77.effects.sound, { kind = target.kind, id = target.id }, up.def.impactSound, {})
            if not played or why == false then log("impact sound %s refused: %s", up.def.impactSound, tostring(why)) end
        end
        callHook(up.def, "onExecute", { source = up.hacker, target = target, quickhack = up.def.id, uploadId = uid })
        TriggerEvent("open77_quickhack:executed", up.hacker, target, up.def.id)
    else
        callHook(up.def, "onCancel", { source = up.hacker, target = target, quickhack = up.def.id, uploadId = uid, reason = reason })
        TriggerEvent("open77_quickhack:cancelled", up.hacker, target, up.def.id, reason)
    end
    pushDeck(up.hacker)
end

local function completeUpload(uid)
    local up = uploads[uid]
    if not up then return end
    local target, why = resolve(up.target)
    if not target then return finishUpload(uid, false, why) end
    local from, bucket = hackerPosition(up.hacker)
    if not from then return finishUpload(uid, false, "hacker_gone") end
    if target.bucket and bucket and target.bucket ~= bucket then return finishUpload(uid, false, "target_gone") end
    if dist(from, target.position) > up.def.range + cfg.rangeTolerance * 2 then return finishUpload(uid, false, "out_of_range") end
    up.target.position = target.position
    finishUpload(uid, true)
end

local function startUpload(pid, def, target, deck)
    uploadSerial = uploadSerial + 1
    local uid = uploadSerial
    local ms = math.floor(def.upload * 1000)
    deck.ram = deck.ram - def.ram
    deck.cooldowns[def.id] = now() + ms + math.floor(def.cooldown * 1000)
    local up = { id = uid, hacker = pid, def = def, target = { kind = target.kind, id = target.id, position = target.position },
                 started = now(), ends = now() + ms }
    if target.kind == "player" and def.uploadDetected and target.id ~= pid then up.victim = target.id end
    uploads[uid], uploadOf[pid] = up, uid
    TriggerClientEvent("open77_quickhack:upload", pid, { uploadId = uid, quickhack = def.id, target = { kind = target.kind, id = target.id },
        duration = ms, ram = def.ram })
    if up.victim then
        TriggerClientEvent("open77_quickhack:incoming", up.victim, { uploadId = uid, quickhack = def.id, label = def.label,
            icon = def.icon, category = def.category, duration = ms, from = Open77.players.name(pid) or ("PLAYER " .. pid) })
    end
    callHook(def, "onStart", { source = pid, target = { kind = target.kind, id = target.id, position = target.position }, quickhack = def.id, uploadId = uid })
    TriggerEvent("open77_quickhack:started", pid, { kind = target.kind, id = target.id, position = target.position }, def.id)
    pushDeck(pid)
    if ms <= 0 then completeUpload(uid) else SetTimeout(ms, function() completeUpload(uid) end) end
    return uid
end

local function cancelUpload(uid, reason)
    if uploads[uid] then finishUpload(uid, false, reason or "cancelled"); return true end
    return false
end

-- ---------------------------------------------------------------------------------- net
local function budget(pid, limit)
    local t = now()
    local b = scanBudget[pid]
    if not b or t - b[1] > 1000 then b = { t, 0 }; scanBudget[pid] = b end
    b[2] = b[2] + 1
    return b[2] <= limit
end

RegisterNetEvent("open77_quickhack:hello", function()
    local pid = source
    local list = {}
    for _, id in ipairs(order) do if defs[id] then list[#list + 1] = publicDef(defs[id]) end end
    TriggerClientEvent("open77_quickhack:catalogue", pid, { quickhacks = list })
    broadcastTargets(pid)
    pushDeck(pid)
end)

RegisterNetEvent("open77_quickhack:scan", function(request)
    local pid = source
    if type(request) ~= "table" or not budget(pid, 25) then return end
    local seq = math.tointeger(tonumber(request.seq)) or 0
    local deck = deckOf(pid)
    local target, why = resolve(request.target)
    if target and request.target.kind == "player" and target.id == pid then target, why = nil, "self" end
    if target then
        local from, bucket = hackerPosition(pid)
        if target.bucket and bucket and target.bucket ~= bucket then target, why = nil, "target_gone" end
        if target and from and dist(from, target.position) > cfg.scanRange + cfg.rangeTolerance then target, why = nil, "out_of_range" end
    end
    if not target then
        if cfg.debugAnchors then log("scan refused player=%s target=%s:%s reason=%s", tostring(pid), tostring(request.target and request.target.kind), tostring(request.target and request.target.id), tostring(why)) end
        TriggerClientEvent("open77_quickhack:scanResult", pid, { seq = seq, ok = false, reason = why })
        return
    end
    TriggerClientEvent("open77_quickhack:scanResult", pid, { seq = seq, ok = true, target = publicTarget(target),
        offers = deck.enabled and offers(pid, target) or {}, enabled = deck.enabled })
end)

RegisterNetEvent("open77_quickhack:execute", function(request)
    local pid = source
    if type(request) ~= "table" or not budget(pid, 25) then return end
    local seq = math.tointeger(tonumber(request.seq)) or 0
    local function refuse(reason)
        TriggerClientEvent("open77_quickhack:executeResult", pid, { seq = seq, ok = false, reason = reason, quickhack = request.quickhack })
    end
    local def = type(request.quickhack) == "string" and defs[request.quickhack]
    if not def then return refuse("unknown_quickhack") end
    local deck = deckOf(pid)
    if not deck.enabled then return refuse("disabled") end
    if uploadOf[pid] and uploads[uploadOf[pid]] then return refuse("upload_in_progress") end
    local target, why = resolve(request.target)
    if not target then return refuse(why) end
    if target.kind == "player" and target.id == pid then return refuse("self") end
    local from, bucket = hackerPosition(pid)
    if not from then return refuse("hacker_gone") end
    if target.bucket and bucket and target.bucket ~= bucket then return refuse("target_gone") end
    local allowed = false
    for _, id in ipairs(candidateIds(deck, target)) do if id == def.id then allowed = true; break end end
    if not allowed then return refuse("not_in_deck") end
    local state, reason = evaluate(pid, def, target, deck, from, false)
    if state ~= "ready" then return refuse(reason or state) end
    local uid = startUpload(pid, def, target, deck)
    TriggerClientEvent("open77_quickhack:executeResult", pid, { seq = seq, ok = true, uploadId = uid, quickhack = def.id })
end)

local function dropPlayer(pid)
    pid = math.tointeger(tonumber(pid))
    if not pid then return end
    if uploadOf[pid] then cancelUpload(uploadOf[pid], "hacker_gone") end
    for uid, up in pairs(uploads) do
        if up.target.kind == "player" and up.target.id == pid then cancelUpload(uid, "target_gone") end
    end
    decks[pid], playerInfo[pid], scanBudget[pid] = nil, nil, nil
end
AddEventHandler("playerDropped", function(pid) dropPlayer(pid or source) end)
AddEventHandler("onPlayerDisconnected", function(pid) dropPlayer(pid) end)

-- a stopped resource takes its quickhacks and targets with it
AddEventHandler("onResourceStop", function(name)
    if name == SELF then return end
    local changed = false
    for id, def in pairs(defs) do
        if def.owner == name then
            defs[id] = nil; changed = true
            for i = #order, 1, -1 do if order[i] == id then table.remove(order, i) end end
        end
    end
    if changed then broadcastCatalogue() end
    local dropped = false
    for k, reg in pairs(targets) do if reg.owner == name then targets[k] = nil; dropped = true end end
    if dropped then broadcastTargets() end
end)

-- ---------------------------------------------------------------------------------- exports
exports("register", register)
exports("registerPreset", registerPreset)
exports("unregister", unregister)
exports("preset", function(id) return QuickhackPresets[id] end)
exports("presets", function() local ids = {}; for id in pairs(QuickhackPresets) do ids[#ids + 1] = id end; table.sort(ids); return ids end)
exports("list", function() local list = {}; for _, id in ipairs(order) do list[#list + 1] = publicDef(defs[id]) end; return list end)

exports("getDeck", function(pid)
    local d = deckOf(pid)
    return { ram = d.ram, maxRam = d.maxRam, regen = d.regen, enabled = d.enabled, slots = d.slots }
end)
exports("setDeck", function(pid, spec)
    local d = deckOf(pid)
    spec = type(spec) == "table" and spec or {}
    if spec.maxRam then d.maxRam = math.floor(clamp(spec.maxRam, 1, 40)) end
    if spec.regen then d.regen = clamp(spec.regen, 0, 20) end
    if spec.ram then d.ram = clamp(spec.ram, 0, d.maxRam) else d.ram = math.min(d.ram, d.maxRam) end
    if spec.slots ~= nil then d.slots = type(spec.slots) == "table" and { table.unpack(spec.slots) } or nil end
    if spec.enabled ~= nil then d.enabled = spec.enabled == true end
    pushDeck(pid)
    return true
end)
exports("setRam", function(pid, value) local d = deckOf(pid); d.ram = clamp(value, 0, d.maxRam); pushDeck(pid); return d.ram end)
exports("addRam", function(pid, delta) local d = deckOf(pid); d.ram = clamp(d.ram + (tonumber(delta) or 0), 0, d.maxRam); pushDeck(pid); return d.ram end)
exports("setLoadout", function(pid, ids) local d = deckOf(pid); d.slots = type(ids) == "table" and { table.unpack(ids) } or nil; pushDeck(pid); return true end)
exports("setCooldown", function(pid, id, seconds)
    local d = deckOf(pid)
    d.cooldowns[id] = (tonumber(seconds) or 0) > 0 and now() + math.floor(seconds * 1000) or nil
    pushDeck(pid)
    return true
end)
exports("setEnabled", function(pid, on)
    local d = deckOf(pid)
    d.enabled = on ~= false
    if not d.enabled and uploadOf[pid] then cancelUpload(uploadOf[pid], "disabled") end
    pushDeck(pid)
    return true
end)

-- A result card on one player's screen: what a Ping found, a scan log, a mission hint.
-- spec = { title, subtitle?, tone? ("hostile"|"neutral"|"friendly"|"device"), icon?, seconds?,
--          fields = { { "LABEL", "value" }, ... } }   (at most 10 fields)
local function report(pid, spec)
    pid = math.tointeger(tonumber(pid))
    if not pid or type(spec) ~= "table" then return false, "invalid_report" end
    local card = { title = str(spec.title, 40) or "REPORT", subtitle = str(spec.subtitle, 60),
                   tone = TONES[spec.tone] and spec.tone or "neutral",
                   icon = type(spec.icon) == "string" and spec.icon:match("^[a-z0-9_]+$") and spec.icon or "data",
                   seconds = clamp(spec.seconds or 7, 1, 30), fields = {} }
    for i, f in ipairs(type(spec.fields) == "table" and spec.fields or {}) do
        if i > 10 then break end
        local k, v = str(tostring(f[1] or f.label or ""), 28), str(tostring(f[2] or f.value or ""), 48)
        if k and v then card.fields[#card.fields + 1] = { k, v } end
    end
    TriggerClientEvent("open77_quickhack:report", pid, card)
    return true
end
exports("report", report)
QuickhackReport = report
QuickhackResolve = function(t) return resolve(t) end
QuickhackRecordName = recordName

exports("addTarget", addTarget)
exports("updateTarget", updateTarget)
exports("removeTarget", removeTarget)
exports("setPlayerInfo", function(pid, info)
    pid = math.tointeger(tonumber(pid))
    if not pid then return false, "invalid_player" end
    playerInfo[pid] = info and sanitizeInfo(info) or nil
    return true
end)
exports("setAutoTargets", function(spec)
    for k, v in pairs(type(spec) == "table" and spec or {}) do if autoTargets[k] ~= nil or k == "player" or k == "npc" or k == "vehicle" or k == "prop" then autoTargets[k] = v == true end end
    broadcastTargets()
    return true
end)
exports("cancel", function(uidOrPlayer, reason)
    local uid = math.tointeger(tonumber(uidOrPlayer))
    if uid and uploads[uid] then return cancelUpload(uid, reason) end
    if uid and uploadOf[uid] then return cancelUpload(uploadOf[uid], reason) end
    return false
end)
exports("uploads", function()
    local list = {}
    for uid, up in pairs(uploads) do
        list[#list + 1] = { uploadId = uid, source = up.hacker, quickhack = up.def.id, target = up.target, endsInMs = up.ends - now() }
    end
    return list
end)

-- test seam (tests/server.test.lua drives the module without a host)
QuickhackServer = { resolve = resolve, offers = offers, deckOf = deckOf, sanitizeInfo = sanitizeInfo, normalizeDef = normalizeDef,
                    register = register, addTarget = addTarget, uploads = uploads, startUpload = startUpload, completeUpload = completeUpload }
