-- rpp_ripperdoc -- профессия «Риппердок».
--
-- Риппердок (роль выдаёт админ: rpp.ripperdoc <id> on|off) ставит и снимает
-- импланты другим игрокам. Пациент даёт согласие: ALT на риппердоке ->
-- «Разрешить операцию». Снятый имплант уходит в инвентарь ПАЦИЕНТА.
--
-- Документация: docs/rpp_ripperdoc.md в корне проекта.
resource "rpp_ripperdoc"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "reconnect"

dependency "rpp_inventory >=1.0.0"
dependency "open77_cyberware >=0.1.0"
dependency "open77_contextmenu >=1.1.0"
dependency "open77_notifications >=1.0.0"

shared_script "shared/config.lua"
server_script "server/main.lua"
client_script "client/main.lua"

web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    -- Сервер <-> клиент: панель риппердока, согласие, список риппердоков.
    "network.events",
    -- Клиент: события Open77.
    "local.events",
    -- Сервер: свои определения имплантов, установка/снятие, чтение установленного.
    "players.cyberware.define",
    "players.cyberware.manage",
    "players.cyberware.read",
    -- Сервер: дистанция между риппердоком и пациентом.
    "players.life.read",
}
