-- The OPEN//77 connection screen on NativeUI (ui/shell.rml). client/main.lua keeps the whole
-- controller (launcher handoff, connection worker, resources, the world handoff and the
-- first-placement hold) and talks to this module with the page API the WebUI page had:
-- shell:on(name, fn(payload, request)), shell:send(name, payload), shell:reply(request, payload),
-- shell:show(), shell:hide(), shell:setFocus(keyboard, cursor). What the page's scripts did
-- (app.js, connection-errors.js, resource-errors.js, music.js) lives here; the lobby radio
-- plays through Open77's own audio (Play2DSound), no browser.
ShellUi = {}
local U = ShellUi

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function esc(v)
    return (tostring(v == nil and "" or v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
local function now() return Open77.time.monotonic() end

-- ---- safe text --------------------------------------------------------------------------
--- Strips control characters, credentials and connection strings from text shown to players.
function U.clean(value)
    local s = tostring(value == nil and "" or value):gsub("[%z\1-\31\127]", " ")
    s = s:gsub("[Bb]earer%s+[%w%._~%+/%-]+=*", "[authorization omitted]")
         :gsub("[Bb]asic%s+[%w%._~%+/%-]+=*", "[authorization omitted]")
    s = s:gsub("[Mm][Yy][Ss][Qq][Ll]://%S+", "[database address omitted]"):gsub("[Mm][Aa][Rr][Ii][Aa][Dd][Bb]://%S+", "[database address omitted]")
    for _, key in ipairs({ "password", "passwd", "pwd", "token", "secret", "authorization", "api_key", "apikey", "api%-key", "connectionstring" }) do
        s = s:gsub("(" .. key .. ")%s*[:=]%s*[^;%s]+", "%1=[redacted]")
    end
    -- URLs keep scheme, host and path: no credentials, query or fragment
    s = s:gsub("(https?://)([^%s]+)", function(scheme, rest)
        rest = rest:gsub("^[^/@]*@", ""):gsub("[?#].*$", "")
        return scheme .. rest
    end)
    return s:sub(1, 800)
end
local clean = U.clean

local REASONS = {
    master_unavailable = "Server list unavailable",
    invalid_master_response = "Server list could not be read",
    catalog_request_rejected = "Server list request refused",
    server_not_in_catalog = "Server is no longer listed",
    unsecured_consent = "This server is unsecured. Confirm the warning to join",
    mods_relaunch_required = "This world requires mods. The game must restart through the launcher",
    launcher_not_registered = "The OPEN//77 launcher is not installed on this machine",
    launcher_launch_failed = "The launcher could not be started",
    game_window_close_failed = "The launcher opened, but the game could not close. Close the game window to continue in the launcher.",
    script_bridge_not_attached = "The game is not ready to handle this action. Try again shortly or close its window.",
    relaunch_failed = "The game could not hand over to the launcher",
    connection_already_in_progress = "Already connecting",
    resource_download_failed = "The server's content pack could not be downloaded. Check your connection and try again.",
    connection_refused = "The server refused the connection. It may be offline or restarting.",
    connection_timeout = "The server did not respond in time.",
    invalid_display_name = "Username must contain 1 to 32 UTF-8 bytes",
    identity_update_requires_offline_session = "Disconnect before changing your username",
    identity_master_rejected = "The Master rejected this username",
    identity_update_timeout = "Username update timed out",
    master_change_requires_offline_session = "Disconnect before changing Master",
    unknown_master = "Unknown Master server",
    unsupported_version = "This server is running a different version of Open//77. Update your mod to the latest build, then try again.",
    unknown_message = "This server is running a different version of Open//77.",
    invalid_magic = "That address is not an Open//77 server.",
    invalid_server_packet = "The server sent data this client could not read - it is most likely running a different Open//77 version.",
    malformed_server_reject = "The server refused the connection but its reply could not be read.",
    connect_timeout = "The server did not respond. It may be offline, full, or unreachable.",
    handshake_timeout = "The connection opened but the server never finished the handshake.",
    server_rejected = "The server rejected your connection.",
    server_welcome_identity_mismatch = "The server could not verify your identity. Try reconnecting.",
    server_lease_invalid = "The server's run lease was rejected by the Master.",
    server_lease_missing = "The server did not present a valid run lease.",
    dns_resolution_failed = "The server address could not be resolved.",
    dns_no_supported_address = "The server address could not be resolved.",
    invalid_server_endpoint = "The server address is not valid.",
    identity_not_registered = "You are not signed in to this Master. Sign in again, then reconnect.",
    session_already_busy = "A connection is already in progress.",
    pristine_load_failed = "Your character could not be loaded. Try reconnecting.",
    character_bootstrap_failed = "Your character could not be prepared for this server.",
    session_ended = "The session ended before you reached the world.",
    server_disconnected = "You were disconnected from the server.",
    database_error = "The server could not load your character because its database is unavailable or a database operation failed.",
    database_unavailable = "The server cannot access its character database.",
    database_unreachable = "The server's database is not responding.",
    pristine_load_timeout = "The game did not finish preparing your character in time.",
    launcher_required = "Choose a server in the Open77 launcher first.",
    native_transition_in_progress = "The game is preparing your character. Wait for this transition to finish, or quit the game.",
    connection_lost = "The connection to the server was lost.",
    character_creation_cancelled = "Character creation was cancelled.",
    identity_update_failed = "Your identity could not be verified. Sign in again in the launcher.",
    user_quit = "You left the session.",
}

--- A signed-resource download failure, explained for the player and the server owner.
function U.explainResource(reason, diagnostic)
    local token = tostring(reason or ""):gsub("[%z\1-\31\127]", " "):sub(1, 512)
    local prefixes = { "resource_", "resources_", "package_", "cbor_", "invalid_resource", "unsafe_resource", "unsafe_path",
                       "too_many_resource", "duplicate_resource", "unsupported_cbor", "indefinite_cbor", "invalid_cbor" }
    local matched = false
    for _, p in ipairs(prefixes) do if token:sub(1, #p) == p then matched = true; break end end
    if not matched then return nil end
    token = token:gsub("^resource_download_failed:", ""):gsub("^resource_install_failed:", "")
    local d = type(diagnostic) == "table" and diagnostic or {}
    local code = tostring(d.code or token:match("^([^ :]+)") or ""):sub(1, 96)
    local status = tonumber(d.httpStatus) or tonumber(token:match("^resource_http_status:(%d+)")) or 0
    local os = tonumber(d.osError) or 0
    local summary = "The server resources could not be installed."
    local player = "Retry the connection. If it still fails, share the diagnostic details with the server owner."
    local owner = "Check the public resource URL, TCP firewall/NAT rule and the server resource logs."
    if code == "resources_require_https_or_loopback" then
        summary = "This client build blocks the server's HTTP resource downloads."
        player = "Update the Open77 client. This is not a problem with your internet connection."
        owner = "Use an updated client supporting signed HTTP resources, or optionally configure a valid HTTPS resource URL."
    elseif os == 12007 then
        summary = "The resource server's hostname could not be resolved."
        owner = "Check DNS and resources.download.publicBaseUrl. The game address and resource address can be different."
    elseif os == 12002 then
        summary = "The resource server did not respond in time."
        owner = "Check the TCP resource port, reverse proxy timeout and upload bandwidth. Opening the UDP game port alone is not enough."
    elseif os == 12029 or code:find("resource_http_connect_failed", 1, true) then
        summary = "The game server is reachable, but its resource download service could not be reached."
        owner = "Start the resource HTTP listener and forward/open its TCP port (normally 11779). Verify the public URL from another network."
    elseif os == 12175 then
        summary = "The resource server's HTTPS certificate could not be verified."
        owner = "Fix the certificate hostname, expiry and chain, or explicitly advertise a public HTTP URL for signed resources. Do not disable TLS verification."
    elseif code == "resource_http_status" then
        summary = "The resource server returned HTTP " .. status .. "."
        if status == 404 then owner = "The requested set/package/chunk is missing. Check the public URL path and reverse proxy routing; refresh/re-publish the current resource set."
        elseif status == 401 or status == 403 then owner = "Resource files must be publicly downloadable without login. Check proxy authentication, WAF and file access rules."
        elseif status >= 300 and status < 400 then owner = "The download endpoint redirects. Advertise the final direct resource URL; redirects are not followed."
        elseif status == 429 or status >= 500 then owner = "Check resource service availability, rate limits and reverse proxy logs. Temporary failures are retried automatically." end
    elseif code:find("signature") or code:find("identity_mismatch") then
        summary = "The server resources failed authenticity verification."
        player = "Do not bypass verification. Retry once, then send these details to the server owner."
        owner = "Check the advertised signing key and preserve Open77-Signature / Open77-Public-Key headers through the proxy. Re-publish a coherent resource set."
    elseif code:find("digest_mismatch") or code:find("generation_mismatch") then
        summary = "The resource content does not match the version advertised by the server."
        owner = "Check for a changed resource generation, a stale reverse proxy cache or altered files. Refresh/re-publish the set; do not disable hash checks."
    elseif code:find("cache") or code:find("file_create") or code:find("file_write") or code:find("generation_commit") or code:find("previous_generation") then
        summary = "Open77 could not write or activate the local resource cache."
        player = "Check free disk space, game-folder write access and antivirus quarantine. Close duplicate game instances before retrying; do not delete your server keys."
        owner = "This report points to the player's local cache, not automatically to your server configuration."
    elseif code:find("too_large") or code:find("too_many") or code:find("unsafe") or code:find("cbor") or code:find("package_manifest")
        or code:find("duplicate_resource") or code:find("invalid_resource_file") then
        summary = "The server resource package is invalid or exceeds a supported limit."
        owner = "Check the named resource/file, package size and server packaging logs. Update the server and rebuild the resource set."
    elseif code:find("invalid_resource.*url") or code:find("invalid_resource_advertisement") then
        summary = "The server advertised an invalid resource download address."
        owner = "Set resources.download.publicBaseUrl to a public HTTP(S) base URL, without credentials, query or fragment."
    end
    local url = ""
    local raw = tostring(d.url or "")
    if raw:match("^https?://") then url = clean(raw):sub(1, 2048) end
    local fields = {}
    for _, row in ipairs({ { "Download ID", tostring(d.id or ""):sub(1, 64) }, { "Code", code }, { "Stage", tostring(d.stage or ""):sub(1, 48) },
        { "Resource", tostring(d.resource or ""):sub(1, 128) }, { "File", tostring(d.file or ""):sub(1, 512) }, { "Download URL", url },
        { "HTTP status", status ~= 0 and tostring(status) or "" }, { "OS error", os ~= 0 and tostring(os) or "" } }) do
        if row[2] ~= "" then fields[#fields + 1] = row end
    end
    return { summary = summary, player = player, owner = owner, fields = fields }
end

local ERROR_KINDS = {
    lua_error = "Lua runtime error", lua_syntax_error = "Lua syntax error", manifest_export_missing = "Missing export",
    permission_denied = "Permission refused", resource_start_failed = "Start refused",
}

--- "res/dir/file.lua:12" for a report (empty when it names no file).
function U.where(r)
    if type(r) ~= "table" or tostring(r.file or "") == "" then return "" end
    local owner = tostring(r.fileResource or "")
    local line = tonumber(r.line) or 0
    return (owner ~= "" and owner .. "/" or "") .. tostring(r.file) .. (line > 0 and (":" .. math.floor(line)) or "")
end

--- A server resource that could not start (client host report, open77:resources:activationFailed).
--- The download diagnostic is NOT used here: the install succeeded, a script failed.
function U.explainActivation(activation)
    local r = type(activation) == "table" and type(activation.report) == "table" and activation.report or nil
    if not r then
        return { code = "resource_activation_failed", title = "Server script error",
                 message = "One of this server's resources could not start on your game.",
                 action = "Retry once. If it fails again, tell the server's staff: a script on the server failed, not your game.",
                 owner = "The client log (red4ext/logs/open77-*.log) names the resource and the Lua error.", fields = {} }
    end
    local code = clean(r.code or ""):sub(1, 64)
    local kind = ERROR_KINDS[code] or code
    local resource = clean((r.resource or "") ~= "" and r.resource or "A server resource"):sub(1, 96)
    local where = clean(U.where(r)):sub(1, 300)
    local fields = { { "Resource", resource }, { "Error", kind } }
    if where ~= "" then fields[#fields + 1] = { "Where", where } end
    fields[#fields + 1] = { "Message", clean(r.message or "") }
    fields[#fields + 1] = { "Stage", clean(r.stage or "") }
    return { code = "resource_activation_failed", title = "Server script error",
             message = resource .. " could not start.",
             action = "Not a problem with your game: a script on this server failed. Copy the report and send it to the server's staff.",
             owner = "The same report is in the server console (RESOURCE START FAILED ON A CLIENT)." ..
                 (where ~= "" and (" Fix " .. where .. ", then refresh the resource.") or ""),
             fields = fields, kind = kind, where = where, resource = resource }
end

--- A failure reason as the screen tells it: { code, title, message, action, owner, fields }.
function U.explain(reason, diagnostic, activation)
    local raw = clean(reason or "server_disconnected")
    local token = raw:match("^([^:]*)") or raw
    if token == "resource_activation_failed" then return U.explainActivation(activation) end
    if token:match("^database_") then
        return { code = token, title = "Server database error", message = REASONS[token] or REASONS.database_error,
                 action = "This is a server-side problem. Contact the server owner, then retry after they restore the database.",
                 owner = "Check Database & persistence in Warden, start MySQL/MariaDB and restart resources whose initialization failed.", fields = {} }
    end
    local download = U.explainResource(raw, diagnostic)
    if download then
        local fields = {}
        for i, f in ipairs(download.fields) do fields[i] = { clean(f[1]), clean(f[2]) } end
        return { code = token, title = "Resources could not load", message = download.summary, action = download.player,
                 owner = download.owner, fields = fields }
    end
    local detail = raw:find(":", 1, true) and raw:sub(raw:find(":", 1, true) + 1):match("^%s*(.-)%s*$") or ""
    local message = REASONS[raw] or REASONS[detail] or REASONS[token]
    if not message then
        if (token:match("^server_reject") or token:match("^kicked") or token:match("^banned")) and detail ~= "" then message = detail
        else message = "The session could not continue. Share the details below with the server owner." end
    end
    local version = raw:find("version") or raw:find("unknown_message")
    return { code = raw, title = version and "Version mismatch" or "Connection interrupted", message = message,
             action = version and "Review client updates in the launcher and check the server version with its owner."
                 or "You can retry this server or choose another one in the launcher.", fields = {}, owner = "" }
end

-- ---- address privacy (display only) --------------------------------------------------------
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
    local hidden = "[address hidden]"
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

-- phase -> checkpoint, label
local PHASES = {
    enrolling = { 0, "Verifying identity" }, resolving = { 1, "Resolving server" }, connecting = { 1, "Connecting" },
    handshaking = { 1, "Verifying connection" }, active = { 2, "Preparing server resources" },
    manifest = { 2, "Reading resource manifest" }, downloading = { 2, "Downloading resources" },
    retrying = { 2, "Retrying resource download" }, verifying = { 2, "Verifying resources" },
    ready = { 3, "Preparing character" }, creating_character = { 3, "Create your character" },
    world = { 4, "Loading Night City" },
}
U.PHASES = PHASES

local FONTS = {
    { "ui/fonts/Druk-MediumItalic.ttf", "Druk" }, { "ui/fonts/Nippo-500.ttf", "Nippo" }, { "ui/fonts/Nippo-700.ttf", "NippoBold" },
    { "ui/fonts/Satoshi-400.ttf", "Satoshi" }, { "ui/fonts/Satoshi-500.ttf", "SatoshiMed" }, { "ui/fonts/Satoshi-700.ttf", "SatoshiBold" },
}

local ICON_PAUSE, ICON_PLAY = "M7 5h3v14H7zM14 5h3v14h-3z", "M7 4v16l14-8z"

-- ---------------------------------------------------------------------------------------
--- The connection screen with the page API client/main.lua uses.
function U.create()
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then return nil, "nativeui_unavailable" end
    for _, font in ipairs(FONTS) do
        local ok, why = Open77.ui.loadFont(font[1], font[2], false)
        if not ok then print("Open77 shell: font " .. font[1] .. " not loaded: " .. tostring(why)) end
    end
    local ui, why = Open77.ui.create({ document = "ui/shell.rml", layer = "system", zIndex = 5, visible = false })
    if not ui then return nil, why end
    local page = { handlers = {} }
    local requests, nextRequest = {}, 0
    local alive = true
    local applyFocus -- defined with the show / hide logic below; the painters call it
    local startSlideshow -- defined with the artworks below
    local playIntro, assemble -- defined with the intro below
    local startFloat -- defined with the depth and float below
    local setVolumeBar -- defined with the radio input below
    local introState = "pending"

    -- what is on screen (the page script's state)
    local S = {
        target = nil, client = {}, server = {}, attempt = 0, started = nil, failure = nil, resourceDiagnostic = nil,
        checkpoint = -1, connecting = false, terminal = false, stage = "standby", report = "", busy = false,
        view = "idle", shown = false, suppressed = false, detailsOpen = false, headline = "",
    }
    -- the lobby radio
    local M = { enabled = true, volume = 0.12, visible = false, ready = false, sound = nil, playing = false, error = nil }

    local function emit(name, payload, onReply)
        local fn = page.handlers[name]
        if not fn then return end
        local request
        if onReply then
            nextRequest = nextRequest + 1
            request = nextRequest
            requests[request] = onReply
        end
        fn(payload or {}, request)
    end

    local function setView(next, source)
        if S.view == next then return end
        local before = S.view
        S.view = next
        ui:class("#root", "v-idle", next == "idle")
        ui:class("#root", "v-loading", next == "loading")
        ui:class("#root", "v-failed", next == "failed")
        ui:class("#root", "v-notice", next == "notice")
        emit("shell:trace", { view = next, from = before, source = source })
        if next == "failed" then
            ui:animate("#diag", { from = { opacity = 0, y = 14 }, to = { opacity = 1, y = 0 }, spring = { duration = 0.45, bounce = 0.2 } })
            ui:animate("#dest", { from = { x = 10 }, to = { x = 0 }, spring = { duration = 0.5, bounce = 0.55 } })
        elseif next == "notice" then
            ui:animate("#notice", { from = { opacity = 0, y = -16 }, to = { opacity = 1, y = 0 }, spring = { duration = 0.4, bounce = 0.2 } })
        end
    end

    -- ---- painting -----------------------------------------------------------------------
    local function paintTarget()
        Privacy.remember(S.target)
        local t = S.target or {}
        ui:text("#servername", Privacy.text(clean(t.name or t.endpoint or "Where to next?")))
        ui:text("#endpoint", Privacy.text(clean(t.endpoint or "Choose your destination in the launcher.")))
        ui:text("#master", t.master and (clean(t.master):upper() .. " / MASTER") or "LAUNCHER MANAGED")
        local canRetry = t.endpoint ~= nil and not S.connecting and not S.busy
        ui:class("#retry", "disabled", not canRetry)
        ui:class("#root", "no-retry", S.view == "idle" and not canRetry)
        ui:text("#retryhint", not t.endpoint and "No connection to retry yet." or S.connecting and "Connection in progress."
            or "Retries only this destination. Use the launcher to change servers.")
    end

    -- ---- the segmented bar -------------------------------------------------------------
    -- 5 stages x 10 segments. Stages behind are blue, the current one fills in yellow as its
    -- progress is known (each new segment springs up), a scanner sweeps it while it is not,
    -- a failed one turns pink. The percentage rolls toward the overall progress.
    local SEGS = 10
    local seg = {}            -- seg[g][i] = "" | "on" | "done" | "fail" (what is painted)
    for g = 0, 4 do seg[g] = {} for i = 0, SEGS - 1 do seg[g][i] = "" end end
    local bar = { frac = nil, failed = false, scan = -1, pctShown = 0, pctTarget = 0 }
    local function setSeg(g, i, state, delay)
        if seg[g][i] == state then return false end
        local wasLit = seg[g][i] ~= ""
        seg[g][i] = state
        ui:setClasses("#s" .. g .. "_" .. i, state == "" and "seg" or ("seg " .. state))
        if state ~= "" and not wasLit then
            ui:animate("#f" .. g .. "_" .. i, { from = { scaleY = 0.1 }, to = { scaleY = 1 }, spring = { duration = 0.45, bounce = 0.55 }, delay = delay or 0 })
        end
        return true
    end
    local function renderBar()
        local cp = S.checkpoint
        local appear = 0
        for g = 0, 4 do
            local count, state = 0, ""
            if g < cp then count, state = SEGS, "done"
            elseif g == cp then
                state = bar.failed and "fail" or "on"
                if bar.frac then count = math.floor(clamp(bar.frac, 0, 1) * SEGS + 0.0001)
                else count = 0 for i = 0, SEGS - 1 do if seg[g][i] == "on" or seg[g][i] == "fail" then count = i + 1 end end end
                if bar.failed then count = math.max(count, 1) end
            end
            local becameDone = false
            for i = 0, SEGS - 1 do
                local want = i < count and state or ""
                local was = seg[g][i]
                if setSeg(g, i, want, (want ~= "" and was == "") and (appear * 0.035) or 0) then
                    if want ~= "" and was == "" then appear = appear + 1 end
                    if want == "done" and was == "on" then becameDone = true end
                end
            end
            if becameDone then
                ui:animate("#g" .. g, { from = { scaleY = 1.6 }, to = { scaleY = 1 }, spring = { duration = 0.5, bounce = 0.5 } })
            end
            local lab = g < cp and "lab done" or (g == cp and (bar.failed and "lab failed" or "lab current") or "lab")
            ui:setClasses("#st" .. g, lab)
        end
        ui:text("#checkpoint", cp < 0 and "-- / 05" or ("%02d / 05"):format(cp + 1))
        if not bar.failed then
            bar.pctTarget = cp < 0 and 0 or clamp(math.floor((cp + (bar.frac or 0)) / 5 * 100 + 0.5), 0, 100)
        end
    end
    local function paintSteps(failed)
        bar.failed = failed == true
        renderBar()
    end
    local function progress(done, total)
        total = tonumber(total)
        local frac = (total and total > 0) and clamp((tonumber(done) or 0) / total, 0, 1) or nil
        if frac and bar.frac and bar.fracStage == S.checkpoint then frac = math.max(frac, bar.frac) end
        bar.frac, bar.fracStage = frac, S.checkpoint
        renderBar()
    end
    local function resetBar()
        for g = 0, 4 do for i = 0, SEGS - 1 do seg[g][i] = "x" end end
        for g = 0, 4 do for i = 0, SEGS - 1 do setSeg(g, i, "") end end
        bar.frac, bar.failed, bar.pctShown, bar.pctTarget = nil, false, 0, 0
        ui:text("#percent", "00")
    end
    -- the percentage rolls, the scanner sweeps the current stage while its progress is unknown
    CreateThread(function()
        local scanAt = 0
        while alive do
            Wait(16)
            if bar.pctShown ~= bar.pctTarget then
                local d = bar.pctTarget - bar.pctShown
                bar.pctShown = math.abs(d) < 0.6 and bar.pctTarget or (bar.pctShown + d * 0.14)
                ui:text("#percent", ("%02d"):format(math.floor(bar.pctShown + 0.5)))
            end
            local now = GetGameTimer()
            if now - scanAt >= 75 then
                scanAt = now
                local cp = S.checkpoint
                local scanning = S.shown and not S.suppressed and cp >= 0 and cp <= 4 and S.connecting and not S.terminal and not bar.failed and bar.frac == nil
                -- clear the previous scan marks
                if bar.scanG then
                    for _, k in ipairs({ bar.scanI, bar.scanI - 1 }) do
                        if k and k >= 0 and k < SEGS and seg[bar.scanG][k] == "" then ui:setClasses("#s" .. bar.scanG .. "_" .. k, "seg") end
                    end
                    bar.scanG = nil
                end
                if scanning then
                    local lit = 0
                    for i = 0, SEGS - 1 do if seg[cp][i] ~= "" then lit = i + 1 end end
                    if lit < SEGS then
                        bar.scan = (bar.scan + 1) % (SEGS - lit + 3)
                        local i = lit + bar.scan
                        if i < SEGS and seg[cp][i] == "" then ui:setClasses("#s" .. cp .. "_" .. i, "seg scan") end
                        if i - 1 >= lit and i - 1 < SEGS and seg[cp][i - 1] == "" then ui:setClasses("#s" .. cp .. "_" .. (i - 1), "seg scan2") end
                        bar.scanG, bar.scanI = cp, i
                    end
                end
            end
        end
    end)

    local function headline(first, second)
        if S.headline == first .. "|" .. second then return end
        S.headline = first .. "|" .. second
        ui:text("#h1a", first)
        ui:text("#h1b", second)
        ui:animate("#herocopy", { from = { opacity = 0, x = -26 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.5, bounce = 0.16 } })
    end

    local function phase(name, detail)
        if S.terminal then return end
        S.connecting, S.stage = true, name
        local entry = PHASES[name] or { math.max(S.checkpoint, 1), "Preparing session" }
        local reached = math.max(S.checkpoint, entry[1])
        local advanced = reached ~= S.checkpoint
        S.checkpoint = reached
        paintSteps(false)
        if advanced then
            ui:animate("#st" .. reached .. " .sbody", { from = { opacity = 0.4, y = 6 }, to = { opacity = 1, y = 0 }, spring = { duration = 0.4, bounce = 0.3 } })
        end
        ui:text("#phase", entry[2])
        local character = name == "creating_character"
        headline(character and "Make it" or "Next stop.", character and "yours." or "Night City.")
        ui:text("#statetext", "SESSION IN PROGRESS")
        ui:text("#signaltext", S.checkpoint == 4 and "LOADING WORLD" or S.checkpoint == 3 and "YOUR CHARACTER" or S.checkpoint == 2 and "PREPARING" or "CONNECTING")
        ui:text("#message", character and "Finish character creation to begin your story." or "Your next story is just a connection away.")
        ui:text("#nextstep", "We'll bring you in as soon as your world is ready.")
        ui:class("#root", "progress", true)
        ui:class("#cancel", "off", false)
        -- cancelling a live engine load cannot cancel LoadSavedGame: quit is offered instead
        ui:class("#cancel", "disabled", name == "world" or name == "creating_character")
        ui:text("#connstatus", name == "enrolling" and "VERIFYING" or "CONNECTING")
        ui:text("#progdetail", Privacy.text(clean(detail or "")))
        setView("loading", "phase:" .. tostring(name))
        paintTarget()
        applyFocus()
    end

    local function begin(value)
        S.failure, S.terminal, S.busy, S.resourceDiagnostic, S.server, S.activation = nil, false, false, nil, {}, nil
        ui:class("#root", "has-script", false)
        S.target = value.target or S.target
        S.attempt = value.attempt or (S.attempt + 1)
        S.started, S.checkpoint = now(), -1
        resetBar()
        ui:text("#elapsed", "ELAPSED 0s")
        ui:class("#diag", "open", false)
        S.detailsOpen = false
        ui:text("#toggletext", "Show details")
        ui:class("#actionerror", "on", false)
        ui:text("#copytext", "Copy report")
        phase(value.phase or "enrolling")
        progress(0, 0)
    end

    local function renderReport()
        if not S.failure then return end
        local f = S.failure.explanation
        local function proto(p) return (p.protocolMajor == nil or p.protocolMinor == nil) and "not provided" or (p.protocolMajor .. "." .. p.protocolMinor) end
        local t = S.target or {}
        local rows = {
            { "Reason", f.code }, { "Time (UTC)", S.failure.time }, { "Server", clean(t.name or "not provided") },
            { "Endpoint", clean(t.endpoint or S.server.endpoint or "not provided") }, { "Connection attempt", tostring(S.attempt) },
            { "Last checkpoint", PHASES[S.stage] and PHASES[S.stage][2] or S.stage },
            { "Client runtime", clean(S.client.version or "not provided") }, { "Client protocol", proto(S.client) },
            { "Server protocol", proto(S.server) }, { "Game build", clean(S.client.gameBuild or "not provided") },
        }
        for _, field in ipairs(f.fields) do rows[#rows + 1] = field end
        if f.owner and f.owner ~= "" then rows[#rows + 1] = { "For the server owner", f.owner } end
        local out, lines = {}, { f.message, f.action }
        for _, row in ipairs(rows) do
            out[#out + 1] = ('<div class="drow"><span class="dk">%s</span><span class="dv">%s</span></div>')
                :format(esc(row[1]), esc(Privacy.text(tostring(row[2]))))
            lines[#lines + 1] = row[1] .. ": " .. tostring(row[2])
        end
        ui:rml("#details", table.concat(out))
        local text = S.activation and f.code == "resource_activation_failed" and tostring(S.activation.text or "") or ""
        if text ~= "" then
            -- a code block: pasted in Discord or a ticket, the source window stays aligned
            table.insert(lines, 1, "```\n" .. text:sub(1, 6000):gsub("```", "` ` `") .. "\n```")
        end
        S.report = Privacy.text(table.concat(lines, "\n"))
    end

    local function renderScript()
        local r = S.activation and S.activation.report
        local on = S.failure ~= nil and S.failure.explanation.code == "resource_activation_failed" and type(r) == "table"
        ui:class("#root", "has-script", on)
        if not on then return end
        local f = S.failure.explanation
        ui:rml("#errtitle", ('<span class="res">%s</span> could not start'):format(esc(f.resource)))
        ui:text("#errchip", tostring(f.kind or ""):upper())
        ui:text("#errstage", "STAGE " .. clean(r.stage or ""):upper())
        local where = f.where or ""
        ui:rml("#errmsg", (where ~= "" and ('<span class="loc">%s</span>'):format(esc(where)) or "") .. esc(clean(r.message or "")))
        local source = type(r.source) == "table" and r.source or {}
        ui:class("#errcard", "nosrc", #source == 0)
        local file = tostring(r.file or "")
        local dir, base = file:match("^(.*/)([^/]+)$")
        local owner = tostring(r.fileResource or "")
        ui:rml("#errfile", ('<span class="dir">%s</span>%s'):format(esc((owner ~= "" and owner .. "/" or "") .. (dir or "")), esc(base or file)))
        local hot = tonumber(r.line) or 0
        local rows = {}
        for i = 1, math.min(#source, 15) do
            local row = source[i]
            local n = math.floor(tonumber(type(row) == "table" and row.n) or 0)
            local text = tostring(type(row) == "table" and row.t or ""):gsub("[%z\1-\31\127]", " "):sub(1, 220)
            rows[#rows + 1] = ('<div class="sl%s"><div class="mk"></div><div class="ln">%d</div><div class="tx">%s</div></div>')
                :format(n == hot and " hot" or "", n, text == "" and " " or esc(text))
        end
        ui:rml("#errsrc", table.concat(rows))
        local frames = type(r.frames) == "table" and r.frames or {}
        local out = {}
        for i = 1, math.min(#frames, 12) do
            local fr = frames[i]
            if type(fr) == "table" then
                local loc = (tostring(fr.resource or "") ~= "" and (fr.resource .. "/") or "") .. tostring(fr.file or "?") ..
                    ((tonumber(fr.line) or 0) > 0 and (":" .. math.floor(fr.line)) or "")
                out[#out + 1] = ('<div class="fr%s"><span class="fi">#%d</span>%s<span class="wh">%s</span></div>')
                    :format(i == 1 and " top" or "", i, esc(clean(loc)), esc(clean(fr.where or "")))
            end
        end
        if #out == 0 then out[1] = '<div class="fr"><span class="wh">No Lua stack: the host refused the resource before running it.</span></div>' end
        ui:rml("#errstack", table.concat(out))
        ui:text("#errplayer", f.action)
        ui:text("#errdev", "Developers: the same report is in the server console.")
    end

    local function utcNow()
        local ok, t = pcall(function() return Open77.time.utc and Open77.time.utc() end)
        if ok and t then return tostring(t) end
        return ("monotonic %.1fs"):format(now())
    end

    local function fail(reason)
        local f = U.explain(reason, S.resourceDiagnostic, S.activation)
        -- repeated teardown events keep the first failure, its time and the open details
        if S.failure then setView("failed", "failure_retained") return end
        S.failure = { explanation = f, time = utcNow() }
        S.terminal, S.connecting, S.busy = true, false, false
        S.headline = ""
        ui:text("#h1a", f.title .. ".")
        ui:text("#h1b", "")
        ui:text("#message", f.message)
        ui:text("#nextstep", f.action)
        ui:text("#statetext", "SESSION INTERRUPTED")
        ui:text("#signaltext", "ACTION REQUIRED")
        ui:class("#root", "progress", false)
        ui:class("#cancel", "off", true)
        ui:text("#connstatus", "DISCONNECTED")
        ui:text("#failurecode", f.code)
        ui:text("#elapsed", "CONNECTION STOPPED")
        ui:text("#phase", "Stopped at " .. (PHASES[S.stage] and PHASES[S.stage][2] or "the connection"))
        ui:text("#progdetail", f.code)
        paintSteps(true)
        paintTarget()
        renderReport()
        renderScript()
        setView("failed", "connection_failure")
        applyFocus()
        ui:animate("#herocopy", { from = { opacity = 0, x = -20 }, to = { opacity = 1, x = 0 }, spring = { duration = 0.45, bounce = 0.12 } })
    end

    local function idle(reason)
        S.terminal, S.connecting, S.busy = true, false, false
        local quit = reason == "user_quit"
        headline(quit and "Session" or "Connection", quit and "ended." or "cancelled.")
        ui:text("#statetext", "SESSION ENDED")
        ui:text("#signaltext", "STANDBY")
        ui:text("#message", "Return to the launcher to choose a server, or retry your last destination.")
        ui:text("#nextstep", "Your server selection and downloads are managed in the launcher.")
        ui:class("#root", "progress", false)
        ui:class("#cancel", "off", true)
        ui:text("#connstatus", "OFFLINE")
        ui:text("#elapsed", "NO ACTIVE SESSION")
        ui:text("#phase", "Standing by")
        ui:text("#progdetail", "Choose a server in the launcher.")
        setView("idle", "intentional_disconnect")
        paintTarget()
        applyFocus()
    end

    local function action(name, button)
        if S.busy then return end
        S.busy = true
        ui:class(button, "disabled", true)
        paintTarget()
        ui:class("#actionerror", "on", false)
        emit(name, {}, function(result)
            S.busy = false
            ui:class(button, "disabled", false)
            if type(result) ~= "table" or not result.accepted then
                ui:text("#actionerror", U.explain(type(result) == "table" and result.reason or "action_failed").message)
                ui:class("#actionerror", "on", true)
            end
            paintTarget()
        end)
    end

    -- ---- the radio ------------------------------------------------------------------------
    local function paintMusic()
        local level = math.floor(M.volume * 5 + 0.5)
        if M.volume > 0 and level == 0 then level = 1 end
        for b = 1, 5 do ui:class("#vb" .. b, "on", b <= level) end
        ui:attr("#musicicon", "d", M.enabled and ICON_PAUSE or ICON_PLAY)
        ui:class("#music", "playing", M.playing and M.volume > 0 and M.visible)
        ui:text("#musicstatus", M.error and "Audio unavailable" or not M.enabled and "Paused" or M.volume == 0 and "Muted"
            or not M.ready and "Loading preferences" or not M.playing and "Standby" or "Playing - looping")
    end
    local function musicSync()
        local want = M.visible and M.ready and M.enabled and S.view ~= "notice" and S.shown and not S.suppressed
        if want and not M.sound and not M.error then
            local id, reason = Play2DSound("audio/lobby.mp3", { loop = true, volume = M.volume, paused = true })
            if id then M.sound = id else M.error = tostring(reason); print("Open77 shell: lobby music unavailable: " .. tostring(reason)) end
        end
        if M.sound then
            pcall(SetSoundVolume, M.sound, M.volume)
            if want and not M.playing then
                if pcall(PlaySound, M.sound) then M.playing = true end
                emit("music:playback", { playing = true, volume = M.volume })
            elseif not want and M.playing then
                pcall(PauseSound, M.sound)
                M.playing = false
                emit("music:playback", { playing = false, volume = M.volume })
            end
        end
        paintMusic()
    end
    local saveToken = 0
    local function musicSave(delay)
        saveToken = saveToken + 1
        local token = saveToken
        SetTimeout(delay or 0, function()
            if token ~= saveToken or not alive then return end
            emit("music:preferences", { enabled = M.enabled, volume = M.volume }, function(result)
                if type(result) ~= "table" or not result.accepted then
                    ui:text("#musicstatus", "Settings could not be saved. This session keeps your choice.")
                end
            end)
        end)
    end

    -- ---- input lease ----------------------------------------------------------------------
    -- The controller drops the input when the cover goes up (the world must keep its keys).
    -- While the connection itself runs (identity, handshake, downloads) nothing else wants
    -- the mouse, and Cancel / Back to launcher are on screen: the cursor stays, the keyboard
    -- does not. It goes when the world starts streaming, or the character creator opens.
    local wanted = { keyboard = false, cursor = false }
    local leased = nil
    local presented = false
    applyFocus = function()
        local mode
        if presented and (wanted.keyboard or wanted.cursor) then
            mode = (wanted.keyboard and "k" or "") .. (wanted.cursor and "c" or "")
        elseif presented and S.view == "loading" and S.connecting and S.stage ~= "world" and S.stage ~= "creating_character" then
            mode = "c"
        end
        if mode == leased then return end
        leased = mode
        if mode then
            ui:focus({ keyboard = mode:find("k", 1, true) ~= nil, cursor = mode:find("c", 1, true) ~= nil })
            if mode:find("k", 1, true) then ui:focusElement("#root") end
        else
            ui:blur()
        end
    end

    -- ---- the game's own music ----------------------------------------------------------------
    -- The game's menu music would play under this screen and its radio. While the screen is
    -- shown (or a server's own loadscreen stands in for it), the game's Music volume is held
    -- at 0 and given back the moment the screen goes. The value to give back is kept in KVP
    -- first: a crash under the screen is repaired at the next start.
    local MUSIC_GROUP, MUSIC_NAME, MUSIC_KEY = "/audio/volume", "MusicVolume", "shell:music-restore"
    local duck = { active = false, original = nil }
    -- The game's own UserSettings, through the RTTI bridge: unlike the script-bridge settings it
    -- answers in the pre-game menu, where the menu music plays.
    local function musicVar(fn)
        local rtti = type(Open77.rtti) == "table" and Open77.rtti or nil
        if not rtti then return nil, "rtti_unavailable" end
        local gi, why = rtti.gameInstance()
        if not gi then return nil, why end
        local settings, settingsWhy = rtti.call("ScriptGameInstance", "GetSettingsSystem", nil, gi)
        if not settings then pcall(rtti.release, gi); return nil, settingsWhy or "no_settings_system" end
        local var, varWhy = rtti.call("UserSettings", "GetVar", settings, MUSIC_GROUP, MUSIC_NAME)
        local result, reason
        if var then
            local ok, a, b = pcall(fn, rtti, var)
            if ok then result, reason = a, b else reason = tostring(a) end
            pcall(rtti.release, var)
        else
            reason = varWhy or "no_music_var"
        end
        pcall(rtti.release, settings)
        pcall(rtti.release, gi)
        return result, reason
    end
    local function readMusic()
        return musicVar(function(rtti, var)
            local value, why = rtti.call("ConfigVarInt", "GetValue", var)
            if value == nil then value, why = rtti.call("ConfigVarFloat", "GetValue", var) end
            return tonumber(value), why
        end)
    end
    local function writeMusic(value)
        return musicVar(function(rtti, var)
            local _, why = rtti.call("ConfigVarInt", "SetValue", var, math.floor(value))
            if why then _, why = rtti.call("ConfigVarFloat", "SetValue", var, value + 0.0) end
            return why == nil, why
        end)
    end
    local function restoreMusic(value)
        if not value then return end
        local ok, why = writeMusic(value)
        pcall(Open77.kvp.set, MUSIC_KEY, "")
        print(("Open77 shell: the game's music given back (%d)%s"):format(math.floor(value), ok and "" or (" failed: " .. tostring(why))))
    end
    local function setDuck(on)
        if on == duck.active then return end
        duck.active = on
        if not on then
            if duck.original then restoreMusic(duck.original) end
            duck.original = nil
            return
        end
        CreateThread(function()
            local found, why = readMusic()
            if not duck.active or duck.original then return end
            if not found then print("Open77 shell: the game's music volume could not be read: " .. tostring(why)) return end
            if found <= 0 then return end
            duck.original = found
            pcall(Open77.kvp.set, MUSIC_KEY, tostring(found))
            local ok, setWhy = writeMusic(0)
            print(("Open77 shell: the game's music held at 0 under the screen (was %d)%s"):format(found, ok and "" or (" failed: " .. tostring(setWhy))))
        end)
    end
    U.musicDuck = duck
    -- a previous run that ended under the screen left the music at 0: give it back
    do
        local ok, stored = pcall(Open77.kvp.get, MUSIC_KEY, "")
        local value = ok and tonumber(stored)
        if value and value > 0 then restoreMusic(value) end
    end

    -- ---- show / hide ----------------------------------------------------------------------
    local function present()
        local want = S.shown and not S.suppressed
        if want == presented then return end
        presented = want
        if want then
            ui:show()
            ui:stop("#root")
            ui:animate("#root", { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.28, easing = "out" })
            if S.view ~= "notice" then
                if introState == "pending" then playIntro() else assemble() end
            end
        else
            ui:hide()
        end
        applyFocus()
        musicSync()
        setDuck(S.shown and S.view ~= "notice")
    end

    -- ---- the artworks ---------------------------------------------------------------------
    -- One artwork at a time, each slowly pushing in while it is shown, then a 1.8 s cross-fade
    -- to the next. Runs only while the screen is presented (nothing animates when hidden).
    local ART_COUNT, ART_HOLD = 4, 8000
    local art = math.random(1, 4)
    local slideshowGeneration = 0
    local function pushIn(index)
        ui:stop("#art" .. index)
        ui:animate("#art" .. index, { from = { scale = 1.0, x = 0 },
                                      to = { scale = 1.08, x = (index % 2 == 0) and -12 or 12 }, duration = (ART_HOLD + 2000) / 1000, easing = "linear" })
    end
    startSlideshow = function()
        slideshowGeneration = slideshowGeneration + 1
        local generation = slideshowGeneration
        for i = 1, ART_COUNT do ui:class("#art" .. i, "on", i == art) end
        pushIn(art)
        CreateThread(function()
            while alive and generation == slideshowGeneration do
                Wait(ART_HOLD)
                if not alive or generation ~= slideshowGeneration then return end
                if presented and S.view ~= "notice" and introState ~= "playing" then
                    local previous = art
                    art = art % ART_COUNT + 1
                    pushIn(art)
                    ui:animate("#art" .. art, { from = { opacity = 0 }, to = { opacity = 1 }, duration = 1.8, easing = "ease-in-out" })
                    ui:animate("#art" .. previous, { to = { opacity = 0 }, duration = 1.8, easing = "ease-in-out" })
                end
            end
        end)
    end

    -- ---- depth and float -------------------------------------------------------------------
    -- The blocks stand in space: the destination turns toward the centre, the headline leans
    -- the other way, the rail tilts back. Each one breathes on its own slow rhythm (rotation
    -- and height), so the screen never sits still. Motion channels, no relayout.
    startFloat = function()
        local function float(sel, persp, channel, a, b, period, yAmp, yPeriod)
            ui:keyframes(sel, { channel = "perspective", stops = { { offset = 0, value = persp }, { offset = 1, value = persp } }, duration = 1, iterations = -1 })
            ui:keyframes(sel, { channel = channel, stops = { { offset = 0, value = a, easing = "ease-in-out" }, { offset = 1, value = b } },
                                duration = period, iterations = -1, alternate = true })
            if yAmp then
                ui:keyframes(sel, { channel = "y", stops = { { offset = 0, value = -yAmp, easing = "ease-in-out" }, { offset = 1, value = yAmp } },
                                    duration = yPeriod, iterations = -1, alternate = true })
            end
        end
        float("#aside", 1400, "rotateY", -9, -15, 5.2, 7, 3.6)
        float("#hero", 1600, "rotateY", 5, 9, 6.4, 5, 4.4)
        float("#rail", 1800, "rotateX", 4, 8, 4.8)
    end

    -- ---- the headline glitch ---------------------------------------------------------------
    -- Every few seconds one line of the headline (sometimes both) tears for a fraction of a
    -- second: a horizontal jump, a skew and a chromatic split, then it snaps back.
    local function glitchLine(sel, strength)
        ui:class(sel, "glitch", true)
        ui:keyframes(sel, { channel = "x", stops = { { offset = 0, value = 0 }, { offset = 0.2, value = -9 * strength },
            { offset = 0.4, value = 7 * strength }, { offset = 0.6, value = -4 * strength }, { offset = 0.8, value = 2 * strength },
            { offset = 1, value = 0 } }, duration = 0.28, iterations = 1 })
        ui:keyframes(sel, { channel = "skewX", stops = { { offset = 0, value = 0 }, { offset = 0.3, value = -9 * strength },
            { offset = 0.6, value = 5 * strength }, { offset = 1, value = 0 } }, duration = 0.28, iterations = 1 })
        SetTimeout(290, function() if alive then ui:class(sel, "glitch", false) end end)
    end
    CreateThread(function()
        while alive do
            Wait(math.random(3500, 7000))
            if presented and S.view ~= "notice" and introState ~= "playing" then
                local pick = math.random(1, 3)
                local strength = 0.7 + math.random() * 0.6
                if pick ~= 2 then glitchLine("#h1a", strength) end
                if pick ~= 1 then glitchLine("#h1b", strength) end
                if math.random(1, 3) == 1 then
                    Wait(380)
                    if alive and presented then glitchLine(pick == 1 and "#h1a" or "#h1b", strength * 0.6) end
                end
            end
        end
    end)

    -- ---- the intro ------------------------------------------------------------------------
    -- Once per client run, the first time the screen is presented: OPEN//77 lands over the
    -- artwork the slideshow starts on, like a game's title card, then the screen assembles.
    -- A click or a key skips it.
    introState = "pending" -- pending | playing | done
    local introToken = 0
    -- The screen assembling: each block arrives on its own beat, so the eye follows the
    -- story -- brand, the headline, where you are going, how you get there.
    assemble = function()
        local spring = function(d, b) return { duration = d, bounce = b } end
        ui:animate("#mast", { from = { opacity = 0, y = -26 }, to = { opacity = 1, y = 0 }, spring = spring(0.55, 0.18) })
        ui:animate("#wordmark", { from = { opacity = 0, x = -50 }, to = { opacity = 1, x = 0 }, spring = spring(0.6, 0.22), delay = 0.05 })
        ui:animate("#statelabel, #signal", { from = { opacity = 0, x = -24 }, to = { opacity = 1, x = 0 }, spring = spring(0.5, 0.2), delay = 0.1, stagger = 0.06 })
        ui:animate("#h1a", { from = { opacity = 0, x = -110 }, to = { opacity = 1, x = 0 }, spring = spring(0.7, 0.22), delay = 0.14 })
        ui:animate("#h1b", { from = { opacity = 0, x = -150 }, to = { opacity = 1, x = 0 }, spring = spring(0.75, 0.24), delay = 0.22 })
        ui:animate("#message, #nextstep, #herobottom", { from = { opacity = 0, y = 18 }, to = { opacity = 1, y = 0 }, spring = spring(0.55, 0.12), delay = 0.36, stagger = 0.07 })
        ui:animate("#dest", { from = { opacity = 0, x = 90 }, to = { opacity = 1, x = 0 }, spring = spring(0.65, 0.2), delay = 0.24 })
        ui:animate("#dest-edge", { from = { scaleX = 0 }, to = { scaleX = 1 }, duration = 0.7, easing = "emphasized", delay = 0.5 })
        ui:animate("#controls > *", { from = { opacity = 0, x = 70 }, to = { opacity = 1, x = 0 }, spring = spring(0.6, 0.22), delay = 0.4, stagger = 0.06 })
        ui:animate("#rail", { from = { opacity = 0, x = -60 }, to = { opacity = 1, x = 0 }, spring = spring(0.65, 0.2), delay = 0.42 })
        ui:animate("#bar > .grp", { from = { opacity = 0, scaleY = 0.2 }, to = { opacity = 1, scaleY = 1 }, spring = spring(0.55, 0.5), delay = 0.56, stagger = 0.07 })
        ui:animate("#labels > .lab", { from = { opacity = 0, y = 16 }, to = { opacity = 1, y = 0 }, spring = spring(0.55, 0.28), delay = 0.62, stagger = 0.07 })
        ui:animate("#foot", { from = { opacity = 0, y = 26 }, to = { opacity = 1, y = 0 }, spring = spring(0.6, 0.14), delay = 0.62 })
    end
    local function finishIntro(fast)
        if introState ~= "playing" then return end
        introState = "done"
        introToken = introToken + 1
        local token = introToken
        local function later(ms, fn) SetTimeout(ms, function() if token == introToken and alive then fn() end end) end
        local function reveal(fade)
            ui:class("#root", "intro-ui", false)
            startSlideshow() -- the screen opens on the intro's artwork, with a full hold before the next
            assemble()
            ui:animate("#intro", { to = { opacity = 0, scale = 1.04 }, duration = fade, easing = "ease-in-out" })
            later(math.floor(fade * 1000) + 60, function()
                ui:class("#root", "intro", false)
                for _, sel in ipairs({ "#intro", "#intro-mark", "#intro-ghost-p", "#intro-ghost-b", "#intro-art", "#intro-flash",
                                       "#intro-corner-tl", "#intro-corner-br", "#intro-bar" }) do
                    ui:stop(sel)
                end
                ui:style("#intro", "opacity", "1")
            end)
        end
        -- a cross-fade: the screen assembles under the intro while the intro dissolves over it
        reveal(fast and 0.3 or 0.9)
    end
    playIntro = function()
        introState = "playing"
        introToken = introToken + 1
        local token = introToken
        local function at(ms, fn) SetTimeout(ms, function() if token == introToken and introState == "playing" and alive then fn() end end) end
        ui:style("#intro-art", "decorator", ("image(/ui/art/art%d.jpg cover center)"):format(art))
        ui:class("#root", "intro", true)
        ui:class("#root", "intro-ui", true)
        ui:animate("#intro-art", { from = { opacity = 0, scale = 1.18 }, to = { opacity = 1, scale = 1.0 }, duration = 4.6, easing = "out" })
        ui:animate("#intro-grid", { from = { opacity = 0 }, to = { opacity = 0.5 }, duration = 1.2 })
        at(250, function()
            ui:animate("#intro-corner-tl", { from = { opacity = 0, x = -30, y = -30 }, to = { opacity = 1, x = 0, y = 0 }, spring = { duration = 0.5, bounce = 0.3 } })
            ui:animate("#intro-corner-br", { from = { opacity = 0, x = 30, y = 30 }, to = { opacity = 1, x = 0, y = 0 }, spring = { duration = 0.5, bounce = 0.3 } })
        end)
        at(650, function()
            -- the mark slams in; its pink and blue ghosts converge onto it
            ui:animate("#intro-mark", { from = { opacity = 0, scale = 1.7 }, to = { opacity = 1, scale = 1.0 }, spring = { duration = 0.5, bounce = 0.32 } })
            ui:animate("#intro-ghost-p", { from = { opacity = 0.9, x = -46, scale = 1.25 }, to = { opacity = 0, x = 0, scale = 1.0 }, duration = 0.55, easing = "out" })
            ui:animate("#intro-ghost-b", { from = { opacity = 0.9, x = 46, scale = 1.25 }, to = { opacity = 0, x = 0, scale = 1.0 }, duration = 0.55, easing = "out" })
        end)
        at(980, function()
            ui:animate("#intro-flash", { from = { opacity = 0.55 }, to = { opacity = 0 }, duration = 0.45, easing = "out" })
            ui:animate("#intro-fill", { from = { width = "0%" }, to = { width = "100%" }, duration = 1.6, easing = "emphasized" })
        end)
        -- the mark tears: a jump, a skew and a chromatic split, its ghosts splitting
        local function tear(strength)
            ui:class("#intro-mark", "glitch", true)
            ui:keyframes("#intro-mark", { channel = "x", stops = { { offset = 0, value = 0 }, { offset = 0.15, value = -12 * strength }, { offset = 0.3, value = 9 * strength },
                { offset = 0.45, value = -5 * strength }, { offset = 0.6, value = 2 * strength }, { offset = 1, value = 0 } }, duration = 0.3, iterations = 1 })
            ui:keyframes("#intro-mark", { channel = "skewX", stops = { { offset = 0, value = 0 }, { offset = 0.3, value = -10 * strength },
                { offset = 0.6, value = 6 * strength }, { offset = 1, value = 0 } }, duration = 0.3, iterations = 1 })
            for _, g in ipairs({ { "#intro-ghost-p", -16 }, { "#intro-ghost-b", 16 } }) do
                ui:keyframes(g[1], { channel = "opacity", stops = { { offset = 0, value = 0.85 }, { offset = 0.5, value = 0.5 }, { offset = 1, value = 0 } }, duration = 0.3, iterations = 1 })
                ui:keyframes(g[1], { channel = "x", stops = { { offset = 0, value = g[2] * strength }, { offset = 0.5, value = -g[2] * 0.4 * strength }, { offset = 1, value = 0 } }, duration = 0.3, iterations = 1 })
            end
            SetTimeout(300, function() if alive then ui:class("#intro-mark", "glitch", false) end end)
        end
        at(1650, function() tear(1.0) end)
        at(2350, function() tear(0.55) end)
        at(3050, function() tear(0.8) end)
        at(3500, function() finishIntro(false) end)
    end
    ui:on("click", function() if introState == "playing" then finishIntro(true) end end)
    ui:on("keydown", function() if introState == "playing" then finishIntro(true) end end)

    -- ---- input --------------------------------------------------------------------------
    ui:on("click", ".act", function(e)
        local id = tostring(e.id or "")
        if id == "retry" then if not S.connecting and S.target and S.target.endpoint then action("connection:retry", "#retry") end
        elseif id == "cancel" then action("connection:cancel", "#cancel")
        elseif id == "launcher" then action("shell:launcher", "#launcher")
        elseif id == "quit" then action("shell:quit", "#quit")
        elseif id == "privacy" then emit("privacy:set", { visible = not Privacy.visible })
        elseif id == "toggledetails" then
            S.detailsOpen = not S.detailsOpen
            ui:class("#diag", "open", S.detailsOpen)
            ui:text("#toggletext", S.detailsOpen and "Hide details" or "Show details")
        elseif id == "copy" then
            local ok = Open77.clipboard and Open77.clipboard.setText and Open77.clipboard.setText(S.report)
            ui:text("#copytext", ok and "Copied" or "Copy failed")
            if not ok and not S.detailsOpen then
                S.detailsOpen = true
                ui:class("#diag", "open", true)
                ui:text("#toggletext", "Hide details")
            end
        elseif id:match("^vb%d$") then
            setVolumeBar(tonumber(id:sub(3)))
        elseif id == "musictoggle" then
            M.enabled = not M.enabled
            musicSync()
            musicSave(0)
        end
    end)
    -- a volume bar: its level (20% steps); the lit top bar clicked again steps down one
    setVolumeBar = function(b)
        local current = math.floor(M.volume * 5 + 0.5)
        local level = (b == current) and (b - 1) or b
        M.volume = level / 5
        if M.sound then pcall(SetSoundVolume, M.sound, M.volume) end
        musicSync()
        ui:animate("#vb" .. b, { from = { scaleY = 0.6 }, to = { scaleY = 1 }, spring = { duration = 0.35, bounce = 0.55 } })
        musicSave(200)
    end
    ui:on("mouseup", function() ui:focusElement("#root") end)

    ui:onEvent("loaded", function()
        paintTarget()
        paintMusic()
        startSlideshow()
        ui:keyframes("#bg-sweep", { channel = "y", stops = { { offset = 0, value = -200 }, { offset = 1, value = 1100 } }, duration = 9, iterations = -1 })
        startFloat()
        emit("shell:ready", {})
    end)
    ui:onEvent("reloaded", function()
        local view = S.view
        S.view, S.headline = nil, ""
        setView(view, "reloaded")
        for g = 0, 4 do for i = 0, SEGS - 1 do seg[g][i] = "x" end end
        paintSteps(S.failure ~= nil)
        startFloat()
        paintTarget()
        paintMusic()
        ui:class("#root", "progress", S.connecting and not S.terminal)
        ui:class("#cancel", "off", not S.connecting)
        ui:class("#root", "addresses", Privacy.visible)
        if S.failure then
            local f = S.failure.explanation
            ui:text("#h1a", f.title .. "."); ui:text("#h1b", ""); ui:text("#message", f.message); ui:text("#nextstep", f.action)
            ui:text("#failurecode", f.code)
            renderReport()
        end
        emit("shell:ready", {}) -- the controller replays the state and the last connection event
    end)
    ui:onEvent("error", function(name, detail)
        print("Open77 shell (native): " .. tostring(name) .. ": " .. tostring(detail and detail.message))
    end)

    -- elapsed time while a connection runs
    CreateThread(function()
        while alive do
            Wait(1000)
            if S.connecting and S.started and not S.terminal then
                ui:text("#elapsed", "ELAPSED " .. math.floor(now() - S.started) .. "s")
            end
        end
    end)

    -- ---- the page API -------------------------------------------------------------------
    function page.on(_, name, fn) page.handlers[name] = fn end
    function page.reply(_, request, payload)
        local fn = request and requests[request]
        if not fn then return end
        requests[request] = nil
        fn(payload)
    end
    function page.show()
        S.shown = true
        present()
        return true
    end
    function page.hide()
        S.shown = false
        present()
        return true
    end
    function page.setFocus(_, keyboard, cursor)
        wanted.keyboard, wanted.cursor = keyboard == true, cursor == true
        applyFocus()
        return true
    end
    --- A server's own (WebUI) loading screen is up: it must be seen, and NativeUI draws
    --- above WebUI, so this screen steps aside -- after a beat, so the page has painted.
    function page.suppress(_, on)
        on = on == true
        if on == S.suppressed then return end
        S.suppressed = on
        if on then
            SetTimeout(700, function()
                if S.suppressed and alive then
                    ui:animate("#root", { to = { opacity = 0 }, duration = 0.3, easing = "ease-in" })
                    SetTimeout(320, function() if S.suppressed and alive then present() end end)
                end
            end)
        else
            present()
        end
    end
    function page.destroy()
        setDuck(false)
        alive = false
        if M.sound then pcall(DestroySound, M.sound) end
        pcall(ui.destroy, ui)
    end

    function page.send(_, name, payload)
        payload = type(payload) == "table" and payload or {}
        if name == "shell:state" then
            S.client = type(payload.client) == "table" and payload.client or S.client
            S.target = payload.target or S.target
            ui:text("#build", S.client.version and clean(S.client.version) or "")
            paintTarget()
            renderReport()
        elseif name == "connection:begin" then begin(payload)
        elseif name == "shell:actionError" then
            ui:text("#actionerror", U.explain(payload.reason or "action_failed").message)
            ui:class("#actionerror", "on", true)
        elseif name == "connection:update" then
            if type(payload.serverProfile) == "table" then S.server = payload.serverProfile end
            if payload.endpoint then
                S.target = S.target or {}
                S.target.endpoint = payload.endpoint
                S.target.name = payload.server or payload.endpoint
            end
            local p = tostring(payload.phase or "")
            if p == "failed" or p == "rejected" or p == "offline" or p == "disconnecting" or p == "unknown" then
                fail(payload.reason or "server_disconnected")
                return true
            end
            phase(p, payload.detail or "")
            progress(0, 0)
        elseif name == "resources:loading" then
            if S.terminal then return true end
            if payload.diagnostic then S.resourceDiagnostic = payload.diagnostic end
            if payload.phase == "failed" then fail(payload.message or "resource_download_failed") return true end
            local function mb(n) return ("%.1f MB"):format((tonumber(n) or 0) / 1048576) end
            local parts = {}
            if payload.resource and payload.resource ~= "" then parts[#parts + 1] = tostring(payload.resource) end
            if tonumber(payload.totalFiles) and tonumber(payload.totalFiles) > 0 then parts[#parts + 1] = tostring(payload.completedFiles or 0) .. "/" .. tostring(payload.totalFiles) .. " files" end
            if tonumber(payload.total) and tonumber(payload.total) > 0 then parts[#parts + 1] = mb(payload.received) .. " / " .. mb(payload.total) end
            phase(payload.phase, table.concat(parts, " - "))
            progress(payload.received, payload.total)
        elseif name == "resources:activationFailed" then
            if type(payload.report) ~= "table" then return true end
            S.activation = { report = payload.report, text = tostring(payload.text or "") }
            -- the disconnect normally follows; if it already arrived, upgrade the screen in place
            if S.failure and S.failure.explanation.code == "resource_activation_failed" then
                S.failure.explanation = U.explain("resource_activation_failed", nil, S.activation)
                local f = S.failure.explanation
                ui:text("#h1a", f.title .. ".")
                ui:text("#message", f.message)
                ui:text("#nextstep", f.action)
                renderReport()
                renderScript()
            end
        elseif name == "world:loading:begin" then
            phase("world", "Streaming the world")
            progress(0, 0)
        elseif name == "world:loading" then
            if not S.terminal then phase("world", "Streaming the world"); progress(payload.progress, 1) end
        elseif name == "session:ended" then
            local reason = payload.reason or "server_disconnected"
            if S.failure then setView("failed", "session_ended_preserves_error") return true end
            if reason == "user_quit" or reason == "connection_cancelled" or reason == "client_disconnect" then idle(reason) else fail(reason) end
        elseif name == "shell:cover" then
            if not S.terminal then setView("loading", "shell_cover") end
            paintTarget()
        elseif name == "shell:reveal" then
            if S.failure then setView("failed", "shell_reveal_preserves_error") return true end
            if not S.connecting then setView("idle", "shell_reveal") end
            paintTarget()
        elseif name == "shell:notice" then
            ui:text("#noticemessage", clean(payload.message or "Your session ended while creating a character."))
            setView("notice", "creator_orphaned")
            musicSync()
            setDuck(false)
        elseif name == "loading:theme" then
            -- no server-controlled markup or assets: a strap line and an accent colour
            if payload.strap and not S.terminal then ui:text("#footstatus", clean(payload.strap)) end
            if type(payload.accent) == "string" and payload.accent:match("^#%x%x%x%x%x%x$") then
                local a = payload.accent
                ui:stylesheet("accent", (".seg.on .segfill { background-color: %s; box-shadow: %s80 0 0 10dp 0; } .seg.on { border-color: %s; } "
                    .. ".seg.scan .segfill { background-color: %s59; } #percent, #pctsign, #rail-edge { color: %s; } #rail-edge { background-color: %s; } "
                    .. ".lab.current .snum, .lab.current .sname { color: %s; }"):format(a, a, a, a, a, a, a))
            end
        elseif name == "privacy:state" then
            Privacy.visible = payload.visible == true
            ui:class("#root", "addresses", Privacy.visible)
            paintTarget()
            renderReport()
        elseif name == "music:preferences" then
            M.enabled = payload.enabled ~= false
            M.volume = type(payload.volume) == "number" and payload.volume == payload.volume and clamp(payload.volume, 0, 1) or 0.12
            M.ready = true
            musicSync()
        elseif name == "music:visibility" then
            M.visible = payload.visible == true
            musicSync()
        end
        return true
    end

    return page
end
