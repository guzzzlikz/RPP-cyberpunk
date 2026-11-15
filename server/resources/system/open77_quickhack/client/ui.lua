-- open77_quickhack client/ui.lua: the NativeUI presentation.
-- client/main.lua decides; this file draws: one document (ui/quickhack.rml) bound to the "qh"
-- model, positions set in px every frame, motion through ui:animate / ui:keyframes, and the
-- small text effects the game uses (decode-in names, code rain on the frame edges).

QuickhackUi = {}
local M = QuickhackUi

local ui, alive = nil, false
local S = {
    width = 1920, height = 1080, density = 1,
    rows = {}, selected = 1, rowCount = 0,
    ramMax = 0, ramSegs = 0, ramState = nil,
    uploads = {}, decode = {}, glitchUntil = 0,
    listShown = false, panelShown = false, locked = false, scanning = false,
    codeAt = 0, alert = nil, toastUntil = 0,
}

local remeasure                         -- defined with M.measure below
local HEX = "0123456789ABCDEF"
local GLYPHS = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#$%&@/\\<>[]"

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end; return v end
local function now() return GetGameTimer() end

function M.escape(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("{{", "{ {"):gsub("}}", "} }")
    return s
end

function M.iconSrc(icon)
    if type(icon) == "string" and icon:match("^nui://") then return icon end
    if type(icon) ~= "string" or not icon:match("^[a-z0-9_]+$") then icon = "generic" end
    return "/ui/icons/" .. icon .. ".png"
end

local function randomCode(lines, width)
    local out = {}
    for l = 1, lines do
        local row = {}
        for c = 1, width do
            local i = math.random(1, #HEX)
            row[c] = HEX:sub(i, i)
            if c % 4 == 0 then row[#row + 1] = " " end
        end
        out[l] = table.concat(row)
    end
    return table.concat(out, "\n")
end

local function scramble(text, revealed)
    local out = {}
    for i = 1, #text do
        local ch = text:sub(i, i)
        if i <= revealed or ch == " " then out[i] = ch
        else local g = math.random(1, #GLYPHS); out[i] = GLYPHS:sub(g, g) end
    end
    return table.concat(out)
end

local function defaults(cfg)
    return {
        scanning = false, locked = false, menu = false, tone = "hostile", tab = "data", help = false, noRam = false,
        serial = "NC 4884 0252 5584 0415", codeLeft = "", codeRight = "",
        nameShown = "", mult = "1x", distance = "", deckName = cfg.deckName or "CYBERDECK",
        emptyText = "NO QUICKHACKS AVAILABLE", descTitle = "", descText = "", descUpload = "", descCooldown = "",
        ramText = "0/0", tabKey = "Z", abilitiesLabel = "ABILITIES:",
        keyExecute = "F", keyPrev = "1", keyNext = "3", keyHelp = "H",
        helpText = "", alertTitle = "", alertSub = "", alertPct = "", alertFoot = "", toastTag = "", toastText = "",
        tint = false, vendor = cfg.vendor or "KIROSHI", reportTitle = "", reportSub = "",
    }
end

-- ---------------------------------------------------------------------------------- lifecycle
function M.create(cfg)
    if type(Open77) ~= "table" or type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then
        return false, "nativeui_unavailable"
    end
    local handle, why = Open77.ui.create({
        document = "ui/quickhack.rml", layer = "hud", zIndex = 55, visible = true,
        models = { qh = defaults(cfg) },
    })
    if not handle then return false, why end
    ui, alive = handle, true
    ui:onEvent("error", function(_, detail) print("[open77_quickhack] ui error: " .. tostring(detail and (detail.reason or detail.message) or detail)) end)
    remeasure()
    return true
end

function M.ready() return alive end

function M.destroy()
    if ui then pcall(ui.destroy, ui) end
    ui, alive = nil, false
end

-- ui:state() crosses into the host: read it once per frame (M.tick), not per projection
function M.measure() return S.width, S.height end

remeasure = function()
    if not ui then return end
    local ok, st = pcall(ui.state, ui)
    if ok and type(st) == "table" and tonumber(st.width) and tonumber(st.width) > 0 then
        S.width, S.height = tonumber(st.width), tonumber(st.height)
        S.density = S.height / 1080
    end
end

local function dp(v) return v * S.density end
local function px(v) return math.floor(v + 0.5) .. "px" end

function M.setKeys(keys)
    if not ui then return end
    ui:merge("qh", { keyExecute = keys.execute or "F", keyPrev = keys.prev or "1", keyNext = keys.next or "3",
        keyHelp = keys.help or "H", tabKey = keys.tab or "Z",
        helpText = ("Hold %s to scan. Look at a target to read it. %s/%s or the mouse wheel picks a quickhack, %s uploads it. %s and %s switch target, %s switches DATA and HACKING.")
            :format(keys.scanner or "TAB", keys.up or "UP", keys.down or "DOWN", keys.execute or "F", keys.prev or "1", keys.next or "3", keys.tab or "Z") })
end

function M.setTint(on) if ui then pcall(ui.set, ui, "qh", "tint", on == true) end end
function M.setVendor(v) if ui then ui:set("qh", "vendor", tostring(v or ""):upper()) end end

-- colours a server can change: accent (the cyan), alert (the red), name (the yellow)
local function hex(v) return type(v) == "string" and v:match("^#%x%x%x%x%x%x$") and v:lower() or nil end
function M.setTheme(theme)
    if not ui then return false end
    theme = type(theme) == "table" and theme or {}
    local a, r, n = hex(theme.accent), hex(theme.alert), hex(theme.name)
    local rules = {}
    if a then
        rules[#rules + 1] = (".qh .label, .ht, .key span, #np-name, .ability .ab-name, .field .v { color: %s; }"):format(a)
        rules[#rules + 1] = (".key { border-color: %s; } .seg.on { background-color: %sd9; } .qh.sel { decorator: fx(chamfer 10 2 0.92 0 %s); }"):format(a, a, a)
    end
    if r then
        rules[#rules + 1] = ("#ram-title, .label, .field .k, .tiny, .mult, .dist { color: %s; } #panel-body { decorator: fx(chamfer 14 1 0.9 0 %s); }"):format(r, r)
        rules[#rules + 1] = ("#tab-data { decorator: fx(chamfer 10 1 0.9 0 %s); } .bars div { background-color: %scc; }"):format(r, r)
    end
    if n then rules[#rules + 1] = ("#p-name, .field .v.yellow, #desc .desc-title { color: %s; }"):format(n) end
    ui:stylesheet("theme", #rules > 0 and table.concat(rules, " ") or nil)
    return true
end

-- ---------------------------------------------------------------------------------- scanner open / close
function M.open(deck)
    if not ui then return end
    remeasure()
    S.scanning = true
    ui:merge("qh", { scanning = true, locked = false, menu = false, help = false, tab = "data" })
    -- the sweep line runs down the screen once
    ui:animate("#sweep", { from = { opacity = 1, y = -dp(140) }, to = { opacity = 0, y = S.height }, duration = 0.55, easing = "cubic-in" })
    ui:animate("#frame", { from = { opacity = 0, scale = 1.04 }, to = { opacity = 1, scale = 1 }, duration = 0.28, easing = "cubic-out" })
    ui:animate("#vignette", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.3, easing = "cubic-out" })
    ui:animate(".corner", { from = { opacity = 0, scale = 1.6 }, to = { opacity = 1, scale = 1 }, spring = { duration = 0.4, bounce = 0.3 }, stagger = 0.04 })
    ui:animate("#ram", { from = { opacity = 0, y = -dp(18) }, to = { opacity = 1, y = 0 }, spring = { duration = 0.42, bounce = 0.15 } })
    ui:animate("#hints", { from = { opacity = 0, y = dp(14) }, to = { opacity = 1, y = 0 }, duration = 0.3, easing = "cubic-out", delay = 0.08 })
    ui:animate("#scanner-tag", { from = { opacity = 0, x = -dp(20) }, to = { opacity = 1, x = 0 }, duration = 0.3, easing = "cubic-out" })
    -- the RAM cells light up left to right
    ui:animate("#ram-bar .seg", { from = { opacity = 0, y = -dp(8) }, to = { opacity = 1, y = 0 }, duration = 0.18, easing = "cubic-out", stagger = 0.018 })
    ui:keyframes("#ram-title", { channel = "opacity", stops = { { offset = 0, value = 0.2 }, { offset = 0.15, value = 1 },
        { offset = 0.22, value = 0.4 }, { offset = 0.3, value = 1 } }, duration = 0.6 })
    if deck then M.setRam(deck.ram, deck.maxRam, 0) end
end

function M.close()
    if not ui then return end
    S.scanning, S.locked = false, false
    ui:stop("#ring")
    S.lastPlace, S.lastDistance, S.rowSig = nil, nil, nil
    ui:animate("#list", { to = { opacity = 0, x = -dp(30) }, duration = 0.12, easing = "cubic-in" })
    ui:animate("#panel", { to = { opacity = 0, x = dp(30) }, duration = 0.12, easing = "cubic-in" })
    ui:animate("#frame", { to = { opacity = 0, scale = 1.03 }, duration = 0.16, easing = "cubic-in" })
    ui:animate("#ram", { to = { opacity = 0, y = -dp(12) }, duration = 0.14, easing = "cubic-in" })
    ui:animate("#hints", { to = { opacity = 0 }, duration = 0.12, easing = "cubic-in" })
    ui:animate("#vignette", { to = { opacity = 0 }, duration = 0.18, easing = "cubic-in" }, function()
        if not S.scanning and ui then ui:merge("qh", { scanning = false, locked = false, menu = false, help = false }) end
    end)
    S.listShown, S.panelShown = false, false
end

-- ---------------------------------------------------------------------------------- RAM
-- cells: available (on), the selected quickhack's cost carved from the top of the available
-- ones (cost), or the part of the cost the deck cannot pay (short)
function M.setRam(ram, maxRam, cost)
    if not ui then return end
    maxRam = math.max(1, math.floor(maxRam or 1))
    local whole = math.floor((ram or 0) + 1e-6)
    cost = math.floor(cost or 0)
    if maxRam ~= S.ramSegs then
        local parts = {}
        for i = 1, maxRam do parts[i] = ('<div class="seg" id="seg%d"></div>'):format(i) end
        ui:rml("#ram-bar", table.concat(parts))
        S.ramSegs, S.ramState = maxRam, {}
    end
    local state = S.ramState
    for i = 1, maxRam do
        local cls
        if i <= whole then
            cls = (cost > 0 and i > whole - cost) and "cost" or "on"
        elseif cost > 0 and i <= cost and cost > whole then
            cls = "short"
        else
            cls = "off"
        end
        if state[i] ~= cls then
            state[i] = cls
            ui:class("#seg" .. i, "on", cls == "on")
            ui:class("#seg" .. i, "cost", cls == "cost")
            ui:class("#seg" .. i, "short", cls == "short")
        end
    end
    ui:merge("qh", { ramText = ("%d/%d"):format(whole, maxRam), noRam = cost > whole })
end

-- the cells a quickhack just spent drop out, one by one, from the top
function M.spendRam(from, count)
    if not ui or count <= 0 then return end
    for i = 0, count - 1 do
        local idx = from - i
        if idx >= 1 then
            ui:keyframes("#seg" .. idx, { channel = "y", stops = { { offset = 0, value = 0 }, { offset = 0.4, value = -dp(10) }, { offset = 1, value = 0 } },
                duration = 0.35 })
            ui:keyframes("#seg" .. idx, { channel = "opacity", stops = { { offset = 0, value = 1 }, { offset = 0.2, value = 0.1 }, { offset = 0.4, value = 1 },
                { offset = 0.6, value = 0.2 }, { offset = 1, value = 1 } }, duration = 0.35 })
        end
    end
end

-- ---------------------------------------------------------------------------------- target lock
function M.lock(target)
    if not ui then return end
    S.locked = true
    S.lockName = (target.name or ""):upper()
    S.decode.name = { text = S.lockName, started = now(), duration = 420 }
    ui:merge("qh", { locked = true, tone = target.tone or "hostile", nameShown = scramble(S.lockName, 0), tab = "data" })
    ui:class("#panel", "ready", false)
    -- squares close in on the target, then the scan ring starts drawing
    ui:animate("#ret-anim", { from = { scale = 1.55, opacity = 0, rotate = 8 }, to = { scale = 1, opacity = 1, rotate = 0 }, spring = { duration = 0.38, bounce = 0.25 } })
    ui:animate("#nameplate", { from = { opacity = 0, x = -dp(16) }, to = { opacity = 1, x = 0 }, duration = 0.25, easing = "cubic-out" })
    ui:style(".ring-b", { ["trim-end"] = "0" })
    ui:keyframes("#ring", { channel = "rotate", stops = { { offset = 0, value = 0 }, { offset = 1, value = 360 } }, duration = 1.6, iterations = -1 })
    M.glitch()
end

function M.scanProgress(p)
    if not ui then return end
    ui:style(".ring-b", { ["trim-end"] = ("%.3f"):format(clamp(p, 0, 1)) })
    ui:style("#ring-fill", { opacity = p > 0 and p < 1 and "1" or "0" })
end

function M.unlock()
    if not ui then return end
    S.locked = false
    ui:stop("#ring")
    ui:animate("#ret-anim", { to = { opacity = 0, scale = 0.8 }, duration = 0.12, easing = "cubic-in" })
    ui:animate("#nameplate", { to = { opacity = 0 }, duration = 0.1, easing = "cubic-in" })
    if S.listShown then ui:animate("#list", { to = { opacity = 0, x = -dp(24) }, duration = 0.12, easing = "cubic-in" }) end
    if S.panelShown then ui:animate("#panel", { to = { opacity = 0, x = dp(24) }, duration = 0.12, easing = "cubic-in" }) end
    S.listShown, S.panelShown = false, false
    ui:merge("qh", { locked = false, menu = false })
end

function M.glitch()
    if not ui then return end
    ui:class("#np-name", "glitch", true)
    ui:class("#p-name", "glitch", true)
    ui:keyframes("#np-name", { channel = "x", stops = { { offset = 0, value = 0 }, { offset = 0.2, value = dp(4) }, { offset = 0.35, value = -dp(3) },
        { offset = 0.5, value = dp(2) }, { offset = 0.7, value = -dp(1) }, { offset = 1, value = 0 } }, duration = 0.22 })
    S.glitchUntil = now() + 220
end

-- ---------------------------------------------------------------------------------- data panel
local function threatRml(level)
    local parts = { '<div class="threat">' }
    for i = 1, 4 do parts[#parts + 1] = ('<div class="lvl%s"></div>'):format(i <= level and " on" or "") end
    parts[#parts + 1] = "</div>"
    return table.concat(parts)
end

local function starsRml(n)
    local parts = { '<div class="stars">' }
    for i = 1, 5 do parts[#parts + 1] = ('<shape type="star" sides="5" class="%s"/>'):format(i <= n and "on" or "") end
    parts[#parts + 1] = "</div>"
    return table.concat(parts)
end

local THREAT_NAMES = { [0] = "NONE", "LOW", "MEDIUM", "HIGH", "EXTREME" }

function M.showData(target, offers, catalogue, deck)
    if not ui then return end
    local info = target.info or {}
    local tone = target.tone or "hostile"
    local fields = {}
    local function field(k, v, cls)
        fields[#fields + 1] = ('<div class="field"><span class="k">%s</span><span class="v%s">%s</span></div>')
            :format(M.escape(k), cls and (" " .. cls) or "", M.escape(v))
    end
    if info.affiliation then field("AFFILIATION", info.affiliation:upper()) end
    if info.wanted then field("STATUS", info.wanted:upper(), "yellow") end
    for _, f in ipairs(info.fields or {}) do field(tostring(f[1]):upper(), tostring(f[2]):upper()) end
    local extra = {}
    if info.bounty or info.streetCred or info.stars then
        extra[#extra + 1] = '<span class="label">NCPD DATABASE</span>'
        if info.bounty then extra[#extra + 1] = ('<div class="field"><span class="k">REWARD</span><span class="v yellow">E$ %d</span></div>'):format(info.bounty) end
        if info.streetCred then extra[#extra + 1] = ('<div class="field"><span class="v green">SC %d</span></div>'):format(info.streetCred) end
        extra[#extra + 1] = '<div class="field"><span class="k">BOUNTY CLASS</span>' .. starsRml(info.stars or 0) .. '</div>'
    end
    if info.threat then
        extra[#extra + 1] = ('<div class="field"><span class="k">THREAT · %s</span>%s</div>'):format(THREAT_NAMES[info.threat] or "", threatRml(info.threat))
    end
    if info.description then
        extra[#extra + 1] = ('<div class="field"><span class="v" style="font-size: 15dp; white-space: normal; color: #b9fcff;">%s</span></div>'):format(M.escape(info.description))
    end
    -- abilities (people) or vulnerabilities (devices: the quickhacks it takes, as in the game)
    local rows, label = {}, "ABILITIES:"
    if #(info.abilities or {}) > 0 then
        for _, a in ipairs(info.abilities) do
            rows[#rows + 1] = ('<div class="ability"><div class="ab-icon"><img src="%s"/></div><span class="ab-name">%s</span></div>')
                :format(M.iconSrc(a.icon), M.escape(a.label))
        end
    else
        label = "VULNERABILITIES"
        local names = info.vulnerabilities
        if not names or #names == 0 then
            names = {}
            for _, o in ipairs(offers or {}) do names[#names + 1] = o.id end
        end
        for i, v in ipairs(names) do
            if i > 6 then break end
            local def = catalogue[v]
            rows[#rows + 1] = ('<div class="ability"><div class="ab-icon"><img src="%s"/></div><span class="ab-name">%s</span></div>')
                :format(M.iconSrc(def and def.icon or "generic"), M.escape(def and def.label or v))
        end
    end
    if #rows == 0 then label = "" end
    ui:rml("#fields", table.concat(fields))
    ui:rml("#extra", table.concat(extra))
    ui:rml("#abilities", table.concat(rows))
    ui:merge("qh", { abilitiesLabel = label, tone = tone })
    M.hackingLines(target, offers, catalogue, deck)
    if not S.panelShown then
        S.panelShown = true
        ui:animate("#panel", { from = { opacity = 0, x = dp(40) }, to = { opacity = 1, x = 0 }, spring = { duration = 0.4, bounce = 0.12 } })
        ui:keyframes("#panel-body", { channel = "opacity", stops = { { offset = 0, value = 0.3 }, { offset = 0.1, value = 1 }, { offset = 0.16, value = 0.5 },
            { offset = 0.24, value = 1 } }, duration = 0.5 })
    end
    ui:animate("#panel .field, #panel .ability", { from = { opacity = 0, x = dp(14) }, to = { opacity = 1, x = 0 }, duration = 0.22, easing = "cubic-out", stagger = 0.035, delay = 0.08 })
end

function M.hackingLines(target, offers, catalogue, deck)
    local lines = {}
    local function line(s) lines[#lines + 1] = ('<span class="hk-line">%s</span>'):format(M.escape(s)) end
    line(("> TARGET      %s"):format((target.name or ""):upper()))
    line(("> CLASS       %s"):format((target.kind or ""):upper()))
    line(("> DECK RAM    %d / %d"):format(math.floor(deck.ram or 0), deck.maxRam or 0))
    line(("> REGEN       %.1f / S"):format(deck.regen or 0))
    line("> ------------------------------")
    for _, o in ipairs(offers or {}) do
        local def = catalogue[o.id]
        if def then line(("> %-18s %2d RAM  %4.1fS"):format(def.label:upper():sub(1, 18), def.ram, def.upload)) end
    end
    ui:rml("#hack-lines", table.concat(lines))
end

function M.setTab(tab)
    if not ui then return end
    ui:set("qh", "tab", tab)
    ui:animate("#panel-body", { from = { opacity = 0.2, x = dp(8) }, to = { opacity = 1, x = 0 }, duration = 0.18, easing = "cubic-out" })
    if tab == "hacking" then
        ui:animate("#hack-lines .hk-line", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.05, stagger = 0.03 })
    end
end

function M.toggleHelp(on)
    if ui then ui:set("qh", "help", on) end
end

-- ---------------------------------------------------------------------------------- quickhack list
local STATE_TEXT = { ready = "READY", cooldown = "COOLDOWN", noram = "READY", range = "OUT OF RANGE", blocked = "BLOCKED", busy = "UPLOADING" }

local function rowRml(i, def, offer)
    local state = offer.state
    local cls = "qh"
    if state == "blocked" or state == "range" then cls = cls .. " blocked"
    elseif state == "cooldown" then cls = cls .. " cooling"
    elseif state == "noram" then cls = cls .. " poor"
    elseif state == "busy" then cls = cls .. " busy" end
    return ('<div class="%s" id="q%d"><div class="bg"></div><div class="glowbar"></div>'
        .. '<span class="label">%s</span><div class="state"><span id="qs%d">%s</span></div>'
        .. '<div class="cost"><span class="num">%d</span><div class="pip"></div></div>'
        .. '<div class="icon"><img src="%s"/><div class="stamp"></div></div><div class="cd" id="qc%d"></div><div class="flash" id="qf%d"></div></div>')
        :format(cls, i, M.escape(def.label), i, STATE_TEXT[state] or "READY", def.ram, M.iconSrc(def.icon), i, i)
end

-- the game's list bows: rows shift right the further they are from the middle
local function rowShift(i, n, selected)
    local mid = (n + 1) / 2
    local t = n > 1 and math.abs(i - mid) / math.max(1, mid - 1) or 0
    local x = t * t * dp(56)
    if i == selected then x = x + dp(14) end
    return x
end

function M.setOffers(offers, catalogue, selected, animateIn)
    if not ui then return end
    S.rows = {}
    local parts = {}
    for i, o in ipairs(offers) do
        local def = catalogue[o.id]
        if def then
            S.rows[#S.rows + 1] = { offer = o, def = def }
            parts[#parts + 1] = rowRml(#S.rows, def, o)
        end
    end
    S.rowCount = #S.rows
    S.lastPlace = nil
    ui:rml("#rows", table.concat(parts))
    ui:class("#list", "empty", S.rowCount == 0)
    ui:set("qh", "menu", true)
    S.selected = clamp(selected or 1, 1, math.max(1, S.rowCount))
    if not S.listShown then
        S.listShown = true
        ui:animate("#list", { from = { opacity = 0, x = -dp(30) }, to = { opacity = 1, x = 0 }, duration = 0.22, easing = "cubic-out" })
        ui:animate("#list-head", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.2 })
        animateIn = true
    end
    if animateIn then
        ui:animate("#rows .qh", { from = { opacity = 0, scaleY = 0.2 }, to = { opacity = 1, scaleY = 1 }, duration = 0.16, easing = "cubic-out", stagger = 0.035 })
    end
    M.select(S.selected, true)
end

function M.updateRowStates(offers)
    if not ui then return end
    for i, row in ipairs(S.rows) do
        local o = offers[row.offer.id]
        local sig = o and (o.state .. ":" .. (o.remainingS and ("%.1f"):format(o.remainingS) or ""))
        if o and sig == row.sig then row.offer = o; o = nil end
        if o then
            row.sig = sig
            row.offer = o
            ui:class("#q" .. i, "blocked", o.state == "blocked" or o.state == "range")
            ui:class("#q" .. i, "cooling", o.state == "cooldown")
            ui:class("#q" .. i, "poor", o.state == "noram")
            ui:class("#q" .. i, "busy", o.state == "busy")
            local text = STATE_TEXT[o.state] or "READY"
            if o.state == "cooldown" and o.remainingS then text = ("COOLDOWN %.1fS"):format(o.remainingS) end
            ui:text("#qs" .. i, text)
            if o.state == "cooldown" and o.cooldownFrac then
                ui:style("#qc" .. i, { width = ("%d%%"):format(math.floor(o.cooldownFrac * 100)) })
            else
                ui:style("#qc" .. i, { width = "0%" })
            end
        end
    end
end

function M.select(index, silent)
    if not ui or S.rowCount == 0 then return nil end
    index = clamp(index, 1, S.rowCount)
    local previous = S.selected
    S.selected = index
    for i = 1, S.rowCount do
        ui:class("#q" .. i, "sel", i == index)
        ui:animate("#q" .. i, { to = { x = rowShift(i, S.rowCount, index) }, spring = { duration = 0.26, bounce = 0.2 } })
    end
    if not silent or previous ~= index then
        ui:animate("#q" .. index .. " .icon", { from = { scale = 1.18 }, to = { scale = 1 }, spring = { duration = 0.3, bounce = 0.45 } })
        -- the glow bar is CSS only (.qh.sel .glowbar): a motion channel would leave its inline
        -- opacity on the row after it loses the selection
        ui:keyframes("#qf" .. index, { channel = "opacity", stops = { { offset = 0, value = 0.18 }, { offset = 1, value = 0 } }, duration = 0.18 })
    end
    local row = S.rows[index]
    if row then
        ui:merge("qh", { descTitle = row.def.label:upper(), descText = row.def.description or "",
            descUpload = ("%.1fS"):format(row.def.upload), descCooldown = ("%dS"):format(math.floor(row.def.cooldown + 0.5)) })
    end
    return row
end

function M.selected() return S.rows[S.selected], S.selected end
function M.rowCount() return S.rowCount end

-- the row that was executed flashes white and pulses
function M.flashRow(index)
    if not ui then return end
    ui:keyframes("#qf" .. index, { channel = "opacity", stops = { { offset = 0, value = 0.85 }, { offset = 1, value = 0 } }, duration = 0.32 })
    ui:animate("#q" .. index, { from = { scale = 1.04 }, to = { scale = 1 }, spring = { duration = 0.3, bounce = 0.4 } })
end

function M.shakeRow(index)
    if not ui then return end
    local base = rowShift(index, S.rowCount, S.selected)
    ui:keyframes("#q" .. index, { channel = "x", stops = { { offset = 0, value = base }, { offset = 0.2, value = base - dp(9) }, { offset = 0.4, value = base + dp(7) },
        { offset = 0.6, value = base - dp(5) }, { offset = 0.8, value = base + dp(3) }, { offset = 1, value = base } }, duration = 0.3 })
end

function M.hideList()
    if not ui or not S.listShown then return end
    S.listShown = false
    ui:animate("#list", { to = { opacity = 0, x = -dp(24) }, duration = 0.12, easing = "cubic-in" }, function()
        if ui and not S.listShown then ui:set("qh", "menu", false) end
    end)
end

-- ---------------------------------------------------------------------------------- per-frame placement
-- sx, sy in px; scale grows the reticle for close targets; head is the nameplate anchor (px)
function M.place(sx, sy, scale, hx, hy, distance, visible)
    if not ui then return end
    if not visible then
        if S.lastPlace ~= "hidden" then
            S.lastPlace = "hidden"
            ui:style("#reticle", { left = "-2000px", top = "-2000px" })
            ui:style("#nameplate", { left = "-2000px", top = "-2000px" })
        end
        return
    end
    -- the target barely moves most frames: write styles only when a pixel changed
    local key = ("%d:%d:%d:%d:%d:%d"):format(math.floor(sx), math.floor(sy), math.floor(scale * 50), math.floor(hx), math.floor(hy),
        S.listShown and S.rowCount or -1)
    local dist = distance and ("%.1f"):format(distance) or ""
    if dist ~= S.lastDistance then S.lastDistance = dist; ui:set("qh", "distance", dist) end
    if key == S.lastPlace then return end
    S.lastPlace = key
    ui:style("#reticle", { left = px(sx), top = px(sy) })
    ui:style("#ret-size", { transform = ("scale(%.3f)"):format(scale) })
    local nx = clamp(hx - dp(40), dp(20), S.width - dp(520))
    local ny = clamp(hy - dp(70), dp(150), S.height - dp(200))
    ui:style("#nameplate", { left = px(nx), top = px(ny) })
    if S.listShown then
        local listW, listH = dp(460), dp(62 + 69 * math.max(1, S.rowCount) + 120)
        local lx = clamp(sx - dp(140) * scale - listW - dp(40), dp(60), S.width - listW - dp(560))
        local ly = clamp(sy - listH / 2 + dp(40), dp(150), S.height - listH - dp(90))
        ui:style("#list", { left = px(lx), top = px(ly) })
    end
end

-- ---------------------------------------------------------------------------------- frame tick (text effects)
function M.tick()
    if not ui then return end
    local t = now()
    if S.scanning or t - (S.measuredAt or 0) > 1000 then S.measuredAt = t; remeasure() end
    local d = S.decode.name
    if d then
        local p = clamp((t - d.started) / d.duration, 0, 1)
        local shown = scramble(d.text, math.floor(p * #d.text))
        ui:set("qh", "nameShown", shown)
        if p >= 1 then S.decode.name = nil end
    end
    if S.glitchUntil > 0 and t > S.glitchUntil then
        S.glitchUntil = 0
        ui:class("#np-name", "glitch", false)
        ui:class("#p-name", "glitch", false)
    end
    if S.scanning and t - S.codeAt > 260 then
        S.codeAt = t
        ui:merge("qh", { codeLeft = randomCode(18, 8), codeRight = randomCode(18, 8) })
    end
    if S.reportUntil and S.reportUntil > 0 and t > S.reportUntil then
        S.reportUntil = 0
        local serial = S.reportSerialShown
        ui:animate("#report", { to = { opacity = 0, x = -dp(24) }, duration = 0.2, easing = "cubic-in" }, function()
            if ui and S.reportSerialShown == serial and (S.reportUntil or 0) == 0 then ui:class("#report", "on", false) end
        end)
    end
    if S.toastUntil > 0 and t > S.toastUntil then
        S.toastUntil = 0
        ui:animate("#toast", { to = { opacity = 0, y = -dp(8) }, duration = 0.2, easing = "cubic-in" }, function()
            if ui and S.toastUntil == 0 then ui:class("#toast", "on", false) end
        end)
    end
end

-- ---------------------------------------------------------------------------------- uploads over targets
function M.uploadStart(uid, def, mine)
    if not ui then return end
    local id = "u" .. uid
    local rml = ('<div class="up%s" id="%s"><div class="up-head"><div class="up-icon"><img src="%s"/></div>'
        .. '<span class="up-name">%s</span><span class="up-time" id="%st"></span></div>'
        .. '<div class="up-bar"><div class="up-fill" id="%sf"></div></div></div>')
        :format(mine and " mine" or "", id, M.iconSrc(def.icon), M.escape(def.label), id, id)
    ui:insert("#uploads", rml, "end")
    S.uploads[uid] = { id = id }
    ui:animate("#" .. id, { from = { opacity = 0, y = dp(10), scale = 0.9 }, to = { opacity = 1, y = 0, scale = 1 }, spring = { duration = 0.3, bounce = 0.3 } })
end

function M.uploadUpdate(uid, x, y, progress, remainingMs, visible)
    local up = S.uploads[uid]
    if not ui or not up then return end
    if not visible then ui:style("#" .. up.id, { left = "-2000px", top = "-2000px" }); return end
    ui:style("#" .. up.id, { left = px(x), top = px(y - dp(118)) })
    ui:style("#" .. up.id .. "f", { width = ("%.1f%%"):format(clamp(progress, 0, 1) * 100) })
    ui:text("#" .. up.id .. "t", ("%.1fS"):format(math.max(0, remainingMs or 0) / 1000))
end

function M.uploadEnd(uid, ok)
    local up = S.uploads[uid]
    if not ui or not up then return end
    S.uploads[uid] = nil
    ui:class("#" .. up.id, ok and "done" or "fail", true)
    ui:style("#" .. up.id .. "f", { width = "100%" })
    ui:keyframes("#" .. up.id, { channel = "opacity", stops = { { offset = 0, value = 1 }, { offset = 0.15, value = 0.3 }, { offset = 0.3, value = 1 },
        { offset = 0.45, value = 0.4 }, { offset = 1, value = 0 } }, duration = 0.7 })
    ui:remove("#" .. up.id, { to = { opacity = 0, y = -dp(16) }, duration = 0.2, delay = 0.6 })
end

-- ---------------------------------------------------------------------------------- the hacked player's warning
function M.alertStart(spec)
    if not ui then return end
    S.alert = spec
    ui:attr("#alert-img", "src", M.iconSrc(spec.icon))
    ui:merge("qh", { alertTitle = "QUICKHACK UPLOAD DETECTED", alertSub = (spec.label or ""):upper() .. "  //  SOURCE: " .. (spec.from or "UNKNOWN"):upper(),
        alertPct = "0%", alertFoot = "TRACING CONNECTION..." })
    ui:class("#alert", "on", true)
    ui:style("#alert-fill", { width = "0%" })
    ui:animate("#alert", { from = { opacity = 0, scaleY = 0.1 }, to = { opacity = 1, scaleY = 1 }, duration = 0.18, easing = "cubic-out" })
    ui:keyframes("#alert-title", { channel = "opacity", stops = { { offset = 0, value = 1 }, { offset = 0.5, value = 0.45 }, { offset = 1, value = 1 } },
        duration = 0.8, iterations = -1 })
    ui:keyframes("#alert", { channel = "x", stops = { { offset = 0, value = 0 }, { offset = 0.25, value = dp(6) }, { offset = 0.5, value = -dp(5) },
        { offset = 0.75, value = dp(3) }, { offset = 1, value = 0 } }, duration = 0.25 })
end

function M.alertProgress(p)
    if not ui or not S.alert then return end
    ui:style("#alert-fill", { width = ("%.1f%%"):format(clamp(p, 0, 1) * 100) })
    ui:set("qh", "alertPct", ("%d%%"):format(math.floor(clamp(p, 0, 1) * 100)))
end

function M.alertEnd(ok)
    if not ui or not S.alert then return end
    S.alert = nil
    ui:stop("#alert-title")
    ui:merge("qh", { alertFoot = ok and "SYSTEM COMPROMISED" or "UPLOAD INTERRUPTED", alertPct = ok and "100%" or "--" })
    ui:keyframes("#alert", { channel = "opacity", stops = { { offset = 0, value = 1 }, { offset = 0.1, value = 0.2 }, { offset = 0.2, value = 1 },
        { offset = 0.3, value = 0.3 }, { offset = 0.4, value = 1 }, { offset = 1, value = 0 } }, duration = 1.1 }, function()
        if ui and not S.alert then ui:class("#alert", "on", false) end
    end)
end

-- ---------------------------------------------------------------------------------- report card
function M.report(card)
    if not ui then return end
    local rows = {}
    for _, f in ipairs(card.fields or {}) do
        rows[#rows + 1] = ('<div class="rp-row"><span class="rp-k">%s</span><span class="rp-v">%s</span></div>')
            :format(M.escape(tostring(f[1]):upper()), M.escape(tostring(f[2])))
    end
    S.reportSerial = (S.reportSerial or 0) + 1
    local serial = S.reportSerial
    local seconds = tonumber(card.seconds) or 7
    ui:rml("#rp-fields", table.concat(rows))
    ui:attr("#rp-img", "src", M.iconSrc(card.icon or "data"))
    ui:merge("qh", { reportTitle = tostring(card.title or "REPORT"):upper(), reportSub = tostring(card.subtitle or "") })
    for _, tone in ipairs({ "hostile", "neutral", "friendly", "device" }) do ui:class("#report", tone, card.tone == tone) end
    ui:class("#report", "on", true)
    ui:animate("#report", { from = { opacity = 0, x = -dp(40) }, to = { opacity = 1, x = 0 }, spring = { duration = 0.35, bounce = 0.15 } })
    ui:animate("#rp-fields .rp-row", { from = { opacity = 0, x = -dp(10) }, to = { opacity = 1, x = 0 }, duration = 0.16,
        easing = "cubic-out", stagger = 0.04, delay = 0.12 })
    ui:keyframes("#rp-head", { channel = "opacity", stops = { { offset = 0, value = 0.2 }, { offset = 0.2, value = 1 }, { offset = 0.3, value = 0.4 },
        { offset = 0.45, value = 1 } }, duration = 0.5 })
    ui:animate("#rp-timer-fill", { from = { scaleX = 1 }, to = { scaleX = 0 }, duration = seconds, easing = "linear-in-out" })
    S.reportUntil = now() + math.floor(seconds * 1000)
    S.reportSerialShown = serial
end

-- ---------------------------------------------------------------------------------- toast
function M.toast(tag, text, bad, seconds)
    if not ui then return end
    ui:merge("qh", { toastTag = tag, toastText = text })
    ui:class("#toast", "bad", bad == true)
    ui:class("#toast", "on", true)
    ui:animate("#toast", { from = { opacity = 0, y = dp(8), scaleX = 0.6 }, to = { opacity = 1, y = 0, scaleX = 1 }, duration = 0.18, easing = "cubic-out" })
    S.toastUntil = now() + math.floor((seconds or 1.8) * 1000)
end

-- Slow-call log: any UI entry point that takes more than 4 ms is printed (client log), so a
-- regression in what a frame costs shows up without a profiler.
do
    local slow = { "showData", "setOffers", "updateRowStates", "place", "tick", "setRam", "select", "lock", "open", "close", "report",
                   "uploadUpdate", "alertProgress" }
    for _, name in ipairs(slow) do
        local fn = M[name]
        M[name] = function(...)
            local clock = Open77.time and (Open77.time.precise or Open77.time.monotonic)
            local t0 = clock and clock() or nil
            local a, b, c = fn(...)
            if t0 then
                local ms = (clock() - t0) * 1000
                if ms > 4 then print(("[open77_quickhack] slow ui.%s %.1f ms"):format(name, ms)) end
            end
            return a, b, c
        end
    end
end

return M
