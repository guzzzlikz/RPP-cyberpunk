-- The chat on NativeUI (ui/chat.rml): client/main.lua keeps its logic (commands, history
-- owner, suggestions from the server, exports) and talks to this module with the page API
-- it always used: chat:send(name, payload), chat:on(name, fn), chat:setFocus(kb, cursor).
ChatNative = {}
local N = ChatNative

local MAX_MESSAGES = 48
local MAX_LENGTH = 4096
local STALE_DELAY = 8500
local CLOSED_ROWS = 6   -- rows shown while the chat is closed (the newest)
local KINDS = { message = true, system = true, announce = true, warning = true, error = true, action = true, join = true, leave = true }
local CHANNELS = {
    global = { label = "ОБЩИЙ", color = "#fcee0a" },
    ["local"] = { label = "МЕСТНЫЙ", color = "#8a94a2" },
    squad = { label = "ОТРЯД", color = "#2be58b" },
    whisper = { label = "ШЁПОТ", color = "#7c5cff" },
    ooc = { label = "OOC", color = "#ffb020" },
    admin = { label = "АДМИН", color = "#ff3b4e" },
}

local function bounded(v, max) return tostring(v == nil and "" or v):sub(1, max or MAX_LENGTH) end
local function esc(s) return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")) end
local function token(v, fallback)
    local t = bounded(v, 24):lower():gsub("[^a-z0-9_-]", "")
    return t ~= "" and t or fallback
end
local function rgb(v, fallback)
    if type(v) ~= "table" or #v < 3 then return fallback end
    local function c(i) return math.max(0, math.min(255, math.floor((tonumber(v[i]) or 0) + 0.5))) end
    return ("#%02x%02x%02x"):format(c(1), c(2), c(3))
end

--- A message table (the chat API's: text/args/author/type/channel/color/segments/...) as row RML.
function N.normalize(raw, templates)
    if type(raw) == "string" then raw = { text = raw } end
    if type(raw) ~= "table" then return nil end
    local args = type(raw.args) == "table" and raw.args or {}
    local author = bounded(raw.author or (#args > 1 and args[1] or ""), 96)
    local text = raw.text or raw.message
    if text == nil then
        if #args > 1 then
            local rest = {}
            for i = 2, #args do rest[#rest + 1] = tostring(args[i]) end
            text = table.concat(rest, " ")
        else
            text = args[1]
        end
    end
    text = bounded(text, MAX_LENGTH)
    if raw.templateId and templates and templates[tostring(raw.templateId)] then
        text = templates[tostring(raw.templateId)]:gsub("{(%d+)}", function(i) return bounded(args[tonumber(i) + 1] or "", 1024) end)
    end
    local kind = token(raw.kind or raw.type, "message")
    if kind == "player" or kind == "default" then kind = "message" end
    if kind == "announcement" then kind = "announce" end
    if not KINDS[kind] then kind = "message" end
    local channel = CHANNELS[raw.channel] and raw.channel or (kind == "warning" and "admin" or "global")
    return {
        author = author, text = text, kind = kind, channel = channel,
        channelColor = CHANNELS[channel].color, color = rgb(raw.color, CHANNELS[channel].color),
        playerId = bounded(raw.playerId, 20), role = token(raw.role, ""), time = raw.time and bounded(raw.time, 16) or nil,
        segments = type(raw.segments) == "table" and raw.segments or {},
        mention = raw.mention == true or raw.mentioned == true, title = bounded(raw.title, 96),
        duration = tonumber(raw.duration),
    }
end

local function textRml(m)
    if #m.segments > 0 then
        local out = {}
        for i = 1, math.min(32, #m.segments) do
            local s = m.segments[i]
            if type(s) == "table" then
                local style = s.color and (' style="color: %s;"'):format(rgb(s.color, "#e6eaec")) or ""
                out[#out + 1] = ('<span class="%s"%s>%s</span>'):format(s.bold and "bold" or "", style, esc(bounded(s.text, 1024)))
            end
        end
        return ('<span class="text">%s</span>'):format(table.concat(out))
    end
    return ('<span class="text">%s</span>'):format(esc(m.text))
end

function N.rowRml(m)
    local time = m.time and ('<span class="time">%s</span>'):format(esc(m.time)) or ""
    if m.kind == "announce" then
        return ('<span class="announce-head">// %s</span>%s%s'):format(esc(m.title ~= "" and m.title or "SERVER ANNOUNCEMENT"), time, textRml(m))
    end
    if m.kind == "system" or m.kind == "error" or m.kind == "warning" then
        local marker = m.kind == "error" and "!" or (m.kind == "warning" and "▲" or "›")
        local source = m.author ~= "" and ('<span class="source">%s</span>'):format(esc(m.author)) or ""
        return ('%s<span class="marker">%s</span>%s%s'):format(time, marker, source, textRml(m))
    end
    if m.kind == "join" or m.kind == "leave" then
        local what = m.kind == "join" and "connected" or "disconnected"
        local extra = m.text ~= "" and (" · " .. m.text) or ""
        return ('%s<span class="dot">●</span><span class="text">%s %s%s</span>'):format(time, esc(m.author ~= "" and m.author or "Player"), what, esc(extra))
    end
    if m.kind == "action" then
        -- RPP: /me — вся строка оранжевая, без звёздочек.
        return ('%s<span class="text" style="color: #ff9a3c;">%s %s</span>'):format(time, esc(m.author ~= "" and m.author or "Player"), esc(m.text))
    end
    local tag = ('<span class="tag" style="color: %s; border-color: %s66;">%s</span>'):format(m.channelColor, m.channelColor, CHANNELS[m.channel].label)
    local pid = m.playerId:match("^%d+$") and ('<span class="pid">[%s]</span>'):format(m.playerId) or ""
    local author = ""
    if m.author ~= "" then
        local roleClass = (m.role == "admin" or m.role == "mod") and (" " .. m.role) or ""
        local role = m.role ~= "" and ('<span class="role">%s</span>'):format(esc(m.role:upper())) or ""
        author = ('<span class="author%s" style="color: %s;">%s%s</span>'):format(roleClass, m.color, esc(m.author), role)
    end
    return time .. tag .. pid .. author .. textRml(m)
end

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function cameraAngles()
    if type(Open77.camera) ~= "table" or type(Open77.camera.view) ~= "function" then return nil end
    local ok, v = pcall(Open77.camera.view)
    local f = ok and type(v) == "table" and v.forward
    if type(f) ~= "table" or (math.abs(f.x or 0) + math.abs(f.y or 0)) < 1e-4 then return nil end
    return math.deg(math.atan(-f.x, f.y)), math.deg(math.asin(clamp(f.z or 0, -1, 1)))
end

--- The chat floats in the game like the HUD: it trails the camera's turns with some inertia,
--- breathes, and takes the kick of each shot; while typing it holds almost still.
local function startFloat(ui, isOpen, alive)
    CreateThread(function()
        local yaw0, pitch0, at0 = nil, nil, GetGameTimer()
        local sx, sy, rx, ry, kick = 0, 0, 0, 0, 0
        local shots, generation, sent = nil, nil, nil
        local counters = type(Open77.weapons) == "table" and Open77.weapons.shotCounters or nil
        while alive() do
            Wait(0)
            local at = GetGameTimer()
            local dt = math.max(0.001, math.min(0.1, (at - at0) / 1000))
            at0 = at
            local calm = isOpen() and 0.25 or 1
            local yaw, pitch = cameraAngles()
            local yawVel, pitchVel = 0, 0
            if yaw and yaw0 then
                yawVel, pitchVel = ((yaw - yaw0 + 540) % 360 - 180) / dt, (pitch - pitch0) / dt
            end
            yaw0, pitch0 = yaw, pitch
            if counters then
                local ok, c = pcall(counters)
                if ok and type(c) == "table" and tonumber(c.total) then
                    local total = tonumber(c.total)
                    if shots and generation == c.generation and total > shots then
                        kick = math.min(1.6, kick + 0.7 * math.min(3, total - shots))
                    end
                    shots, generation = total, c.generation
                end
            end
            kick = kick * math.exp(-dt * 14)
            local k = 1 - math.exp(-dt * 6)
            sx = sx + (clamp(yawVel * 0.09, -22, 22) * calm - sx) * k
            sy = sy + (clamp(-pitchVel * 0.07, -15, 15) * calm - sy) * k
            ry = ry + (clamp(-yawVel * 0.02, -3, 3) * calm - ry) * k
            rx = rx + (clamp(pitchVel * 0.016, -2, 2) * calm - rx) * k
            local kk = kick * calm
            local fy = math.sin(at / 1000 * 0.8) * 1.8 * calm
            local jx = kk > 0.01 and (math.random() * 2 - 1) * kk * 2 or 0
            local spec = {
                rotateX = math.floor((rx + kk * 1.4) * 100 + 0.5) / 100, rotateY = math.floor(ry * 100 + 0.5) / 100,
                rotateZ = math.floor((math.random() * 2 - 1) * kk * 30 + 0.5) / 100,
                offset = { math.floor((sx + jx) * 10 + 0.5) / 10, math.floor((sy + fy + kk * 4) * 10 + 0.5) / 10, math.floor(-kk * 32 * 10 + 0.5) / 10 },
                perspective = 1600, origin = { 0.2, 0.2 },
            }
            local key = ("%.2f %.2f %.2f %.1f %.1f %.1f"):format(spec.rotateX, spec.rotateY, spec.rotateZ, spec.offset[1], spec.offset[2], spec.offset[3])
            if key ~= sent then
                sent = key
                ui:projection(spec)
            end
        end
    end)
end

--- The chat surface with the page API client/main.lua uses.
-- RPP: the embedded faces (Rajdhani, Chakra Petch, Lato) have no Cyrillic, so
-- Russian text rendered as blanks. Play Bold (OFL, ui/fonts/Play-OFL.txt) is
-- loaded as a FALLBACK face: RmlUi takes any glyph the requested family lacks
-- from it. Fallback faces are global to NativeUI, so the context menu, HUD and
-- every other RmlUi document get Cyrillic too.
local fontsLoaded = false
local function loadFallbackFonts()
    if fontsLoaded or type(Open77.ui.loadFont) ~= "function" then return end
    fontsLoaded = true
    local ok, loaded, why = pcall(Open77.ui.loadFont, "ui/fonts/Play-Bold.ttf", "RppPlay", true)
    if not ok or loaded == false then
        print("[open77_chat] Cyrillic fallback font not loaded: " .. tostring(ok and why or loaded))
    end
end

function N.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    loadFallbackFonts()
    local ui, why = Open77.ui.create({ document = "ui/chat.rml", layer = "hud", zIndex = 30, visible = true })
    if not ui then return nil, why end
    local page = { handlers = {} }
    local rows = {}            -- { serial, delay, token }
    local suggestions = {}     -- lower command -> { command, help, parameters }
    local templates = {}
    local history, historyIndex = {}, 1
    local open, enabled = false, true
    local value = ""
    local visible, selected = {}, 1
    local staleToken = 0
    local alive = true
    local openedAt = nil       -- when the composer took the focus (the opening key's character follows)
    local draftAtOpen = ""     -- RPP: черновик в момент открытия (к нему дописывается символ клавиши T)

    local function emit(name, payload)
        local fn = page.handlers[name]
        if fn then fn(payload or {}) end
    end

    local function updateCount()
        ui:text("#count", ("%02d"):format(#rows))
        ui:class("#root", "empty", #rows == 0)
    end

    local function schedule(row)
        staleToken = staleToken + 1
        row.token = staleToken
        local tokenAt = row.token
        ui:class(row.serial, "stale", false)
        if open then return end
        CreateThread(function()
            Wait(row.delay)
            if row.token == tokenAt and not open and ui then ui:class(row.serial, "stale", true) end
        end)
    end

    local function latest()
        local last = rows[#rows]
        if not last then return end
        ui:scrollTo(last.serial, false)
        -- the class change that opens the log lays it out on the next frames: pin again then
        CreateThread(function()
            for _ = 1, 2 do Wait(0) end
            if alive and rows[#rows] == last then ui:scrollTo(last.serial, false) end
        end)
    end

    local function markOld()
        for i, row in ipairs(rows) do
            local old = i <= #rows - CLOSED_ROWS
            if row.old ~= old then row.old = old; ui:class(row.serial, "old", old) end
        end
    end

    local function addMessage(raw)
        local m = N.normalize(raw, templates)
        if not m or (m.text == "" and #m.segments == 0) then return end
        local classes = "msg k-" .. m.kind .. (m.mention and " mention" or "")
        local style = (m.kind == "message") and ("border-left-color: " .. m.color .. ";") or nil
        local serial = ui:create("#messages", { tag = "div", class = classes, rml = N.rowRml(m), style = style and { ["border-left-color"] = m.color } or nil })
        local row = { serial = serial, delay = math.max(2500, m.duration or STALE_DELAY) }
        rows[#rows + 1] = row
        while #rows > MAX_MESSAGES do
            local old = table.remove(rows, 1)
            ui:remove(old.serial)
        end
        markOld()
        updateCount()
        latest()
        schedule(row)
    end

    local function renderSuggestions()
        local query = value:gsub("^%s+", ""):lower()
        if query:sub(1, 1) ~= "/" then
            visible = {}
            ui:class("#suggestions", "on", false)
            return
        end
        local command = query:match("^(%S*)")
        local list = {}
        for key, item in pairs(suggestions) do
            if key:sub(1, #command) == command then list[#list + 1] = item end
        end
        table.sort(list, function(a, b)
            if #a.command ~= #b.command then return #a.command < #b.command end
            return a.command < b.command
        end)
        visible = {}
        for i = 1, math.min(7, #list) do visible[i] = list[i] end
        selected = math.max(1, math.min(selected, #visible))
        if #visible == 0 then ui:class("#suggestions", "on", false) return end
        local out = { ('<div class="sg-head"><span>// COMMANDS</span><span class="grow"></span><span>%d %s</span></div>'):format(#visible, #visible == 1 and "MATCH" or "MATCHES") }
        for i, item in ipairs(visible) do
            local params = {}
            for p = 1, math.min(8, #(item.parameters or {})) do
                local param = item.parameters[p]
                local name = bounded(type(param) == "table" and param.name or param, 40)
                params[#params + 1] = (type(param) == "table" and param.optional) and ("[" .. name .. "]") or ("<" .. name .. ">")
            end
            out[#out + 1] = ('<div id="sg-' .. i .. '" class="sg%s"><span class="sg-cmd">%s</span><span class="sg-params">%s</span><span class="sg-help">%s</span></div>')
                :format(i == selected and " sel" or "", esc(item.command), esc(table.concat(params, " ")), esc(bounded(item.help, 240)))
        end
        ui:rml("#suggestions", table.concat(out))
        ui:class("#suggestions", "on", true)
    end

    -- RPP: лимит 1000 символов (не байт: русская буква — 2 байта).
    local CHAR_LIMIT = 1000
    local function charCount(text) return utf8.len(text) or #text end
    local function updateChars()
        local count = charCount(value)
        ui:text("#chars", count .. "/" .. CHAR_LIMIT)
        ui:class("#chars", "near", count >= CHAR_LIMIT - 100)
    end

    local function setValue(text)
        value = text
        ui:value("#input", text)
        updateChars()
        renderSuggestions()
    end

    local function complete()
        local item = visible[selected]
        if not item then return false end
        local suffix = value:match("^%s*/%S*(.*)$") or ""
        setValue(item.command .. (suffix:match("%S") and suffix or " "))
        selected = 1
        return true
    end

    local function setOpen(v)
        open = v == true
        ui:class("#root", "open", open)
        for _, row in ipairs(rows) do schedule(row) end
        if open then
            openedAt = GetGameTimer()
            draftAtOpen = value
            setValue(value) -- черновик остаётся в поле
            ui:focusElement("#input")
            latest()
            emit("chat:requestSuggestions", {})
        else
            -- RPP: черновик не стирается при закрытии — только после отправки
            -- (submit) или если игрок сам удалит текст.
            ui:blurElement("#input")
            selected = 1
            latest()
        end
    end

    local function submit()
        local text = value:match("^%s*(.-)%s*$")
        if text == "" then emit("chat:close", {}) return end
        history[#history + 1] = text
        if #history > 50 then table.remove(history, 1) end
        historyIndex = #history + 1
        ui:class("#root", "sending", false)
        CreateThread(function() Wait(0); if ui then ui:class("#root", "sending", true) end end)
        emit("chat:submit", { text = text })
        setValue("") -- отправлено: черновик больше не нужен
    end

    ui:onEvent("loaded", function()
        updateCount()
        emit("chat:ready", {})
    end)
    ui:onEvent("error", function(name, detail) print("[open77_chat] ui " .. tostring(name) .. ": " .. tostring(detail and detail.message)) end)

    ui:on("change", "#input", function(e)
        if not open then return end
        value = tostring(e.value or "")
        -- the key that opened the chat (T) is still typed: its character reaches the
        -- composer that just took the focus. A single character in the first moments is it.
        -- RPP: с черновиком символ клавиши дописывается к нему — убираем его же.
        if openedAt and GetGameTimer() - openedAt < 150
            and value:sub(1, #draftAtOpen) == draftAtOpen
            and charCount(value) == charCount(draftAtOpen) + 1 then
            openedAt = nil
            setValue(draftAtOpen)
            return
        end
        openedAt = nil
        selected = 1
        updateChars()
        renderSuggestions()
    end)
    ui:on("keydown", function(e)
        if not open then return end
        local key = tostring(e.key or "")
        if e.value ~= nil then value = tostring(e.value) end
        if key == "escape" then emit("chat:close", {})
        elseif key == "enter" or key == "return" then submit()
        elseif key == "tab" then
            complete()
            ui:focusElement("#input")
        elseif key == "up" then
            if #visible > 0 then selected = (selected - 2) % #visible + 1; renderSuggestions()
            elseif #history > 0 then historyIndex = math.max(1, historyIndex - 1); setValue(history[historyIndex] or "") end
        elseif key == "down" then
            if #visible > 0 then selected = selected % #visible + 1; renderSuggestions()
            elseif #history > 0 then historyIndex = math.min(#history + 1, historyIndex + 1); setValue(history[historyIndex] or "") end
        end
    end)
    ui:on("click", ".sg", function(e)
        local i = tonumber(tostring(e.id or ""):match("sg%-(%d+)"))
        if i then selected = i end
        complete()
        ui:focusElement("#input")
    end)

    local function addSuggestion(item)
        if type(item) ~= "table" or not item.command or item.command == "" then return end
        local command = tostring(item.command)
        if command:sub(1, 1) ~= "/" then command = "/" .. command end
        suggestions[command:lower()] = { command = command, help = item.help, parameters = item.parameters }
    end

    function page.on(_, name, fn) page.handlers[name] = fn end
    function page.setFocus(_, keyboard, cursor)
        if keyboard or cursor then ui:focus({ keyboard = true, cursor = cursor == true }) else ui:blur() end
        return true
    end
    function page.send(_, name, p)
        p = type(p) == "table" and p or {}
        if name == "chat:open" then setOpen(true)
        elseif name == "chat:close" then setOpen(false)
        elseif name == "chat:state" then
            enabled = p.enabled ~= false
            ui:class("#chat", "disabled", not enabled)
            if not enabled then setOpen(false) end
        elseif name == "chat:addMessage" then addMessage(p)
        elseif name == "chat:clear" then
            for _, row in ipairs(rows) do ui:remove(row.serial) end
            rows = {}
            updateCount()
        elseif name == "chat:clearSuggestions" then suggestions = {}; renderSuggestions()
        elseif name == "chat:addTemplate" then if p.id then templates[tostring(p.id)] = bounded(p.template) end
        elseif name == "chat:addSuggestion" then addSuggestion(p); renderSuggestions()
        elseif name == "chat:addSuggestions" then
            for _, item in ipairs(p.suggestions or {}) do addSuggestion(item) end
            renderSuggestions()
        elseif name == "chat:removeSuggestion" then
            local command = tostring(p.command or "")
            if command:sub(1, 1) ~= "/" then command = "/" .. command end
            suggestions[command:lower()] = nil
            renderSuggestions()
        end
    end
    function page.destroy() alive = false; pcall(ui.destroy, ui) end
    startFloat(ui, function() return open end, function() return alive end)
    return page
end
