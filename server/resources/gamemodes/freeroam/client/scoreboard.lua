-- The TAB roster on NativeUI (ui/scoreboard.rml). client/main.lua keeps the roster plumbing
-- (server pages, nameplate distances, TAB events) and talks to this module with the page API
-- the WebUI page had: page:on(name, fn), page:send(name, payload). The roster protocol is the
-- one web/scoreboard.js checked: paged full/delta revisions per epoch, a repair request on
-- any gap. Only the first rows are drawn (the board is held open, it never scrolls).
FreeroamScoreboard = {}
local S = FreeroamScoreboard

local MAX_ROWS = 12
local NEAR = 25

local function esc(s) return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")) end
local function integer(v, min, max)
    return type(v) == "number" and v == math.floor(v) and v >= min and v <= max
end
-- empty Lua lists can arrive as {} with no array part: both are lists
local function list(v)
    if type(v) ~= "table" then return nil end
    if next(v) == nil then return {} end
    return #v > 0 and v or nil
end

--- "12 m", "1.4 km"
function S.distance(m)
    m = tonumber(m) or 0
    if m >= 1000 then return ("%.1f km"):format(m / 1000) end
    return ("%d m"):format(math.floor(m + 0.5))
end

--- The name without its crew tag, the tag ("[OP//77 Team] Yuki" -> "Yuki", "OP//77 Team") and two initials.
function S.identity(label)
    label = tostring(label or "Player"):sub(1, 64)
    local crew = label:match("^%s*%[(.-)%]") or ""
    local name = label:gsub("^%s*%b[]%s*", "")
    if name == "" then name = label end
    local initials = {}
    for word in name:gmatch("[%w]+") do
        initials[#initials + 1] = word:sub(1, 1):upper()
        if #initials == 2 then break end
    end
    if #initials == 1 and #name > 1 then initials[2] = name:match("^[%w](%w)") or "" end
    return name, crew, table.concat(initials):upper()
end

local PALETTE = { "#22d8e2", "#2be58b", "#ffb020", "#ff2e88", "#7c5cff", "#4ea8ff", "#ff6b3d", "#c6f432" }

--- The roster state machine (no UI): pages in, ordered rows out.
function S.newRoster()
    local R = { roster = {}, size = 0, revision = nil, epoch = nil, pending = nil,
                distances = {}, distanceBatch = nil, selfId = nil, ordered = {}, dirty = true }

    -- returns "repair" when the client must ask for the full roster again
    function R.page(m)
        if type(m) ~= "table" then return "repair" end
        local players, removed = list(m.players), list(m.removed)
        if type(m.epoch) ~= "string" or not integer(m.revision, 0, 2 ^ 53) or not integer(m.pages, 1, 64)
            or not integer(m.page, 1, m.pages) or not integer(m.count, 0, 4096) or not players or not removed
            or #players + #removed > 128 or (m.kind ~= "full" and m.kind ~= "delta") then
            R.pending = nil
            return "repair"
        end
        if m.kind == "delta" then
            if R.epoch ~= m.epoch or R.revision == nil then R.pending = nil return "repair" end
            if m.revision <= R.revision then return nil end
            if m.base ~= R.revision then R.pending = nil return "repair" end
        elseif R.epoch == m.epoch and R.revision ~= nil and m.revision < R.revision then
            return nil
        end
        local p = R.pending
        if not p or p.revision ~= m.revision or p.epoch ~= m.epoch or p.kind ~= m.kind then
            p = { revision = m.revision, epoch = m.epoch, kind = m.kind, pages = m.pages, count = m.count, chunks = {}, got = 0 }
            R.pending = p
        end
        if p.pages ~= m.pages or p.count ~= m.count then R.pending = nil return "repair" end
        if not p.chunks[m.page] then p.got = p.got + 1 end
        p.chunks[m.page] = { players = players, removed = removed }
        if p.got ~= p.pages then return nil end
        local nextRoster, size = {}, 0
        if p.kind == "delta" then
            for id, name in pairs(R.roster) do nextRoster[id] = name; size = size + 1 end
        end
        for page = 1, p.pages do
            local chunk = p.chunks[page]
            for _, row in ipairs(chunk.players) do
                if type(row) ~= "table" or not integer(row.id, 1, 2 ^ 53) or type(row.name) ~= "string" or #row.name > 256 then
                    R.pending = nil
                    return "repair"
                end
                if nextRoster[row.id] == nil then size = size + 1 end
                nextRoster[row.id] = row.name
            end
            for _, id in ipairs(chunk.removed) do
                if not integer(id, 1, 2 ^ 53) then R.pending = nil return "repair" end
                if nextRoster[id] ~= nil then size = size - 1 end
                nextRoster[id] = nil
            end
        end
        if size ~= p.count then R.pending = nil return "repair" end
        R.roster, R.size, R.revision, R.epoch, R.pending = nextRoster, size, m.revision, m.epoch, nil
        R.dirty = true
        return "changed"
    end

    function R.distancesPage(m)
        if type(m) ~= "table" then return nil end
        local players = list(m.players)
        if not players or not integer(m.pages, 1, 64) or not integer(m.page, 1, m.pages) then return nil end
        local b = R.distanceBatch
        if not b or b.revision ~= m.revision then
            b = { revision = m.revision, pages = m.pages, chunks = {}, got = 0 }
            R.distanceBatch = b
        end
        if not b.chunks[m.page] then b.got = b.got + 1 end
        b.chunks[m.page] = players
        if b.got ~= b.pages then return nil end
        local nextDistances = {}
        for _, chunk in pairs(b.chunks) do
            for _, row in ipairs(chunk) do
                local id, d = tonumber(row.id), tonumber(row.distance)
                if id and d and d == d and d < math.huge then nextDistances[id] = d end
            end
        end
        R.distances, R.selfId, R.distanceBatch = nextDistances, tonumber(m.selfId), nil
        R.dirty = true
        return "changed"
    end

    -- self first, then streamed players by distance, then everyone else by name
    function R.order()
        if not R.dirty then return R.ordered end
        local out = {}
        for id, label in pairs(R.roster) do
            local d = R.distances[id]
            out[#out + 1] = { id = id, label = label, lower = label:lower(), self = id == R.selfId, distance = d, streamed = d ~= nil }
        end
        table.sort(out, function(a, b)
            if a.self ~= b.self then return a.self end
            if a.streamed ~= b.streamed then return a.streamed end
            if a.streamed and a.distance ~= b.distance then return a.distance < b.distance end
            if a.lower ~= b.lower then return a.lower < b.lower end
            return a.id < b.id
        end)
        R.ordered, R.dirty = out, false
        return out
    end
    return R
end

--- One row's RML.
function S.rowRml(p, index, enter, delay)
    local name, crew, initials = S.identity(p.label)
    local color = PALETTE[(p.id % #PALETTE) + 1]
    local streamed = p.streamed and not p.self
    local classes = "row" .. (p.self and " self" or (not streamed and " far" or ((p.distance or 0) <= NEAR and " near" or "")))
        .. (enter and " enter" or "")
    local style = enter and (' style="transition: opacity transform 0.36s %.3fs cubic-out;"'):format(delay) or ""
    local dist
    if p.self then
        dist = '<span class="you">YOU</span>'
    elseif streamed then
        -- the bar fills as they get closer (full under 25 m, empty past 500 m)
        local fill = math.max(0.04, math.min(1, 1 - (p.distance - NEAR) / (500 - NEAR)))
        dist = ('<span class="dist-bar"><span class="dist-fill" style="width: %d%%;"></span></span><span class="dist-text">%s</span>')
            :format(math.floor(fill * 100 + 0.5), S.distance(p.distance))
    else
        dist = '<span class="dist-text">--</span>'
    end
    local crewLine = crew ~= "" and ('<span class="crew">%s</span>'):format(esc(crew:upper())) or ""
    return ('<div class="%s"%s><span class="rank">%02d</span><span class="avatar" style="color: %s; border-color: %s88;">%s</span>'
        .. '<div class="who"><span class="name">%s</span>%s</div><span class="pid">%d</span><div class="dist">%s</div></div>')
        :format(classes, style, index, color, color, esc(initials ~= "" and initials or "?"), esc(name), crewLine, p.id, dist)
end

--- The board with the page API client/main.lua uses.
function S.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    local ui, why = Open77.ui.create({ document = "ui/scoreboard.rml", layer = "hud", zIndex = 40, visible = true })
    if not ui then return nil, why end
    local page = { handlers = {} }
    local R = S.newRoster()
    local opened, alive = false, true
    local openToken = 0
    local enterPending = false
    local shownKey = nil

    local function emit(name)
        local fn = page.handlers[name]
        if fn then fn({}) end
    end

    local function render()
        if not opened then return end
        local ordered = R.order()
        local near, streamed = 0, 0
        for _, p in ipairs(ordered) do
            if p.streamed and not p.self then
                streamed = streamed + 1
                if p.distance <= NEAR then near = near + 1 end
            end
        end
        local count = #ordered
        local rowsOut, keyParts = {}, {}
        local enter = enterPending
        for i = 1, math.min(MAX_ROWS, count) do
            local p = ordered[i]
            rowsOut[i] = S.rowRml(p, i, enter, (i - 1) * 0.035)
            keyParts[i] = p.id .. ":" .. (p.streamed and math.floor(p.distance) or -1) .. (p.self and "s" or "")
        end
        local key = table.concat(keyParts, ",") .. "|" .. count
        if key == shownKey and not enter then return end
        shownKey = key
        enterPending = false
        ui:rml("#rows", table.concat(rowsOut))
        ui:text("#count", tostring(count))
        ui:text("#st-near", tostring(near))
        ui:text("#st-streamed", tostring(streamed))
        ui:text("#st-far", tostring(math.max(0, count - streamed - (R.selfId and R.roster[R.selfId] and 1 or 0))))
        ui:text("#more", count > MAX_ROWS and ("+%d MORE IN THE CITY"):format(count - MAX_ROWS) or "")
        ui:text("#empty-text", R.revision == nil and "WAITING FOR THE SERVER ROSTER" or "NO ONE ELSE ON THE SERVER")
        ui:class("#root", "empty", count == 0)
    end

    local function setOpen(value)
        opened = value
        openToken = openToken + 1
        local tokenAt = openToken
        if value then
            enterPending, shownKey = true, nil
            ui:class("#rows", "in", false)
            ui:class("#root", "shown", true)
            render()
            -- one frame visible but folded, then the slide and the rows (transitions need a start)
            CreateThread(function()
                Wait(0)
                if alive and openToken == tokenAt then
                    ui:class("#root", "open", true)
                    ui:class("#rows", "in", true)
                end
            end)
        else
            ui:class("#root", "open", false)
            -- the glass still draws its blur while transparent: hide it once it has slid out
            CreateThread(function()
                Wait(240)
                if alive and openToken == tokenAt then ui:class("#root", "shown", false) end
            end)
        end
    end

    ui:onEvent("loaded", function() emit("scoreboard:ready") end)
    ui:onEvent("error", function(name, detail) print("[freeroam] scoreboard " .. tostring(name) .. ": " .. tostring(detail and detail.message)) end)

    function page.on(_, name, fn) page.handlers[name] = fn end

    function page.send(_, name, payload)
        if name == "scoreboard:rosterPage" then
            local r = R.page(payload)
            if r == "repair" then emit("scoreboard:requestRoster")
            elseif r == "changed" then render() end
        elseif name == "scoreboard:distances" then
            if R.distancesPage(payload) == "changed" then render() end
        elseif name == "scoreboard:open" then
            if not opened then setOpen(true) end
        elseif name == "scoreboard:closed" then
            if opened then setOpen(false) end
        end
    end

    function page.destroy() alive = false; pcall(ui.destroy, ui) end
    return page
end
