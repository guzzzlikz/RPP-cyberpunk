-- rpp_animwheel -- колесо анимаций на U.
--
-- 12 слотов под любимые анимации. «Список анимаций» — все анимации сервера:
-- двойной клик проигрывает, перетаскивание на слот колеса закрепляет
-- (на занятый — заменяет). Набор слотов хранится у игрока (kvp клиента).
--
-- Документация: docs/rpp_animwheel.md в корне проекта.
resource "rpp_animwheel"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "reconnect"

dependency "open77_animations >=1.0.0"

client_script "client/main.lua"

web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    -- Клавиша U (RegisterKeyMapping).
    "input.actions",
    -- onPlayerAnimationChanged / onAnimationPlaybackFailed.
    "local.events",
}
