-- A YouTube television in front of the player, on a real TV mesh (Open77.screens):
-- the picture is the set's own screen material, the sound comes from the set.
--
--   started             every connected player gets a television in front of them
--   /tv [url]           (again) a television in front of you, playing url (YouTube, Vimeo, a video file)
--   J                   sit in front of it with the cursor on the player; Escape gives the view back
resource "open77_tv"
version "0.1.0"
open77_version ">=0.0.1"
auto_start true

client_script "client/main.lua"
server_script "server/main.lua"
web_files { "web/**" }
permissions { "world.props", "camera.script", "network.events" }
