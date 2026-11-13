resource "open77_pause"
version "0.6.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "local"

-- The string table first: it declares the global `PauseStrings` that
-- client/main.lua reads and forwards to the page. Shared scripts are
-- prepended to the client list by the resource host, so the order is not a
-- convention here, it is the load order.
shared_script "shared/strings.lua"
client_script "client/voice_setup.lua"
client_script "client/web_audio.lua"
-- The menu on NativeUI: its icons, then the surface main.lua drives.
client_script "client/icons.lua"
client_script "client/ui.lua"
client_script "client/main.lua"
files { "assets/**", "ui/pause.rml", "ui/pause.rcss", "ui/open77-wordmark.png", "ui/open77-yellow.rcss", "ui/fonts/Play-Bold.ttf" }
-- network.client is read-only here in practice: the pause menu polls the
-- session snapshot for its info card and calls disconnect() for Quit Session.
permissions {
    "webui.system", "ui.system", "network.client", "network.events", "local.events",
    "voice.client", "input.actions", "map.read", "map.control"
}
