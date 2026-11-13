-- The pause menu on NativeUI (ui/pause.rml). client/main.lua keeps the whole controller
-- (session, settings bridge, voice, key mappings, map providers) and talks to this module
-- with the page API the WebUI page had: menu:on(name, fn), menu:send(name, payload),
-- menu:show(), menu:hide(), menu:setFocus(keyboard, cursor), menu:setConsumedKeys().
-- Everything the page's script did (focus, confirmations, the settings rows, the option
-- sheet, key capture, the filter, address privacy, branding) lives here.
PauseUi = {}
local U = PauseUi

local DEFAULT_ACCENT = "#22D8E2"
local PANEL_MAIN, PANEL_SETTINGS = 620, 1340
local SUPPORTED = { int = true, bool = true, list = true, keybind = true, meter = true, info = true }
local CONFIRMATIONS = {
    ["quit-session"] = { title = "confirm.quitSessionTitle", body = "confirm.quitSessionBody", icon = "quit-session" },
    ["quit-game"] = { title = "confirm.quitGameTitle", body = "confirm.quitGameBody", icon = "quit-game" },
}
local ITEMS = {
    { id = "resume", label = "menu.resume", icon = "resume", key = true },
    { id = "map", label = "menu.map", icon = "map" },
    { id = "settings", label = "menu.settings", icon = "settings" },
    { rule = true },
    { id = "quit-session", label = "menu.quitSession", icon = "quit-session", danger = true },
    { id = "quit-game", label = "menu.quitGame", icon = "quit-game", danger = true },
}

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function esc(s)
    return (tostring(s == nil and "" or s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
local function icon(name, class) return PauseIcons.rml(name, class) end

--- Upper case with accents: RCSS text-transform only changes ASCII letters, and the engine
--- hands localised words ("Fenêtré", "Désactivé") that must read FENÊTRÉ, not FENêTRé.
local function upper(s)
    s = tostring(s or "")
    return (s:upper():gsub("\195([\160-\190])", function(c)
        local b = c:byte()
        if b == 0xB7 then return nil end -- the division sign has no capital
        return "\195" .. string.char(b - 0x20)
    end):gsub("\197\147", "\197\146"):gsub("\197\147", "\197\146"))
end
U.upper = upper

-- ---- strings -------------------------------------------------------------------------
local strings = PauseStrings or {}
local function T(path, fallback)
    local node = strings
    for part in tostring(path):gmatch("[^.]+") do node = type(node) == "table" and node[part] or nil end
    if type(node) == "string" then return node end
    return fallback or path
end
local function F(path, values)
    return (T(path):gsub("{(%w+)}", function(key)
        local v = values and values[key]
        if v == nil then return "{" .. key .. "}" end
        return tostring(v)
    end))
end
U.T, U.F = T, F

-- ---- address privacy (display only: payloads and values keep their originals) ----------
local function ipv4(host)
    local a, b, c, d = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    return a and #a <= 3 and #b <= 3 and #c <= 3 and #d <= 3 and
        tonumber(a) <= 255 and tonumber(b) <= 255 and tonumber(c) <= 255 and tonumber(d) <= 255
end
local function ipv6(host)
    host = host:gsub("%%[%w_.%-]+$", "")
    local tail = host:match("([%d.]+)$")
    if host:find(".", 1, true) then
        if not tail or not ipv4(tail) then return false end
        host = host:sub(1, #host - #tail) .. "0:0"
    end
    if host:find("[^%x:]") or host:find(":::", 1, true) then return false end
    local compressed = host:find("::", 1, true)
    if compressed and host:find("::", compressed + 2, true) then return false end
    if (host:sub(1, 1) == ":" and host:sub(1, 2) ~= "::") or (host:sub(-1) == ":" and host:sub(-2) ~= "::") then return false end
    local count = 0
    for part in host:gmatch("[^:]+") do
        if #part > 4 then return false end
        count = count + 1
    end
    return compressed and count < 8 or not compressed and count == 8
end
local Privacy = { visible = false, known = {} }
function Privacy.remember(payload)
    if type(payload) ~= "table" then return end
    for key, value in pairs(payload) do
        if type(value) == "table" then Privacy.remember(value)
        elseif type(value) == "string" and ({ endpoint = true, serveraddress = true, ipaddress = true, resourcebaseurl = true })[tostring(key):lower()] then
            local authority = value:lower():gsub("^%s+", ""):gsub("^%a[%w+.-]*://", ""):match("^[^/%s?#]+")
            if authority then
                authority = authority:gsub("^.*@", "")
                local host = authority:match("^%[([^%]]+)%]") or authority:gsub(":%d+$", "")
                Privacy.known[authority], Privacy.known[host] = true, true
            end
        end
    end
end
function Privacy.text(value)
    value = tostring(value or "")
    if value == "" or Privacy.visible then return value end
    local hidden = T("session.addressHidden")
    value = value:gsub("%[([^%]]+)%]:?%d*", function(host) if ipv6(host) then return hidden end return nil end)
    return (value:gsub("[%w_%.:%%%-]+", function(token)
        local candidate = token:gsub("%.$", "")
        local suffix = token:sub(#candidate + 1)
        local host, port = candidate:match("^(.-):(%d+)$")
        local lower = candidate:lower()
        local hostname = host and host:lower() or lower
        local address = ipv6(candidate) or ipv4(candidate) or
            host and #port <= 5 and (ipv4(host) or host:match("^[%w][%w.%-]*%.[%a][%w%-]*$")) or
            hostname == "localhost" and (not port or #port <= 5) or
            Privacy.known[lower] or Privacy.known[hostname]
        return address and hidden .. suffix or token
    end))
end
U.Privacy = Privacy

-- ---- settings rows -------------------------------------------------------------------
local function labelFor(entry)
    if entry.label and entry.label ~= "" then return tostring(entry.label) end
    return (tostring(entry.name):gsub("(%l)(%u)", "%1 %2"):gsub("_", " "))
end
U.labelFor = labelFor

--- A Float setting travels as a fixed-point int; `scale` is the divisor (display only).
function U.formatValue(entry, raw)
    local scale = tonumber(entry.scale) or 1
    local suffix = tostring(entry.suffix or "")
    raw = tonumber(raw) or 0
    if scale <= 1 then return tostring(math.floor(raw + 0.5)) .. suffix end
    return string.format(scale >= 100 and "%.2f" or "%.1f", raw / scale) .. suffix
end

--- Some engine choices are untranslated tokens ("UI-Settings-...-Off"): show the readable tail.
function U.optionText(value)
    local text = tostring(value or T("settings.blank"))
    local tail = text:match("^UI%-Settings%-.+%-([^%-]+)$")
    if tail then
        if tail == "Off" then return T("settings.off") end
        if tail == "On" then return T("settings.on") end
        return (tail:gsub("(%l)(%u)", "%1 %2"):gsub("_", " "))
    end
    return text
end

--- At most two tags: the engine's own answer to "I changed it and nothing happened".
function U.tagsFor(entry)
    local tags = {}
    if entry.type == "list" and #(entry.options or {}) < 2 then tags[#tags + 1] = { "unavailable", "quiet" } end
    if entry.disabled then tags[#tags + 1] = { "locked", "quiet" } end
    if entry.policy == "restart" then tags[#tags + 1] = { "restart", "warn" } end
    if entry.policy == "checkpoint" then tags[#tags + 1] = { "checkpoint", "warn" } end
    if entry.inGame == false then tags[#tags + 1] = { "menuOnly", "warn" } end
    if entry.visible == false then tags[#tags + 1] = { "hidden", "quiet" } end
    return { tags[1], tags[2] }
end

--- The rows a payload's sections render, filtered by a query (label or variable name).
function U.rows(sections, query)
    local out = {}
    query = tostring(query or ""):lower():match("^%s*(.-)%s*$")
    for _, section in ipairs(sections or {}) do
        for _, entry in ipairs(section.entries or {}) do
            if type(entry) == "table" and SUPPORTED[entry.type] then
                local hay = (labelFor(entry) .. " " .. tostring(entry.name)):lower()
                if query == "" or hay:find(query, 1, true) then
                    out[#out + 1] = { group = section.group, title = section.title, entry = entry,
                                      key = tostring(section.group) .. "|" .. tostring(entry.name) }
                end
            end
        end
    end
    return out
end

local function editable(entry)
    if entry.disabled then return false end
    return entry.type == "int" or entry.type == "bool" or entry.type == "keybind" or
        (entry.type == "list" and #(entry.options or {}) > 1)
end
U.editable = editable

local function ratio(entry, value)
    local lo, hi = tonumber(entry.min) or 0, tonumber(entry.max) or 100
    return hi > lo and clamp(((tonumber(value) or 0) - lo) / (hi - lo), 0, 1) or 0
end

--- One row's RML (`i` is its index in the rendered list: ids r<i>, in<i>).
function U.rowRml(row, i, state)
    local e = row.entry
    local classes = "srow nav-item" .. (e.sub and " sub" or "") .. (e.disabled and " locked" or "")
    local tags = {}
    for _, tag in ipairs(U.tagsFor(e)) do
        tags[#tags + 1] = ('<span class="tag %s">%s</span>'):format(tag[2] == "warn" and "warn" or "", esc(T("tag." .. tag[1])))
    end
    local ctl
    if e.type == "int" then
        local lo, hi, step = tonumber(e.min) or 0, tonumber(e.max) or 100, math.max(1, tonumber(e.step) or 1)
        local pct = math.floor(ratio(e, e.value) * 1000 + 0.5) / 10
        ctl = ('<div class="slider"><div class="well"></div><div class="fill" style="width: %s%%;"></div>'
            .. '<input id="in%d" type="range" min="%s" max="%s" step="%s" value="%s"%s/></div><span class="readout">%s</span>')
            :format(pct, i, lo, hi, step, tonumber(e.value) or lo, e.disabled and ' disabled=""' or "", esc(U.formatValue(e, e.value)))
    elseif e.type == "bool" then
        local on = tonumber(e.value) == 1
        ctl = ('<div id="c%d-toggle" class="tgl act%s"><span class="word">%s</span><div class="well"><div class="knob"></div></div></div>')
            :format(i, on and " on" or "", esc(T(on and "settings.on" or "settings.off")))
    elseif e.type == "list" then
        local options = e.options or {}
        local index = clamp(math.floor(tonumber(e.value) or 0), 0, math.max(0, #options - 1))
        local locked = e.disabled or #options < 2
        ctl = ('<div class="lst"><div id="c%d-prev" class="step act%s">%s</div><div id="c%d-open" class="val act%s"><span class="txt">%s</span>%s</div>'
            .. '<div id="c%d-next" class="step act%s">%s</div></div>')
            :format(i, (locked or index <= 0) and " off" or "", icon("chev-left"),
                i, locked and " off" or "", esc(upper(#options > 0 and U.optionText(options[index + 1]) or T("settings.blank"))), icon("chev-down"),
                i, (locked or index >= #options - 1) and " off" or "", icon("chev-right"))
    elseif e.type == "keybind" then
        local capture = state and state.capture == row.key
        local key = capture and T("keybind.press") or (tostring(e.value or "") ~= "" and tostring(e.value) or T("settings.blank"))
        local reset = ""
        if e.default ~= nil then
            reset = ('<div id="c%d-reset" class="reset act%s">%s</div>'):format(i, e.rebound == true and "" or " off", icon("reset"))
        end
        ctl = ('<div class="kb">%s<div id="c%d-capture" class="key act%s">%s</div></div>'):format(reset, i, capture and " capture" or "", esc(key))
    elseif e.type == "meter" then
        local pct = clamp(tonumber(e.value) or 0, 0, 100)
        local thr = e.threshold and ('<div class="thr" style="left: %d%%;"></div>'):format(clamp(math.floor(tonumber(e.threshold) or 0), 0, 100)) or ""
        ctl = ('<div class="mtr"><div class="fill" style="width: %d%%;"></div>%s</div><span class="readout">%s</span>')
            :format(math.floor(pct), thr, esc(math.floor(pct) .. tostring(e.suffix or "")))
        classes = classes:gsub(" nav%-item", "")
    else -- info
        ctl = ('<span class="info">%s</span>'):format(esc(Privacy.text(e.value ~= nil and tostring(e.value) or T("settings.blank"))))
        classes = classes:gsub(" nav%-item", "")
    end
    return ('<div id="r%d" class="%s" data-nav="r%d"><div class="lbl"><span class="name">%s</span>'
        .. '<div class="tags">%s</div></div><div class="ctl">%s</div></div>')
        :format(i, classes, i, esc(labelFor(e)), table.concat(tags), ctl)
end

-- ---- key capture names ------------------------------------------------------------------
local KEY_NAMES = {
    space = "SPACE", enter = "ENTER", tab = "TAB", shift = "SHIFT", control = "CTRL", alt = "ALT",
    backspace = "BACKSPACE", insert = "INSERT", delete = "DELETE", home = "HOME", ["end"] = "END",
    pageup = "PAGEUP", pagedown = "PAGEDOWN", up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
    add = "NUMPADPLUS", subtract = "NUMPADMINUS", multiply = "NUMPADMULTIPLY", divide = "NUMPADDIVIDE",
    decimal = "NUMPADDECIMAL", semicolon = ";", equals = "=", comma = ",", minus = "-", period = ".",
    slash = "/", backquote = "`", bracketleft = "[", backslash = "\\", bracketright = "]", quote = "'",
}
--- A NativeUI key name ('a', 'f5', 'numpad3', 'space'...) as a key-mapping name ('A', 'F5', 'NUMPAD3').
function U.bindingName(key)
    key = tostring(key or "")
    if key:match("^[a-z]$") or key:match("^[0-9]$") then return key:upper() end
    local f = tonumber(key:match("^f(%d%d?)$"))
    if f and f >= 1 and f <= 12 then return "F" .. f end
    local pad = key:match("^numpad(%d)$")
    if pad then return "NUMPAD" .. pad end
    return KEY_NAMES[key]
end
local MOUSE_NAMES = { [0] = "MOUSE1", [1] = "MOUSE2", [2] = "MOUSE3", [3] = "MOUSE4", [4] = "MOUSE5" }
-- Punctuation keys are named by the character the player's layout gives them (the key
-- registry resolves a character to its key on the active layout: AZERTY's ")" key is
-- not US ";"), which arrives as the textinput that follows the keydown.
local LAYOUT_KEYS = { semicolon = true, equals = true, comma = true, minus = true, period = true, slash = true,
                      backquote = true, bracketleft = true, backslash = true, bracketright = true, quote = true,
                      intlbackslash = true }
U.LAYOUT_KEYS = LAYOUT_KEYS

-- ---- accent theme ---------------------------------------------------------------------
local function mix(hex, target, amount)
    local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
    local function m(v) return math.floor(v + (target - v) * amount + 0.5) end
    return ("#%02x%02x%02x"):format(m(r), m(g), m(b))
end
local ACCENT_RCSS = [[
#aura { decorator: radial-gradient(circle at 0% 22%, {a}30 0%, {a}0c 34%, {a}00 64%); }
#panel-edge { decorator: linear-gradient(90deg, {a} 0%, {a}99 38%, {a}00 86%); box-shadow: {a}55 0 0 18dp 0; }
#panel-spine { decorator: linear-gradient(180deg, {a}00 0%, {a}70 24%, {a}24 70%, {a}00 100%); }
.mark { color: {a}; }
#chip { color: {a}; decorator: fx(chamfer 6 1 0.01 0 {a}88); }
#chip-dot { background-color: {a}; box-shadow: {a} 0 0 8dp 0; }
#session { decorator: fx(chamfer 16 1 0.01 0 #8a94a240); }
.cell-v b { color: {a}; }
#privacy.focus #privacy-box { border-color: {a}; }
#root.addresses #privacy-tick { background-color: {a}; box-shadow: {a} 0 0 6dp 0; }
.item .hl { decorator: linear-gradient(90deg, {a}2a 0%, {a}0c 62%, {a}00 100%); }
.item .bar { background-color: {a}; box-shadow: {a} 0 0 12dp 0; }
.item.focus { color: {a2}; }
.item.focus path.ic { stroke: {a}; }
.item.focus .kbd { color: {a}; decorator: fx(chamfer 5 1 0.01 0 {a}aa); }
.btn.focus { color: {a2}; decorator: fx(chamfer 7 1 0.4 8 {a}); }
#back.focus, #vanilla.focus { color: {a2}; decorator: fx(chamfer 7 1 0.3 6 {a}); }
#back.focus path.ic, #vanilla.focus path.ic { stroke: {a}; }
.tab .hl { decorator: linear-gradient(90deg, {a}26 0%, {a}0a 70%, {a}00 100%); }
.tab .bar { background-color: {a}; box-shadow: {a} 0 0 10dp 0; }
.tab.active { color: {a}; }
.tab.active path.ic { stroke: {a}; }
#filter-wrap.focus { border-color: {a}; box-shadow: {a}3a 0 0 16dp 0; }
#filter-wrap.focus #filter-icon path.ic { stroke: {a}; }
.srow.focus { decorator: linear-gradient(90deg, {a}1a 0%, {a}07 70%, {a}00 100%); border-left-color: {a}; }
.slider .fill { background-color: {a}; box-shadow: {a}99 0 0 10dp 0; }
.slider input.range sliderbar { background-color: {a2}; box-shadow: {a}cc 0 0 10dp 0; }
.srow.locked .slider .fill { background-color: #5a6472; box-shadow: none; }
.readout { color: {a}; }
.tgl.on { color: {a}; }
.tgl.on .well { decorator: fx(chamfer 5 1 0.6 0 {a}); }
.tgl.on .knob { background-color: {a}; box-shadow: {a}b3 0 0 12dp 0; }
.lst .val path.ic { stroke: {a}; }
.srow.focus .lst .val, .lst .val:hover { decorator: fx(chamfer 6 1 0.6 6 {a}); }
.lst .step:hover { decorator: fx(chamfer 6 1 0.5 0 {a}); }
.lst .step:hover path.ic { stroke: {a2}; }
.lst .step.off:hover { decorator: fx(chamfer 6 1 0.5 0 #8a94a257); }
.srow.focus .kb .key, .kb .key:hover { decorator: fx(chamfer 6 1 0.6 6 {a}); }
.kb .key.capture { color: {a}; decorator: fx(chamfer 6 1 0.6 12 {a}); }
.kb .reset:hover { decorator: fx(chamfer 6 1 0.5 0 #ffb020); }
.kb .reset:hover path.ic { stroke: #ffb020; }
.mtr .fill { background-color: {a}; box-shadow: {a} 0 0 10dp 0; }
#sheet { border-top-width: 2dp; border-top-color: {a}; }
.opt .hl { decorator: linear-gradient(90deg, {a}26 0%, {a}0a 100%); }
.opt .bar { background-color: {a}; }
.opt.current { color: {a}; }
.opt path.ic { stroke: {a}; }
.empty .mark { color: {a}; }
scrollbarvertical sliderbar:hover { background-color: {a}; }
]]
function U.theme(accent)
    accent = type(accent) == "string" and accent:match("^#%x%x%x%x%x%x$") and accent:lower() or DEFAULT_ACCENT:lower()
    return (ACCENT_RCSS:gsub("{a2}", mix(accent, 255, 0.2)):gsub("{a}", accent)), accent
end

-- ---------------------------------------------------------------------------------------
--- The menu surface with the page API client/main.lua uses.
function U.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    local ui, why = Open77.ui.create({ document = "ui/pause.rml", layer = "system", zIndex = 900, visible = false })
    if not ui then return nil, why end
    local page = { handlers = {} }
    local alive = true

    -- what is on screen
    local S = {
        open = false, generation = 0, page = "main", pending = nil,
        state = {}, tabs = {}, tab = nil, sections = {}, done = true,
        rows = {}, filter = "", focus = nil, zone = "content",
        sheet = nil, capture = nil, accent = DEFAULT_ACCENT, logo = "", note = "",
    }

    local function emit(name, payload)
        local fn = page.handlers[name]
        if fn then fn(payload or {}) end
    end

    -- ---- focus ------------------------------------------------------------------------
    local function navList()
        if S.page == "confirm" then return { "confirm-no", "confirm-yes" } end
        if S.page == "main" then
            local list = { "privacy" }
            for _, item in ipairs(ITEMS) do
                if item.id and not (item.id == "quit-session" and not S.state.connected) then list[#list + 1] = item.id end
            end
            return list
        end
        if S.zone == "rail" then
            local list = { "back" }
            for _, tab in ipairs(S.tabs) do if tab.enabled ~= false then list[#list + 1] = "tab-" .. tab.id end end
            list[#list + 1] = "vanilla"
            return list
        end
        local list = { "filter-wrap" }
        for i, row in ipairs(S.rows) do if editable(row.entry) then list[#list + 1] = "r" .. i end end
        return list
    end

    local function setFocus(id, reveal)
        if S.focus == id then return end
        if S.focus then ui:class("#" .. S.focus, "focus", false) end
        S.focus = id
        if not id then return end
        ui:class("#" .. id, "focus", true)
        if id == "filter-wrap" then ui:focusElement("#filter") else ui:focusElement("#root") end
        if reveal and id:match("^r%d+$") then ui:scrollTo("#" .. id, "nearest", true) end
    end

    local function moveFocus(delta, toEdge)
        local list = navList()
        if #list == 0 then return end
        local index = 0
        for i, id in ipairs(list) do if id == S.focus then index = i end end
        local target
        if toEdge == "first" then target = 1
        elseif toEdge == "last" then target = #list
        elseif index == 0 then target = delta > 0 and 1 or #list
        else target = clamp(index + delta, 1, #list) end
        setFocus(list[target], true)
    end

    -- ---- static labels ------------------------------------------------------------------
    local function legend()
        local parts = {}
        local function leg(key, label, isIcon)
            parts[#parts + 1] = ('<div class="leg"><span class="kbd%s">%s</span><span>%s</span></div>')
                :format(isIcon and " icon" or "", key, esc(label))
        end
        leg(esc(T("legend.escape")), S.page == "settings" and T("settings.back") or T("legend.close"))
        leg(icon("up") .. icon("down"), T("legend.navigate"), true)
        if S.page == "settings" then leg(icon("chev-left") .. icon("chev-right"), T("legend.adjust"), true) end
        leg(esc(T("legend.enter")), T("legend.select"))
        if S.page == "settings" then leg("TAB", T("settings.categories")) end
        ui:rml("#foot", table.concat(parts))
    end

    local function renderItems()
        local out = {}
        for _, item in ipairs(ITEMS) do
            if item.rule then out[#out + 1] = '<div class="rule"></div>'
            else
                local disabled = item.id == "quit-session" and not S.state.connected
                out[#out + 1] = ('<div id="%s" class="item nav-item%s%s" data-nav="%s"><div class="hl"></div><div class="bar"></div>%s<span class="lbl">%s</span>%s</div>')
                    :format(item.id, item.danger and " danger" or "", disabled and " disabled" or "", item.id, icon(item.icon),
                        esc(T(item.label)), item.key and ('<span class="kbd">%s</span>'):format(esc(T("legend.escape"))) or "")
            end
        end
        ui:rml("#items", table.concat(out))
        if S.focus then ui:class("#" .. S.focus, "focus", true) end
    end

    local function renderTabs()
        local out = {}
        for _, tab in ipairs(S.tabs) do
            out[#out + 1] = ('<div id="tab-%s" class="tab nav-item%s%s" data-nav="tab-%s"><div class="hl"></div><div class="bar"></div>%s<span>%s</span></div>')
                :format(tab.id, tab.id == S.tab and " active" or "", tab.enabled == false and " disabled" or "", tab.id,
                    icon(tab.id), esc(T("tabs." .. tab.id, tostring(tab.id):upper())))
        end
        ui:rml("#tabs", table.concat(out))
        if S.focus then ui:class("#" .. S.focus, "focus", true) end
    end

    local function paintStatic()
        ui:text("#chip-text", T("chip"):upper())
        ui:text("#session-label", T("session.eyebrow"))
        ui:text("#privacy-text", T("session.showAddresses"))
        ui:text("#session-hint", T("session.hint"))
        ui:rml("#confirm-icon", icon("quit-game"))
        ui:text("#confirm-kicker", T("confirm.yes"))
        ui:text("#confirm-no-text", T("confirm.no"))
        ui:text("#confirm-no-key", T("legend.escape"))
        ui:text("#confirm-yes-text", T("confirm.yes"))
        ui:rml("#back", icon("back") .. "<span>" .. esc(T("settings.back")) .. '</span><span class="grow"></span><span class="kbd">' .. esc(T("legend.escape")) .. "</span>")
        ui:text("#rail-label", T("settings.categories"))
        ui:rml("#vanilla", icon("external") .. "<span>" .. esc(T("settings.vanilla")) .. "</span>")
        ui:text("#vanilla-hint", T("settings.vanillaHint"))
        ui:text("#content-kicker-text", T("settings.title"))
        ui:rml("#filter-icon", icon("search"))
        ui:rml("#filter-clear", icon("x"))
        ui:text("#filter-placeholder", T("settings.filterPlaceholder"))
        ui:text("#sheet-kicker-text", T("settings.find"))
        renderItems()
        renderTabs()
        legend()
    end

    -- ---- session card -------------------------------------------------------------------
    local function cell(label, value, wide)
        return ('<div class="cell%s"><span class="cell-k">%s</span><span class="cell-v">%s</span></div>')
            :format(wide and " wide" or "", esc(label), value)
    end
    local function renderState()
        local state = S.state
        local client = state.client or {}
        local blank = T("session.blank")
        local proto = ("p%s.%s"):format(client.protocolMajor ~= nil and client.protocolMajor or "?", client.protocolMinor ~= nil and client.protocolMinor or "?")
        local clientCell = ("<b>%s</b> <span class=\"u\">· %s</span>"):format(esc(client.version or blank), esc(proto))
        local phase = tostring(state.phase or "offline")
        if state.connected then
            ui:text("#session-name", Privacy.text(state.server or state.endpoint or T("session.connected")))
            ui:setClasses("#pill", "live")
            ui:text("#pill-text", T("session.live"))
            local rows = {}
            rows[#rows + 1] = cell(T("session.player"), "<b>" .. esc(state.player or blank) .. "</b>" ..
                ((tonumber(state.playerId) or 0) ~= 0 and (' <span class="u">#' .. esc(state.playerId) .. "</span>") or ""))
            rows[#rows + 1] = cell(T("session.ping"), "<b>" .. esc(state.ping ~= nil and state.ping or blank) .. '</b> <span class="u">' .. esc(T("session.milliseconds")) .. "</span>")
            if state.players ~= nil then
                rows[#rows + 1] = cell(T("session.players"), "<b>" .. esc(state.players) .. "</b>" ..
                    (state.capacity ~= nil and (' <span class="u">/ ' .. esc(state.capacity) .. "</span>") or ""))
            else
                rows[#rows + 1] = cell(T("session.tick"), "<b>" .. esc((state.tickRate or 0) ~= 0 and state.tickRate or blank) .. '</b> <span class="u">' ..
                    esc(F("session.tickUnit", { rate = (state.snapshotRate or 0) ~= 0 and state.snapshotRate or blank })) .. "</span>")
            end
            local server = (state.serverVersion and state.serverVersion ~= "")
                and ("<b>" .. esc(state.serverVersion) .. "</b>" .. ((state.serverProtocol and state.serverProtocol.major ~= nil)
                    and (' <span class="u">· p' .. esc(state.serverProtocol.major) .. "." .. esc(state.serverProtocol.minor) .. "</span>") or ""))
                or ('<span class="u">' .. esc(blank) .. "</span>")
            rows[#rows + 1] = cell(T("session.serverVersion"), server)
            rows[#rows + 1] = cell(T("session.endpoint"), "<b>" .. esc(Privacy.text(state.endpoint ~= "" and state.endpoint or blank)) .. "</b>", true)
            rows[#rows + 1] = cell(T("session.client"), clientCell, true)
            ui:rml("#session-grid", table.concat(rows))
            ui:setClasses("#session", "")
        else
            local busy = phase ~= "offline" and phase ~= "failed" and phase ~= "rejected" and phase ~= "disconnecting"
            ui:text("#session-name", busy and Privacy.text(state.server or state.endpoint or T("session.connecting")) or T("session.none"))
            ui:setClasses("#pill", busy and "busy" or "")
            ui:text("#pill-text", phase == "offline" and T("session.offline") or phase:upper())
            ui:rml("#session-grid", cell(T("session.client"), clientCell, true))
            ui:setClasses("#session", busy and "offline" or "offline idle")
        end
        ui:class("#root", "addresses", Privacy.visible)
        ui:class("#quit-session", "disabled", not state.connected)
    end

    -- ---- settings list --------------------------------------------------------------------
    local refreshToken = 0
    local function scheduleRefresh()
        refreshToken = refreshToken + 1
        local token = refreshToken
        SetTimeout(700, function()
            if token ~= refreshToken or not alive or S.page ~= "settings" or not S.tab then return end
            if S.sheet or S.capture then return end
            emit("settings:open", { tab = S.tab })
        end)
    end

    local function apply(row, value)
        if row.entry.disabled then return end
        row.entry.value = value
        emit("settings:set", { group = row.group, name = row.entry.name, value = value })
        if tostring(row.group):sub(1, 1) == "/" and row.entry.type ~= "int" then scheduleRefresh() end
    end

    local function rowById(id)
        local i = tonumber(tostring(id or ""):match("^r(%d+)$") or tostring(id or ""):match("^in(%d+)$"))
        return i and S.rows[i], i
    end

    -- repaint one row in place (a value change keeps the list, its scroll and the focus)
    local function repaintRow(i)
        local row = S.rows[i]
        if not row then return end
        local e = row.entry
        local sel = "#r" .. i
        if e.type == "int" then
            ui:style(sel .. " .fill", "width", (math.floor(ratio(e, e.value) * 1000 + 0.5) / 10) .. "%")
            ui:text(sel .. " .readout", U.formatValue(e, e.value))
        else
            ui:rml(sel .. " .ctl", U.rowRml(row, i, S):match('<div class="ctl">(.*)</div></div>$'))
        end
    end

    local function renderList(keepFocus)
        local focusKey = keepFocus and S.focus and S.focus:match("^r%d+$") and S.rows[tonumber(S.focus:sub(2))] and S.rows[tonumber(S.focus:sub(2))].key
        if S.focus and S.focus:match("^r%d+$") then S.focus = nil end
        S.rows = U.rows(S.sections, S.filter)
        local out, lastGroup, open = {}, nil, false
        local counts = {}
        for _, row in ipairs(S.rows) do counts[row.group] = (counts[row.group] or 0) + 1 end
        for i, row in ipairs(S.rows) do
            if row.group ~= lastGroup then
                if open then out[#out + 1] = "</div>" end
                out[#out + 1] = ('<div class="section"><div class="section-title"><span class="mark">//</span><span>%s</span><span class="count">%02d</span></div>')
                    :format(esc(T("groups." .. tostring(row.title), tostring(row.group))), counts[row.group])
                lastGroup, open = row.group, true
            end
            out[#out + 1] = U.rowRml(row, i, S)
        end
        if open then out[#out + 1] = "</div>" end
        if not S.done then
            out[#out + 1] = ('<div class="empty"><span class="mark">//</span>%s</div>'):format(esc(T("settings.loading")))
        elseif #S.rows == 0 then
            local text = S.filter ~= "" and F("settings.noMatch", { query = S.filter }) or T("settings.empty")
            out[#out + 1] = ('<div class="empty"><span class="mark">//</span>%s</div>'):format(esc(text))
        end
        ui:rml("#list", table.concat(out))
        if focusKey then
            for i, row in ipairs(S.rows) do
                if row.key == focusKey then S.focus = nil; setFocus("r" .. i, false); break end
            end
        end
    end

    local function selectTab(id)
        S.capture, S.sheet = nil, nil
        ui:class("#root", "sheet", false)
        S.tab = id
        S.sections, S.done, S.filter = {}, false, ""
        ui:value("#filter", "")
        ui:class("#filter-wrap", "typed", false)
        ui:text("#content-title", T("tabs." .. tostring(id), tostring(id):upper()))
        ui:text("#note", "")
        ui:setClasses("#note", "")
        renderTabs()
        renderList(false)
        ui:animate("#content", { from = { opacity = 0, x = 18 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.42, bounce = 0.08 } })
        emit("settings:open", { tab = id })
    end

    -- ---- pages ------------------------------------------------------------------------------
    local function showPage(name, focusId)
        S.page = name
        ui:setClasses("#root", "shown p-" .. name .. (S.logo ~= "" and " branded" or "") .. (Privacy.visible and " addresses" or ""))
        S.focus = nil
        legend()
        if focusId then setFocus(focusId, false) end
    end

    local function openSettings()
        S.zone = "rail"
        showPage("settings", nil)
        ui:animate("#panel", { to = { width = PANEL_SETTINGS .. "dp" }, spring = { duration = 0.38, bounce = 0.18 } })
        ui:animate("#rail > *", { from = { opacity = 0, x = -14 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.45, bounce = 0.1 }, stagger = 0.025 })
        if #S.tabs == 0 then
            S.sections, S.done = {}, true
            ui:rml("#list", ('<div class="empty"><span class="mark">//</span>%s</div>'):format(esc(T("settings.noCategories"))))
            setFocus("back", false)
            return
        end
        local first
        for _, tab in ipairs(S.tabs) do if tab.enabled ~= false and (not S.tab or tab.id == S.tab) then first = tab.id; break end end
        first = first or S.tabs[1].id
        selectTab(first)
        setFocus("tab-" .. first, false)
    end

    local function closeSettings()
        S.capture, S.sheet = nil, nil
        ui:class("#root", "sheet", false)
        refreshToken = refreshToken + 1
        emit("settings:closed", {})
        showPage("main", "settings")
        ui:animate("#panel", { to = { width = PANEL_MAIN .. "dp" }, spring = { duration = 0.34, bounce = 0.12 } })
        ui:animate("#page-main > *", { from = { opacity = 0, x = -16 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.42, bounce = 0.08 }, stagger = 0.03 })
    end

    local function ask(action)
        local copy = CONFIRMATIONS[action]
        if not copy then return end
        S.pending = action
        ui:text("#confirm-title", T(copy.title))
        ui:text("#confirm-body", T(copy.body))
        ui:rml("#confirm-icon", icon(copy.icon))
        showPage("confirm", "confirm-no")
        ui:animate("#page-confirm > *", { from = { opacity = 0, y = 14 }, to = { opacity = 1, y = 0 }, spring = { duration = 0.42, bounce = 0.1 }, stagger = 0.04 })
    end

    local function cancelConfirm()
        S.pending = nil
        showPage("main", "resume")
        ui:animate("#page-main > *", { from = { opacity = 0, x = -12 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.4, bounce = 0.08 }, stagger = 0.03 })
    end

    -- ---- open / close ------------------------------------------------------------------------
    local visibilityToken = 0
    local function openMenu(payload)
        visibilityToken = visibilityToken + 1
        if type(payload.generation) == "number" then S.generation = payload.generation end
        S.open, S.pending, S.capture, S.sheet = true, nil, nil, nil
        ui:class("#root", "sheet", false)
        local err = type(payload.error) == "string" and payload.error or ""
        ui:text("#pause-error", Privacy.text(err))
        ui:class("#pause-error", "on", err ~= "")
        ui:stop("#panel")
        ui:style("#panel", "width", PANEL_MAIN .. "dp")
        showPage("main", "resume")
        ui:animate("#scrim", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.18, easing = "out" })
        ui:animate("#aura", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.35, easing = "out" })
        ui:animate("#panel", { from = { x = -(PANEL_MAIN + 40), opacity = 1 }, to = { x = 0, opacity = 1 }, spring = { duration = 0.34, bounce = 0.28 } })
        ui:animate("#mast, #session", { from = { opacity = 0, x = -44 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.34, bounce = 0.3 }, delay = 0.02, stagger = 0.03 })
        ui:animate("#items > .item", { from = { opacity = 0, x = -54 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.36, bounce = 0.32 }, delay = 0.05, stagger = 0.025 })
        ui:animate("#foot", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.2, delay = 0.12 })
    end

    local function closeMenu(payload)
        payload = payload or {}
        visibilityToken = visibilityToken + 1
        local token = visibilityToken
        if type(payload.generation) == "number" then S.generation = payload.generation end
        local generation = S.generation
        S.open, S.capture = false, nil
        refreshToken = refreshToken + 1
        local function complete()
            if token ~= visibilityToken then return end
            S.pending, S.sheet = nil, nil
            if S.page == "settings" then emit("settings:closed", {}) end
            S.page = "main"
            ui:setClasses("#root", "")
            emit("pause:closed", { generation = generation })
        end
        if payload.immediate == true then complete() return end
        ui:animate("#panel", { to = { x = -(PANEL_SETTINGS + 80) }, duration = 0.17, easing = "ease-in" })
        ui:animate("#scrim, #aura", { to = { opacity = 0 }, duration = 0.17, easing = "ease-in" })
        SetTimeout(180, complete)
    end

    -- ---- the option sheet ---------------------------------------------------------------------
    local function sheetActive(index)
        local sh = S.sheet
        if not sh then return end
        index = clamp(index, 0, #sh.options - 1)
        if sh.active ~= nil then ui:class("#o" .. sh.active, "focus", false) end
        sh.active = index
        ui:class("#o" .. index, "focus", true)
        ui:scrollTo("#o" .. index, "nearest", true)
    end
    local function openSheet(i)
        local row = S.rows[i]
        if not row or not editable(row.entry) or row.entry.type ~= "list" then return end
        local options = row.entry.options or {}
        local current = clamp(math.floor(tonumber(row.entry.value) or 0), 0, #options - 1)
        S.sheet = { row = i, options = options, current = current, active = nil, query = "", queryAt = 0 }
        local out = {}
        for index, text in ipairs(options) do
            out[#out + 1] = ('<div id="o%d" class="opt%s"><div class="hl"></div><div class="bar"></div><span class="txt">%s</span>%s</div>')
                :format(index - 1, index - 1 == current and " current" or "", esc(upper(U.optionText(text))), icon("check"))
        end
        ui:rml("#sheet-list", table.concat(out))
        ui:text("#sheet-title", upper(labelFor(row.entry)))
        ui:text("#sheet-count", ("%d"):format(#options))
        ui:text("#sheet-find", "")
        ui:class("#sheet", "finding", false)
        ui:style("#sheet", "left", (50 + 270 + 36 + math.floor((PANEL_SETTINGS - 50 - 46 - 270 - 36 - 500) / 2)) .. "dp")
        ui:class("#root", "sheet", true)
        ui:animate("#sheet", { from = { opacity = 0, y = -12, scale = 0.97 }, to = { opacity = 1, y = 0, scale = 1 }, spring = { duration = 0.36, bounce = 0.14 } })
        ui:animate("#sheet-veil", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.2 })
        sheetActive(current)
    end
    local function closeSheet()
        if not S.sheet then return end
        S.sheet = nil
        ui:class("#root", "sheet", false)
    end
    local function commitSheet(index)
        local sh = S.sheet
        if not sh then return end
        local row = S.rows[sh.row]
        closeSheet()
        if row and index ~= sh.current then
            apply(row, index)
            repaintRow(sh.row)
        end
    end
    local function typeAhead(char)
        local sh = S.sheet
        local now = GetGameTimer()
        if now - sh.queryAt > 1100 then sh.query = "" end
        sh.query, sh.queryAt = sh.query .. char, now
        local hit
        for i, text in ipairs(sh.options) do
            if U.optionText(text):lower():sub(1, #sh.query) == sh.query then hit = i - 1; break end
        end
        if not hit then
            for i, text in ipairs(sh.options) do
                if U.optionText(text):lower():find(sh.query, 1, true) then hit = i - 1; break end
            end
        end
        ui:rml("#sheet-find", esc(T("settings.find")) .. ' <b>' .. esc(sh.query) .. "</b>" .. (hit and "" or (" - " .. esc(T("settings.findNoMatch")))))
        ui:class("#sheet", "finding", true)
        if hit then sheetActive(hit) end
    end

    -- ---- row actions -------------------------------------------------------------------------
    local function adjust(i, delta)
        local row = S.rows[i]
        if not row or not editable(row.entry) then return end
        local e = row.entry
        if e.type == "bool" then
            local value = delta > 0 and 1 or 0
            if tonumber(e.value) ~= value then apply(row, value); repaintRow(i) end
        elseif e.type == "list" then
            local value = clamp(math.floor(tonumber(e.value) or 0) + delta, 0, #(e.options or {}) - 1)
            if value ~= tonumber(e.value) then apply(row, value); repaintRow(i) end
        elseif e.type == "int" then
            local step = math.max(1, tonumber(e.step) or 1)
            local value = clamp((tonumber(e.value) or 0) + delta * step, tonumber(e.min) or 0, tonumber(e.max) or 100)
            if value ~= tonumber(e.value) then
                apply(row, value)
                ui:value("#in" .. i, tostring(value))
                repaintRow(i)
            end
        end
    end
    local function startCapture(i)
        local row = S.rows[i]
        if not row or row.entry.type ~= "keybind" or row.entry.disabled then return end
        S.capture = row.key
        S.captureRow = i
        S.captureAt = GetGameTimer()
        repaintRow(i)
    end
    local function finishCapture(name)
        local i = S.captureRow
        S.capture, S.captureRow, S.captureLayout = nil, nil, nil
        local row = i and S.rows[i]
        if not row then return end
        if name then
            row.entry.value = name
            emit("settings:set", { group = row.group, name = row.entry.name, value = name })
        end
        repaintRow(i)
    end
    local function activateRow(i, act)
        local row = S.rows[i]
        if not row then return end
        local e = row.entry
        if act == "reset" then
            if e.rebound == true then emit("settings:set", { group = row.group, name = e.name, value = "__default__" }) end
            return
        end
        if not editable(e) then return end
        if e.type == "bool" then adjust(i, tonumber(e.value) == 1 and -1 or 1)
        elseif e.type == "list" then
            if act == "prev" then adjust(i, -1) elseif act == "next" then adjust(i, 1) else openSheet(i) end
        elseif e.type == "keybind" then startCapture(i) end
    end

    -- ---- actions ---------------------------------------------------------------------------
    local function run(id)
        if id == "resume" then closeMenu({})
        elseif id == "map" then emit("pause:action", { action = "map" })
        elseif id == "settings" then openSettings()
        elseif id == "privacy" then emit("privacy:set", { visible = not Privacy.visible })
        elseif CONFIRMATIONS[id] then
            if id == "quit-session" and not S.state.connected then return end
            ask(id)
        elseif id == "confirm-no" then cancelConfirm()
        elseif id == "confirm-yes" then
            if S.pending then
                local action = S.pending
                S.pending = nil
                emit("pause:action", { action = action })
            end
        elseif id == "back" then closeSettings()
        elseif id == "vanilla" then emit("pause:vanilla-settings", {})
        elseif id == "filter-wrap" then setFocus("filter-wrap", false)
        elseif id == "filter-clear" then
            S.filter = ""
            ui:value("#filter", "")
            ui:class("#filter-wrap", "typed", false)
            renderList(false)
            setFocus("filter-wrap", false)
        elseif id:sub(1, 4) == "tab-" then
            S.zone = "content"
            selectTab(id:sub(5))
            setFocus("tab-" .. id:sub(5), false)
            S.zone = "rail"
        elseif id:match("^r%d+$") then activateRow(tonumber(id:sub(2)))
        end
    end

    local function back()
        if S.capture then finishCapture(nil) return end
        if S.sheet then closeSheet() return end
        if S.page == "confirm" then cancelConfirm() return end
        if S.page == "settings" then
            if S.filter ~= "" then run("filter-clear") return end
            closeSettings()
            return
        end
        closeMenu({})
    end

    -- ---- input --------------------------------------------------------------------------------
    ui:on("keydown", function(e)
        if not S.open then return end
        local key = tostring(e.key or "")
        if S.capture then
            if GetGameTimer() - (S.captureAt or 0) < 120 then return end
            if key == "escape" then finishCapture(nil)
            elseif LAYOUT_KEYS[key] then
                -- the layout's character comes next (textinput); the US name if it never does
                local fallback, row = U.bindingName(key) or key, S.captureRow
                S.captureLayout = true
                SetTimeout(160, function()
                    if S.captureLayout and S.captureRow == row then S.captureLayout = nil; finishCapture(fallback) end
                end)
            else
                local name = U.bindingName(key)
                if name then finishCapture(name) end
            end
            return
        end
        if key == "escape" then back() return end
        if S.sheet then
            local sh = S.sheet
            if key == "down" then sheetActive((sh.active or 0) + 1)
            elseif key == "up" then sheetActive((sh.active or 0) - 1)
            elseif key == "pagedown" then sheetActive((sh.active or 0) + 8)
            elseif key == "pageup" then sheetActive((sh.active or 0) - 8)
            elseif key == "home" then sheetActive(0)
            elseif key == "end" then sheetActive(#sh.options - 1)
            elseif key == "enter" or key == "space" then commitSheet(sh.active or sh.current)
            elseif key:match("^[a-z0-9]$") then typeAhead(key) end
            return
        end
        local typing = S.focus == "filter-wrap"
        if key == "tab" and S.page == "settings" then
            S.zone = S.zone == "rail" and "content" or "rail"
            if S.zone == "rail" then setFocus("tab-" .. tostring(S.tab), false)
            else
                local list = navList()
                setFocus(list[2] or list[1], true)
            end
            return
        end
        if key == "up" then moveFocus(-1)
        elseif key == "down" then moveFocus(1)
        elseif not typing and key == "home" and S.page == "settings" then moveFocus(0, "first")
        elseif not typing and key == "end" and S.page == "settings" then moveFocus(0, "last")
        elseif not typing and key == "pagedown" and S.page == "settings" then moveFocus(8)
        elseif not typing and key == "pageup" and S.page == "settings" then moveFocus(-8)
        elseif key == "left" or key == "right" then
            if typing then return end
            local i = S.focus and tonumber(S.focus:match("^r(%d+)$"))
            if i then adjust(i, key == "right" and 1 or -1)
            elseif S.page == "settings" and S.zone == "rail" and key == "right" then
                S.zone = "content"
                local list = navList()
                setFocus(list[2] or list[1], true)
            elseif S.page == "settings" and S.zone == "content" and key == "left" then
                S.zone = "rail"
                setFocus("tab-" .. tostring(S.tab), false)
            elseif S.page == "confirm" then moveFocus(key == "right" and 1 or -1) end
        elseif key == "enter" or (key == "space" and not typing) then
            if typing then moveFocus(1) return end
            if S.focus then run(S.focus) end
        end
    end)

    ui:on("textinput", function(e)
        if not S.capture or not S.captureLayout then return end
        local text = tostring(e.text or "")
        if text ~= "" and not text:match("^%s+$") then
            S.captureLayout = nil
            finishCapture(text:upper())
        end
    end)

    ui:on("mousedown", function(e)
        if not S.open or not S.capture then return end
        local name = MOUSE_NAMES[tonumber(e.button) or -1]
        if name and GetGameTimer() - (S.captureAt or 0) > 150 then
            S.swallowClickUntil = GetGameTimer() + 400
            finishCapture(name)
        end
    end)

    ui:on("mouseover", ".nav-item", function(e)
        if not S.open or S.sheet or S.capture then return end
        local id = e.id
        if not id or id == "" then return end
        if id:sub(1, 4) == "tab-" or id == "back" or id == "vanilla" then S.zone = "rail"
        elseif id == "filter-wrap" or id:match("^r%d+$") then S.zone = "content" end
        if id:match("^r%d+$") then
            local row = S.rows[tonumber(id:sub(2))]
            if not row or not editable(row.entry) then return end
        end
        if id ~= "filter-clear" then setFocus(id, false) end
    end)
    ui:on("mouseover", ".opt", function(e)
        if not S.sheet then return end
        local index = tonumber(tostring(e.id or ""):match("^o(%d+)$"))
        if index and index ~= S.sheet.active then
            if S.sheet.active ~= nil then ui:class("#o" .. S.sheet.active, "focus", false) end
            S.sheet.active = index
            ui:class("#o" .. index, "focus", true)
        end
    end)

    ui:on("click", function(e)
        if not S.open then return end
        if S.swallowClickUntil and GetGameTimer() < S.swallowClickUntil then S.swallowClickUntil = nil return end
        local target = tostring(e.targetId or "")
        if S.capture then return end
        if S.sheet then
            if target == "sheet-veil" then closeSheet() end
            return
        end
        if target == "scrim" or target == "aura" then closeMenu({}) return end
    end)
    ui:on("click", ".opt", function(e)
        if not S.sheet then return end
        local index = tonumber(tostring(e.id or ""):match("^o(%d+)$"))
        if index then commitSheet(index) end
    end)
    ui:on("click", ".nav-item", function(e)
        if not S.open or S.sheet or S.capture then return end
        if S.swallowClickUntil and GetGameTimer() < S.swallowClickUntil then return end
        local id = tostring(e.id or "")
        if id == "" then return end
        if id:match("^r%d+$") then
            local i = tonumber(id:sub(2))
            local row = S.rows[i]
            if not row then return end
            if editable(row.entry) then setFocus(id, false) end
            return -- the control inside decides (data-act below)
        end
        if id == "filter-clear" or id == "filter-wrap" then run(id) return end
        run(id)
    end)
    ui:on("click", ".act", function(e)
        if not S.open or S.sheet or S.capture then return end
        if S.swallowClickUntil and GetGameTimer() < S.swallowClickUntil then return end
        local i, act = tostring(e.id or ""):match("^c(%d+)%-(%a+)$")
        i = tonumber(i)
        if not i then return end
        if act == "toggle" then act = nil elseif act == "capture" then act = nil end
        activateRow(i, act)
    end)

    ui:on("change", "input.range", function(e)
        local row, i = rowById(e.id)
        if not row or row.entry.disabled then return end
        local e2 = row.entry
        local lo, hi, step = tonumber(e2.min) or 0, tonumber(e2.max) or 100, math.max(1, tonumber(e2.step) or 1)
        local value = clamp(lo + math.floor(((tonumber(e.value) or lo) - lo) / step + 0.5) * step, lo, hi)
        if value == tonumber(e2.value) then return end
        apply(row, value)
        repaintRow(i)
        setFocus("r" .. i, false)
    end)
    ui:on("mouseup", function()
        -- a dragged range keeps RmlUi's focus, whose own arrow keys would step it a second time
        if S.open and S.page == "settings" and S.focus ~= "filter-wrap" then ui:focusElement("#root") end
    end)

    local filterToken = 0
    ui:on("change", "#filter", function(e)
        if not S.open or S.page ~= "settings" then return end
        local value = tostring(e.value or "")
        if value == S.filter then return end
        S.filter = value
        ui:class("#filter-wrap", "typed", value ~= "")
        filterToken = filterToken + 1
        local token = filterToken
        SetTimeout(90, function()
            if token == filterToken and alive then renderList(false) end
        end)
    end)

    ui:onEvent("loaded", function()
        paintStatic()
        renderState()
        emit("pause:ready", {})
    end)
    -- a document reloaded from disk (nui.reload, hot reload) comes back empty: paint it all
    -- again from what is known, without re-announcing readiness
    ui:onEvent("reloaded", function()
        paintStatic()
        renderState()
        ui:stylesheet("accent", (U.theme(S.accent)))
        if S.logo ~= "" then ui:rml("#brand", '<img src="' .. S.logo .. '"/>') end
        if S.open then showPage("main", "resume") else ui:setClasses("#root", "") end
    end)
    ui:onEvent("error", function(name, detail)
        local message = tostring(detail and detail.message or "")
        print("Open77 pause (native): " .. tostring(name) .. ": " .. message)
        if name == "focus" and S.open then
            -- the input could not be taken (another page holds it): back out cleanly
            S.open = false
            emit("pause:closed", { generation = S.generation })
        end
    end)

    -- ---- the page API ---------------------------------------------------------------------
    function page.on(_, name, fn) page.handlers[name] = fn end
    function page.show() return ui:show() ~= false end
    function page.hide()
        ui:setClasses("#root", "")
        return ui:hide() ~= false
    end
    function page.setConsumedKeys() return true end
    function page.setFocus(_, keyboard, cursor)
        if keyboard or cursor then
            local ok = ui:focus({ keyboard = true, cursor = true })
            ui:focusElement("#root")
            return ok ~= false and ok ~= nil
        end
        ui:blur()
        return true
    end

    function page.send(_, name, payload)
        payload = type(payload) == "table" and payload or {}
        if name == "pause:strings" then
            strings = payload
            paintStatic()
            renderState()
        elseif name == "pause:state" then
            S.state = payload
            Privacy.remember(payload)
            renderState()
        elseif name == "privacy:state" then
            Privacy.visible = payload.visible == true
            ui:class("#root", "addresses", Privacy.visible)
            renderState()
        elseif name == "settings:tabs" then
            S.tabs = type(payload.tabs) == "table" and payload.tabs or {}
            if not S.tab and S.tabs[1] then S.tab = S.tabs[1].id end
            renderTabs()
        elseif name == "settings:values" then
            if payload.tab ~= S.tab then return true end
            if S.sheet or S.capture then
                -- never pull a list from under an open sheet or a capture: keep it for later
                S.pendingValues = payload
                return true
            end
            S.sections = type(payload.sections) == "table" and payload.sections or {}
            S.done = payload.done ~= false
            renderList(true)
        elseif name == "voice:levels" then
            for i, row in ipairs(S.rows) do
                local e = row.entry
                if e.name == "InputLevel" or e.name == "OutputLevel" then
                    local level = clamp(tonumber(e.name == "InputLevel" and payload.input or payload.output) or 0, 0, 100)
                    e.value = level
                    ui:style("#r" .. i .. " .fill", "width", math.floor(level) .. "%")
                    ui:text("#r" .. i .. " .readout", math.floor(level + 0.5) .. "%")
                    ui:class("#r" .. i, "active", e.name == "InputLevel" and payload.talking == true or e.name == "OutputLevel" and level > 0.5)
                    if e.name == "InputLevel" and payload.threshold ~= nil then
                        ui:style("#r" .. i .. " .thr", "left", clamp(math.floor(tonumber(payload.threshold) or 0), 0, 100) .. "%")
                    end
                elseif e.name == "TransmitMode" or e.name == "TransmitState" or (e.name == "VoiceReach" and payload.proximity ~= nil) then
                    local value = e.name == "TransmitMode" and payload.mode or e.name == "TransmitState" and payload.state
                        or F("voice.reachValue", { metres = math.floor((tonumber(payload.proximity) or 0) + 0.5) })
                    if value ~= e.value then
                        e.value = value
                        ui:text("#r" .. i .. " .info", tostring(value or T("settings.blank")))
                    end
                end
            end
        elseif name == "voice:feedback" or name == "settings:feedback" then
            if name == "settings:feedback" and payload.tab ~= S.tab then return true end
            ui:text("#note", tostring(payload.message or ""))
            ui:setClasses("#note", payload.ok and "ok" or "error")
        elseif name == "pause:branding" then
            local theme, accent = U.theme(payload.accentColor)
            S.accent = accent
            ui:stylesheet("accent", theme)
            local chunks = payload.logoChunks
            local logo = type(payload.logo) == "string" and payload.logo or (type(chunks) == "table" and #chunks <= 32 and table.concat(chunks) or "")
            if logo ~= S.logo then
                S.logo = ""
                if logo:match("^data:image/[%w.+-]+;base64,[%w+/=]+$") then
                    S.logo = logo
                    ui:rml("#brand", '<img src="' .. logo .. '"/>')
                elseif logo ~= "" and not logo:match("^https?://") then
                    emit("pause:logo-error", {})
                end
                -- a logo named by URL: the client downloads it and hands it over as data
                -- (a later revision of the appearance); until then the OPEN//77 logo is alone
                if S.logo == "" then ui:rml("#brand", "") end
                ui:class("#root", "branded", S.logo ~= "")
            end
        elseif name == "pause:open" then openMenu(payload)
        elseif name == "pause:close" then closeMenu(payload)
        end
        return true
    end

    -- a list that arrived under an open sheet or a capture lands once they close
    CreateThread(function()
        while alive do
            Wait(200)
            if S.pendingValues and not S.sheet and not S.capture then
                local payload = S.pendingValues
                S.pendingValues = nil
                page.send(page, "settings:values", payload)
            end
        end
    end)

    function page.destroy() alive = false; pcall(ui.destroy, ui) end
    ui:stylesheet("accent", (U.theme(DEFAULT_ACCENT)))
    return page
end
