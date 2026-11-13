-- rpp_identity -- RP-паспорт жителя Найт-Сити.
--
-- 1. Новый игрок проходит кастомизацию внешности (редактор open77_appearance).
-- 2. Затем вводит имя и фамилию и получает уникальный номер «Житель #1001».
-- 3. Над головами других игроков видно «Житель #N», пока вы не познакомитесь;
--    после знакомства (ALT + клик по игроку -> «Познакомиться») оба видят имена.
--
-- Документация: docs/rpp_identity.md в корне проекта.
resource "rpp_identity"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true
-- Ресурс владеет WebUI-страницей (форма паспорта), поэтому, как и все ресурсы
-- с CEF-поверхностью, перезагружается через переподключение клиента.
reload_policy "reconnect"

dependency "open77_contextmenu >=1.1.0"
dependency "open77_notifications >=1.0.0"

-- Порядок = порядок загрузки. Скрипты перечислены явно: пустой glob в манифесте
-- блокирует подключение всем клиентам (script_pattern_empty).
shared_script "shared/config.lua"
shared_script "shared/names.lua"
server_script "server/storage.lua"
server_script "server/main.lua"
client_script "client/form.lua"
client_script "client/main.lua"

web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    -- Сервер <-> клиент: регистрация, подписи над головами, знакомства.
    "network.events",
    -- Клиент: события редактора внешности и жизненного цикла ресурсов.
    "local.events",
    -- Клиент: свои подписи над головами игроков (Open77.nameplates.set).
    "ui.nameplates",
    -- Сервер: только проверка, включена ли MySQL. Без базы редактор внешности
    -- open77_appearance не открывается, и регистрация сразу переходит к имени.
    "database.access",
    -- Сервер: позиции игроков для проверки дистанции при знакомстве.
    "players.life.read",
}
