-- rpp_quickhack -- сканер и квикхаки (штатный open77_quickhack, 77.248).
--
-- open77_quickhack поставляется выключенным и стартует, только когда другой
-- ресурс объявляет его зависимостью. Этот ресурс и есть такая зависимость.
-- Здесь же — что делают наши квикхаки: «Короткое замыкание» и «Перегрев».
--
-- Документация: docs/rpp_quickhack.md в корне проекта.
resource "rpp_quickhack"
version "1.1.0"
open77_version ">=0.0.1"
auto_start true

dependency "open77_quickhack >=0.1.0"

shared_script "shared/config.lua"
server_script "server/main.lua"

permissions {
    -- Урон игрокам от квикхаков.
    "players.damage.apply",
    "players.life.read",
    -- Урон NPC.
    "world.npcs",
    "npcs.foreign",
    -- Заглушить двигатель машины.
    "world.vehicles",
    -- Искры и огонь на цели.
    "world.effects",
}
