-- A complete character creator, in game, on the runtime body API (Open77.body). The game's own
-- creator catalogue (faces, hair, eyes, makeup, tattoos, piercings, cyberware, body), its
-- thumbnails, live preview on the player, a camera per category, and a persistent result through
-- open77_appearance. With open77_appearance_creation "runtime", new characters skip the menu
-- creator, spawn in the world and get this one. See README.md.
resource "open77_creator"
version "1.1.1"
open77_version ">=0.0.1"
auto_start false
reload_policy "reconnect"

dependency "open77_appearance >=0.5.0"

shared_scripts { "shared/config.lua", "shared/locale.lua", "shared/thumbs.lua" }
server_script "server/main.lua"
client_scripts { "client/effects.lua", "client/main.lua" }

files { "ui/creator.rml", "ui/open77-yellow.rcss", "ui/creator.rcss", "ui/thumbs/*.png", "ui/looks/*.png" }

permissions {
    "network.events",
    "player.body.switch",  -- catalog / compose / decompose / active / switch
    "camera.script",       -- the creator's camera shots
    "player.freeze",       -- the player stands still while the creator is open
    "world.transform",     -- the player's frame, to place the camera
    "ui.vanilla.hud",      -- hides the game HUD and its notifications while the creator is open
    "world.effects",       -- the game's own UI sounds on hover and press (Open77.sfx.play2d)
    "database.access",     -- server: the creator choices (open77_creator_looks)
}
