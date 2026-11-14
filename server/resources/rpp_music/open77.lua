-- rpp_music -- музыка при заходе на сервер.
--
-- Играет трек из web/music/, пока игра загружает мир, и плавно затихает
-- через несколько секунд после появления персонажа. Громкость регулируется
-- общим ползунком «Громкость веб-звука» в меню паузы; /music выключает
-- музыку и запоминает выбор.
--
-- Документация: docs/rpp_music.md в корне проекта.
resource "rpp_music"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "reconnect"

client_script "config.lua"
client_script "client/main.lua"

web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    -- open77:worldReady (персонаж появился в мире).
    "local.events",
}
