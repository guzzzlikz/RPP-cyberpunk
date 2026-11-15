-- rpp_vehicles -- личные машины игроков.
--
-- Машину покупают в автосалоне или выдаёт админ (/givecar), игрок вызывает
-- её в окне гаража (/garage). В прокате можно взять машину на время.
-- Через ALT на машине: открыть / закрыть, багажник, высадить пассажиров,
-- припарковать (убрать в гараж, только владелец). Владелец может дать ключи другому игроку (ALT на игроке):
-- у того же самого права, кроме выдачи ключей.
--
-- Документация: docs/rpp_vehicles.md в корне проекта.
resource "rpp_vehicles"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "reconnect"

dependency "rpp_inventory >=1.0.0"
dependency "open77_contextmenu >=1.1.0"
dependency "open77_notifications >=1.0.0"
dependency "open77_worldui >=0.1.0"

shared_script "shared/config.lua"
server_script "server/storage.lua"
server_script "server/main.lua"
client_script "client/main.lua"

-- Окно гаража (/garage).
web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    -- Сервер <-> клиент: права на машины рядом, действия из ALT-меню.
    "network.events",
    -- Клиент: события Open77 и жизненного цикла ресурсов.
    "local.events",
    -- Сервер: создать / убрать машину, замок, высадить пассажира.
    "world.vehicles",
    -- Сервер: позиции игроков (дистанция до машины, место появления).
    "players.life.read",
    -- Сервер: машины игроков в MySQL (таблица rpp_vehicles).
    "database.access",
    -- Клиент: метки автосалона и проката на карте.
    "world.markers",
}
