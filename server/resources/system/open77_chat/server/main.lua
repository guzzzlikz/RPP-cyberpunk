local enabled = true
local MAX_MESSAGE_BYTES = 256
local readyRequests = {}

local CHAT_SUGGESTIONS = {
    {
        command = "/help",
        help = "Справка по чату и командам.",
        parameters = {}
    },
    {
        command = "/clear",
        help = "Очистить историю чата.",
        parameters = {}
    },
    {
        command = "/me",
        help = "Действие от третьего лица (оранжевым). В обычном сообщении действие — в *звёздочках*.",
        parameters = { { name = "действие" } }
    },
    {
        command = "/id",
        help = "Показать временный ID в этой сессии.",
        parameters = {}
    },
}

local function clean(text)
    text = tostring(text or ""):gsub("[%c]", " ")
    text = text:match("^%s*(.-)%s*$") or ""
    if #text > MAX_MESSAGE_BYTES then
        local ok, boundary = pcall(utf8.offset, text, 0, MAX_MESSAGE_BYTES + 1)
        if ok and boundary then text = text:sub(1, boundary - 1)
        else text = text:sub(1, MAX_MESSAGE_BYTES) end
    end
    return text
end

-- RPP: ролевые действия. `*действие*` (звёздочки вплотную к тексту) красится
-- в оранжевый, сами звёздочки не показываются; /me — вся строка оранжевая.
-- Каждое сообщение также уходит «пузырём» над головой автора (open77_nameplates).
local TEXT_COLOR = { 238, 244, 248 }
local ACTION_COLOR = { 255, 154, 60 }

--- Текст -> фрагменты для чата: обычный текст и *действия* (без звёздочек).
--- Второе значение — текст без звёздочек (для логов и других ресурсов).
local function actionSegments(text)
    local segments, plain, pos = {}, {}, 1
    local function add(piece, color)
        if piece == "" then return end
        local last = segments[#segments]
        if last and last.color == color then last.text = last.text .. piece
        else segments[#segments + 1] = { text = piece, color = color } end
        plain[#plain + 1] = piece
    end
    while pos <= #text do
        local s, e, inner = text:find("%*([^%*]+)%*", pos)
        if not s then break end
        if inner:match("^%s") or inner:match("%s$") then
            -- «* текст *» с пробелами — это не действие: звёздочку оставляем как есть.
            add(text:sub(pos, s), TEXT_COLOR)
            pos = s + 1
        else
            add(text:sub(pos, s - 1), TEXT_COLOR)
            add(inner, ACTION_COLOR)
            pos = e + 1
        end
    end
    add(text:sub(pos), TEXT_COLOR)
    if #segments > 32 then return nil, text end -- у клиента лимит 32 фрагмента
    return segments, table.concat(plain)
end

-- Пузырь видят только те, кто в радиусе голоса автора: шёпот / обычно / крик
-- из open-voice (событие open-voice:modeApplied). Пока режим не известен —
-- обычный голос.
local DEFAULT_VOICE_DISTANCE = 20.0
local voiceDistance = {} -- [playerId] = метры

AddEventHandler("open-voice:modeApplied", function(player, _, distance)
    player, distance = tonumber(player), tonumber(distance)
    if player and distance then voiceDistance[player] = distance end
end)
AddEventHandler("onPlayerDisconnected", function(player)
    voiceDistance[tonumber(player) or -1] = nil
end)

local function position(player)
    local ok, pos = pcall(Open77.players.position, player)
    if ok and type(pos) == "table" and tonumber(pos.x) then return pos end
    return nil
end

local function bubble(player, payload)
    local range = voiceDistance[player] or DEFAULT_VOICE_DISTANCE
    payload.range = range
    local origin = position(player)
    local ok, players = pcall(Open77.players.all)
    if not origin or not ok or type(players) ~= "table" then
        -- Позиции недоступны: страница всё равно спрячет пузырь дальше `range`.
        TriggerClientEvent("open77_chat:bubble", -1, player, payload)
        return
    end
    local limit = (range + 2.0) ^ 2 -- небольшой запас на задержку позиций
    for _, other in ipairs(players) do
        other = tonumber(type(other) == "table" and other.id or other)
        if other and other ~= player then
            local pos = position(other)
            if pos and pos.bucket == origin.bucket then
                local dx, dy, dz = pos.x - origin.x, pos.y - origin.y, pos.z - origin.z
                if dx * dx + dy * dy + dz * dz <= limit then
                    TriggerClientEvent("open77_chat:bubble", other, player, payload)
                end
            end
        end
    end
end

local function targetId(value)
    local target = tonumber(value)
    return (target == nil or target == 0) and -1 or target
end

local function push(target, message)
    if type(message) == "string" then message = { text = message } end
    if type(message) ~= "table" then return false end
    return TriggerClientEvent("chat:addMessage", targetId(target), message)
end

RegisterNetEvent("chat:submit", function(raw)
    if not enabled then return end
    local text = clean(raw)
    if text == "" then return end

    local player = source
    local name = GetPlayerName(player) or ("Player " .. tostring(player))

    -- FiveM-compatible veto point. `chatMessage` is host-wide and cancellable: any
    -- resource can AddEventHandler("chatMessage", ...) and call CancelEvent() to
    -- drop the message before a single client sees it. Read `player` and `name`
    -- before awaiting -- the global `source` belongs to whatever task runs next.
    local verdict = TriggerCancellableEvent("chatMessage", player, name, text)
    if verdict ~= nil and verdict:await() then return end

    -- Accepted. Announced host-wide so logging, RP and moderation resources can
    -- observe it without subscribing to `chat:submit` themselves.
    TriggerEvent("chat:message", player, name, text)
    local segments, plain = actionSegments(text)
    local hasAction = false
    for _, segment in ipairs(segments or {}) do
        if segment.color == ACTION_COLOR then hasAction = true end
    end
    push(-1, {
        type = "player",
        author = name,
        text = plain,
        segments = hasAction and segments or nil,
        playerId = tostring(player),
        color = { 238, 244, 248 }
    })
    bubble(player, { kind = "say", text = plain, segments = segments })
end)

-- /me действие — ролевое действие от третьего лица, оранжевым.
RegisterCommand("me", function(player, args)
    player = tonumber(player)
    if not enabled or not player or player <= 0 then return end
    local text = clean(table.concat(args or {}, " "))
    text = text:gsub("%*", "")
    if text == "" then
        push(player, { type = "system", author = "/ME", text = "Использование: /me действие", color = { 252, 238, 10 } })
        return
    end
    local name = GetPlayerName(player) or ("Player " .. tostring(player))
    local verdict = TriggerCancellableEvent("chatMessage", player, name, "/me " .. text)
    if verdict ~= nil and verdict:await() then return end
    TriggerEvent("chat:message", player, name, "/me " .. text)
    push(-1, { type = "action", author = name, text = text, playerId = tostring(player) })
    bubble(player, { kind = "me", text = text })
end, false)

-- The WebUI requests suggestions whenever it is created. Other resources may
-- listen to the same network event and send their own command metadata directly
-- to this authenticated player.
RegisterNetEvent("chat:ready", function()
    local player = source
    local now = Open77.time.monotonic()
    if readyRequests[player] ~= nil and now - readyRequests[player] < 1 then return end
    readyRequests[player] = now
    TriggerClientEvent("chat:addSuggestions", player, CHAT_SUGGESTIONS)
end)

RegisterCommand("help", function(player)
    push(player, {
        type = "system",
        author = "COMMANDS",
        text = "Введи /, чтобы увидеть команды. Стрелки — выбор подсказки, Tab — дополнить.",
        color = { 252, 238, 10 }
    })
end, false)

RegisterCommand("clear", function(player)
    TriggerClientEvent("chat:clear", player)
end, false)

RegisterCommand("id", function(player)
    if player == nil or player <= 0 then
        print("id is only available to an authenticated player in chat")
        return
    end
    push(player, {
        type = "system",
        author = "SESSION",
        text = "Твой ID в сессии: " .. tostring(player) .. ".",
        color = { 252, 238, 10 }
    })
end, false)

-- Server-side API for other resources.
AddEventHandler("chat:addMessage", function(target, message) push(target, message) end)
AddEventHandler("chat:broadcast", function(message) push(-1, message) end)
AddEventHandler("chat:clear", function(target)
    TriggerClientEvent("chat:clear", targetId(target))
end)
AddEventHandler("chat:setEnabled", function(value, target)
    TriggerClientEvent("chat:setEnabled", targetId(target), value ~= false)
end)
AddEventHandler("chat:setServerEnabled", function(value)
    enabled = value ~= false
end)
AddEventHandler("chat:addSuggestion", function(target, command, help, parameters)
    TriggerClientEvent("chat:addSuggestion", targetId(target),
        tostring(command or ""), tostring(help or ""), parameters or {})
end)
AddEventHandler("chat:addSuggestions", function(target, suggestions)
    TriggerClientEvent("chat:addSuggestions", targetId(target), suggestions or {})
end)
AddEventHandler("chat:removeSuggestion", function(target, command)
    TriggerClientEvent("chat:removeSuggestion", targetId(target), tostring(command or ""))
end)
