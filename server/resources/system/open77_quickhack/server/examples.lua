-- open77_quickhack: the bundled EXAMPLE quickhacks. One "Ping" per kind of target: a player, a
-- network NPC, a vehicle and a device (a point or a prop). Each one reports, on the hacker's screen,
-- what the server knows about the target.
--
-- They exist to be read and copied. Your own resource builds a quickhack the same way, through
-- the exports, with `exports.open77_quickhack:register` in place of `QuickhackRegister`:
--   1. register a definition (label, icon, RAM, upload, cooldown, which target kinds);
--   2. point `onExecute` at an export of YOUR resource;
--   3. in that export, do the effect. Here the effect is a report card (exports.open77_quickhack:report).
-- Turn them off with `examples = false` in shared/config.lua, or at run time with
-- exports.open77_quickhack:setExamplesEnabled(false).

local cfg = QuickhackConfig
local EXAMPLES = {
    { id = "ping_player", targets = { "player" }, ram = 1, upload = 1.0, cooldown = 4,
      description = "Example quickhack: reports what the server knows about this player. "
          .. "The target sees the upload warning." },
    { id = "ping_npc", targets = { "npc" }, ram = 1, upload = 0.8, cooldown = 3,
      description = "Example quickhack: reports the NPC's record, owner, health and who simulates it." },
    { id = "ping_vehicle", targets = { "vehicle" }, ram = 1, upload = 0.8, cooldown = 3,
      description = "Example quickhack: reports the vehicle's model, health, speed, lock and occupants." },
    { id = "ping_device", targets = { "point", "prop" }, ram = 1, upload = 0.6, cooldown = 2,
      description = "Example quickhack: reports the device's id, owner resource and position." },
}

local function fmt(n, digits) return n and string.format("%." .. (digits or 1) .. "f", n) or "-" end
local function distance(a, b)
    if not (a and b) then return nil end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function where(p) return p and ("%s, %s, %s"):format(fmt(p.x), fmt(p.y), fmt(p.z)) or "-" end

-- What each kind of target can tell. `t` is the server's resolved target (position, name, snapshot).
local REPORTERS = {
    player = function(t, hacker)
        local read = Open77.players.get(t.id) or {}
        local seat = Open77.vehicles and Open77.vehicles.getPlayerSeat and Open77.vehicles.getPlayerSeat(t.id)
        return "ИГРОК", {
            { "ИМЯ", t.name or "-" },
            { "ID ИГРОКА", tostring(t.id) },
            { "СКОРОСТЬ", read.speed and (fmt(read.speed * 3.6, 0) .. " KM/H") or "-" },
            { "НАПРАВЛЕНИЕ", read.heading and (fmt(read.heading, 0) .. "°") or "-" },
            { "В ТРАНСПОРТЕ", type(seat) == "table" and ("#" .. tostring(seat.vehicleId or seat.id or "?")) or "НЕТ" },
            { "ИЗМЕРЕНИЕ", tostring(t.bucket or 0) },
            { "РАССТОЯНИЕ", fmt(distance(hacker, t.position)) .. " M" },
        }
    end,
    npc = function(t, hacker)
        local s = t.snapshot or {}
        return "NPC", {
            { "ЗАПИСЬ", tostring(s.record or s.template or "-") },
            { "ВЛАДЕЛЕЦ", tostring(s.resource or "-") },
            { "ЗДОРОВЬЕ", s.health and (fmt(s.health, 0) .. " / " .. fmt(s.maxHealth, 0)) or "-" },
            { "СИМУЛИРУЕТ", s.authorityPlayerId and s.authorityPlayerId ~= 0 and ("ИГРОК " .. s.authorityPlayerId) or "СЕРВЕР" },
            { "ID NPC", tostring(t.id) },
            { "РАССТОЯНИЕ", fmt(distance(hacker, t.position)) .. " M" },
        }
    end,
    vehicle = function(t, hacker)
        local s = t.snapshot or {}
        local occupants = {}
        for _, o in ipairs(type(s.occupants) == "table" and s.occupants or {}) do
            occupants[#occupants + 1] = Open77.players.name(o.playerId) or ("#" .. tostring(o.playerId))
        end
        return "ТРАНСПОРТ", {
            { "МОДЕЛЬ", QuickhackRecordName(s.record, "-") },
            { "ID ТРАНСПОРТА", tostring(t.id) },
            { "ЗДОРОВЬЕ", s.health and (fmt((s.health <= 1 and s.health * 100 or s.health), 0) .. " %") or "-" },
            { "СКОРОСТЬ", s.speedKph and (fmt(s.speedKph, 0) .. " KM/H") or "-" },
            { "ЗАПЕРТ", s.locked and "ДА" or "НЕТ" },
            { "ПАССАЖИРЫ", #occupants > 0 and table.concat(occupants, ", ") or "НЕТ" },
            { "ВЛАДЕЛЕЦ", tostring(s.resource or "-") },
            { "РАССТОЯНИЕ", fmt(distance(hacker, t.position)) .. " M" },
        }
    end,
    device = function(t, hacker)
        return "УСТРОЙСТВО", {
            { "ИМЯ", t.name or "-" },
            { "ID", tostring(t.id) },
            { "ТИП", t.kind:upper() },
            { "ПОЗИЦИЯ", where(t.position) },
            { "СКРИПТЫ", t.quickhacks and tostring(#t.quickhacks) or "ВСЕ" },
            { "РАССТОЯНИЕ", fmt(distance(hacker, t.position)) .. " M" },
        }
    end,
}

-- The effect of every example: read the target again (it may have moved) and send a report card.
exports("qhExamplePing", function(ctx)
    local target = QuickhackResolve({ kind = ctx.target.kind, id = ctx.target.id })
    if not target then return end
    local hacker = Open77.players.position(ctx.source)
    local reporter = REPORTERS[target.kind] or REPORTERS.device
    local label, fields = reporter(target, hacker)
    QuickhackReport(ctx.source, {
        title = "ПИНГ // " .. label, subtitle = (target.name or ""):upper(), icon = "ping",
        tone = target.tone, fields = fields, seconds = 8,
    })
end)

local enabled = false
local function setEnabled(on)
    on = on ~= false
    if on == enabled then return true end
    enabled = on
    for _, ex in ipairs(EXAMPLES) do
        if on then
            QuickhackRegister({ id = ex.id, label = "Пинг", icon = "ping", category = "covert", ram = ex.ram,
                upload = ex.upload, cooldown = ex.cooldown, targets = ex.targets, range = 50,
                description = ex.description, impactSound = "quickhack_ping", onExecute = "qhExamplePing" })
        else
            QuickhackRemove(ex.id)
        end
    end
    return true
end

exports("setExamplesEnabled", setEnabled)
if cfg.examples ~= false then setEnabled(true) end
