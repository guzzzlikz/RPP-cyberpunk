resource "open77_quickhack"
version "0.1.0"
open77_version ">=0.0.1"
auto_start false
reload_policy "reconnect"

-- Shipped with every server, off until used: a resource that declares
-- `dependency "open77_quickhack"` starts it (or `ensure open77_quickhack`).
-- Scanner + quickhack interface on NativeUI (README.md). Server developers register the
-- quickhacks and the targets; this resource owns the experience and the server rules.
shared_scripts { "shared/config.lua", "shared/presets.lua" }
server_scripts { "server/main.lua", "server/examples.lua" }
client_scripts { "client/ui.lua", "client/main.lua" }

files { "ui/quickhack.rml", "ui/quickhack.rcss", "ui/icons/*.png" }

permissions {
    "network.events",
    "input.actions",       -- key mappings; while scanning: no firing, melee, grenade or weapon change
    "player.aim.read",     -- what the crosshair is on
    "world.query",
    "world.effects",       -- scanner vision (focus mode + outlines) and the game's UI sounds
    "npcs.read",           -- client: NPCs on screen (pick, 1 / 3)
    "world.npcs",          -- server: required by npcs.presence (quickhack creates no NPC)
    "npcs.foreign",        -- server: where another resource's NPC is (range checks, Ping)
    "vehicles.read",       -- client: vehicles on screen (pick, tracking)
    "world.vehicles",      -- server: vehicle reads (range checks, Ping); quickhack changes no vehicle
}
