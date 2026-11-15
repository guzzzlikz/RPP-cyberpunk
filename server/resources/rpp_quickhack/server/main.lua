-- rpp_quickhack: свои действия для штатных квикхаков open77_quickhack.
-- Пресет даёт название, иконку, ОЗУ и тайминги, а что квикхак ДЕЛАЕТ — здесь
-- (onExecute = экспорт этого ресурса). Настройки: shared/config.lua.
local cfg = RppQuickhackConfig
local RESOURCE = GetCurrentResourceName()

local function log(text) print("[" .. RESOURCE .. "] " .. text) end

-- Ошибки логируем не чаще раза в 10 с на причину, чтобы не засорять консоль.
local lastLog = {}
local function warnOnce(key, text)
    local now = Open77.time.monotonic()
    if lastLog[key] and now - lastLog[key] < 10 then return end
    lastLog[key] = now
    log(text)
end

local function bucketOf(player)
    local pos = Open77.players.position(tonumber(player))
    return pos and tonumber(pos.bucket) or 0
end

-- ---------------------------------------------------------------------------
-- Урон
-- ---------------------------------------------------------------------------
local function damage(ctx, amount)
    local target = ctx.target or {}
    if target.kind == "player" then
        local ok, reason = Open77.players.damage(tonumber(target.id), amount, { cause = "script" })
        if ok ~= true then warnOnce("pdmg:" .. tostring(reason), "player damage refused: " .. tostring(reason)) end
        return ok == true
    elseif target.kind == "npc" then
        local ok, applied = pcall(Open77.npcs.applyDamage, target.id, amount, "player:" .. tostring(ctx.source), "script")
        if not ok or applied ~= true then
            warnOnce("ndmg", "npc damage refused: " .. tostring(applied))
            return false
        end
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Эффекты: на теле цели, а если не вышло — в её точке
-- ---------------------------------------------------------------------------
local function effectAt(ctx, effect)
    local p = (ctx.target or {}).position
    if not effect or not p then return end
    local ok, done, reason = pcall(Open77.effects.play, effect, {
        position = { x = p.x, y = p.y, z = (p.z or 0) + 1.0 }, bucket = bucketOf(ctx.source),
    })
    if not ok or not done then warnOnce("fx:" .. effect, ("effect %s refused: %s"):format(effect, tostring(ok and reason or done))) end
end

local function effectOn(ctx, effect, ms)
    local target = ctx.target or {}
    if not effect then return end
    if target.kind == "player" or target.kind == "npc" then
        local ok, id = pcall(Open77.effects.attach, { kind = target.kind, id = tostring(target.id) }, effect, { ttlMs = ms })
        if ok and id then return end
    end
    effectAt(ctx, effect)
end

-- ---------------------------------------------------------------------------
-- Короткое замыкание
-- ---------------------------------------------------------------------------
exports("rppShortCircuit", function(ctx)
    local c = cfg.short_circuit
    if type(ctx) ~= "table" or type(ctx.target) ~= "table" then return end
    effectAt(ctx, c.sparks)
    if ctx.target.kind == "vehicle" then
        local id = ctx.target.id
        local ok, reason = pcall(Open77.vehicles.setEngine, id, false)
        if not ok then return warnOnce("engine", "setEngine refused: " .. tostring(reason)) end
        SetTimeout(math.floor((c.engineOffSeconds or 4) * 1000), function()
            pcall(Open77.vehicles.setEngine, id, true)
        end)
        return
    end
    effectOn(ctx, c.effect, c.effectMs or 1500)
    damage(ctx, c.damage or 25)
end)

-- ---------------------------------------------------------------------------
-- Перегрев
-- ---------------------------------------------------------------------------
local burning = {} -- [kind:id] = true, пока горит (повторный перегрев не складывается)

exports("rppOverheat", function(ctx)
    local c = cfg.overheat
    if type(ctx) ~= "table" or type(ctx.target) ~= "table" then return end
    local key = tostring(ctx.target.kind) .. ":" .. tostring(ctx.target.id)
    if burning[key] then return end
    burning[key] = true
    local ticks = c.ticks or 5
    effectOn(ctx, c.effect, ticks * 1000 + 500)
    CreateThread(function()
        for _ = 1, ticks do
            if not damage(ctx, c.tickDamage or 6) then break end
            Wait(1000)
        end
        burning[key] = nil
    end)
end)

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
local HANDLERS = { short_circuit = "rppShortCircuit", overheat = "rppOverheat" }
local PRESET_KEYS = { "ram", "upload", "cooldown", "range", "label", "description" }

CreateThread(function()
    -- Экспорты отвечают, когда все ресурсы старта загрузились: пробуем несколько раз.
    for id, handler in pairs(HANDLERS) do
        local c = cfg[id]
        if c and c.enabled ~= false then
            local spec = { onExecute = handler, targets = c.targets }
            for _, k in ipairs(PRESET_KEYS) do if c[k] ~= nil then spec[k] = c[k] end end
            local done, why
            for _ = 1, 200 do
                local ok, result, reason = pcall(function() return exports.open77_quickhack:registerPreset(id, spec) end)
                if ok and result then done = true break end
                why = ok and reason or result
                Wait(50)
            end
            log(done and ("quickhack " .. id .. " registered") or ("quickhack " .. id .. " not registered: " .. tostring(why)))
        end
    end
end)
