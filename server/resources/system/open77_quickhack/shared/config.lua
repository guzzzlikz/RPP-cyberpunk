-- open77_quickhack: shared configuration (client and server read the same table).
-- Server owners: copy a value here to change a default for every player. Per-player decks and
-- per-target data come from your own resource through the exports (README.md).
QuickhackConfig = {
    -- Every player gets this deck on join unless a resource sets one.
    deck = {
        ram = 19,           -- current RAM
        maxRam = 19,        -- capacity (segments of the RAM bar)
        regen = 0.6,        -- RAM per second
        slots = {},         -- quickhack ids offered by default; empty = every registered quickhack
    },
    -- Which kinds become targets without a resource adding them one by one.
    -- Players, the server's network NPCs (any resource's) and vehicles. Crowd NPCs and parked
    -- traffic the engine owns have no network identity and are never targets.
    autoTargets = { player = true, npc = true, vehicle = true },
    -- The bundled example quickhacks: one "Ping" per entity kind (server/examples.lua). They show
    -- how a custom quickhack is built; turn them off here or with exports.open77_quickhack:setExamplesEnabled(false).
    examples = true,
    -- Scanner reach in metres (looking at something further away does not lock it).
    scanRange = 60,
    -- Seconds the scan of a newly locked target takes before its data shows.
    scanSeconds = 0.55,
    -- Extra metres granted on server range checks (latency, movement during the upload).
    rangeTolerance = 4,
    -- Keys (players can rebind them in the key settings).
    keys = {
        scanner = "TAB", execute = "F", prev = "1", next = "3",
        up = "UP", down = "DOWN", tab = "Z", help = "H",
    },
    -- Scanner vision: "native" (the engine's focus vision with bodies outlined through walls),
    -- "tint" (the HUD re-colours the screen), "none".
    vision = "native",
    visionRadius = 40,
    visionMaxTargets = 24,   -- bodies outlined at once (each one costs a highlight pass)
    -- The game's own UI sound events. Set one to false to silence it.
    sounds = {
        open = "ui_focus_mode_zooming_in_enter",
        openLoop = "ui_focus_mode_loop_start",
        close = "ui_focus_mode_zooming_in_exit",
        closeLoop = "ui_focus_mode_loop_stop",
        scanStart = "ui_focus_mode_scanning_loop_start",
        scanStop = "ui_focus_mode_scanning_loop_stop",
        scanDone = "ui_focus_mode_scanning_done",
        menuOpen = "ui_focus_mode_qh_loop_start",
        menuClose = "ui_focus_mode_qh_loop_stop",
        hover = "ui_hacking_qh_hover",
        targetChange = "ui_focus_mode_zooming_in_step_change",
        tab = "ui_menu_hover",
        execute = "ui_hacking_press",
        refused = "ui_hacking_press_fail",
        uploadLoop = "ui_focus_mode_scanning_qh",
        uploadStop = "ui_focus_mode_scanning_qh_stop",
        uploadDone = "ui_focus_mode_scanning_qh_done",
        granted = "ui_hacking_access_granted",
        denied = "ui_hacking_access_denied",
        incoming = "ui_hacking_loop_start",
        incomingStop = "ui_hacking_loop_stop",
        tagOn = "ui_focus_mode_scanning_tag_on",
    },
    -- Cosmetic strings of the frame (the game prints the optics vendor).
    vendor = "KIROSHI",
    debugAnchors = false,    -- log anchors, picks, refusals and action blocks (development)
    deckName = "CYBERDECK V.552 322",
}
