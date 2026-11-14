-- rpp_inventory -- RP-инвентарь: надетая одежда и киберимпланты слева,
-- рюкзак 6x12 справа, евродоллары, экипировка оружия в слоты, выброс и
-- подбор предметов с земли.
--
-- Документация: docs/rpp_inventory.md в корне проекта.
resource "rpp_inventory"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true
-- Ресурс владеет WebUI-страницей: обновляется через переподключение клиента.
reload_policy "reconnect"

dependency "open77_notifications >=1.0.0"
dependency "open77_weapons >=0.1.0"
dependency "open77_equipment >=0.2.0"
dependency "open77_worldui >=0.1.0"
dependency "open77_contextmenu >=1.1.0"

-- Каталог (config.lua, weapons.lua) нужен клиенту только ради настроек
-- клавиши и дистанций; размеры и названия предметов присылает сервер.
shared_script "shared/config.lua"
server_script "shared/weapons.lua"
server_script "server/storage.lua"
server_script "server/main.lua"
client_script "client/main.lua"

web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    -- Сервер <-> клиент: состояние инвентаря и действия игрока.
    "network.events",
    -- Клиент: события мира (open77:worldReady) и подсказки worldui.
    "local.events",
    -- Клиент: клавиша I и блокировка штатного инвентаря.
    "input.actions",
    -- Клиент: какая одежда надета до первого входа (одноразовый перенос).
    "player.equipment.read",
    -- Сервер: одежда на персонаже (Open77.clothing.set).
    "player.equipment.edit",
    -- Сервер: оружие в слотах 1-3 и патроны.
    "player.weapons.edit",
    "player.weapons.read",
    -- Сервер: установленные киберимпланты (вкладка «Импланты»).
    "players.cyberware.read",
    -- Сервер: позиция игрока для выброса и подбора.
    "players.life.read",
    -- Сервер: хранение в MySQL (таблица rpp_inventories).
    "database.access",
}
