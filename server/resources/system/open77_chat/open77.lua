resource "open77_chat"
version "0.6.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "local"

client_script "client/native.lua"
client_script "client/main.lua"
server_script "server/main.lua"

files { "ui/chat.rml", "ui/chat.rcss", "ui/open77-yellow.rcss", "ui/fonts/*.ttf" }

permissions { "network.events", "local.events", "clipboard.write", "player.weapons.read", "players.life.read" } -- shots kick the floating chat; players.life.read: позиции для пузырей над головой (RPP)
