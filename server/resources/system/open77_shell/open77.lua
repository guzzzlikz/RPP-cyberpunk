resource "open77_shell"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "local"

-- The screen on NativeUI (ui/), then the controller that drives it.
client_script "client/ui.lua"
client_script "client/main.lua"
files { "ui/shell.rml", "ui/shell.rcss", "ui/art/*.jpg", "ui/fonts/*.ttf", "audio/lobby.mp3" }
-- screen.read: the first-placement hold watches the native loading cycle a far
-- spawn teleport opens, so the cover outlasts it (client/main.lua).
-- webui.system: a server's own loadscreen is still a WebUI page; ui.system: this screen;
-- audio.play: the lobby radio; clipboard.write: "Copy report"; rtti.native: the game's music
-- volume is held at 0 under the screen (UserSettings), then given back.
permissions { "webui.system", "ui.system", "network.client", "screen.read", "audio.play", "clipboard.write", "rtti.native" }
