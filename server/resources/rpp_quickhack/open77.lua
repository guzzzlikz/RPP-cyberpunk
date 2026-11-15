-- rpp_quickhack -- включает сканер и квикхаки (штатный open77_quickhack, 77.248).
--
-- open77_quickhack поставляется выключенным и стартует, только когда другой
-- ресурс объявляет его зависимостью. Этот ресурс и есть такая зависимость.
-- Пока здесь только включение: работают штатные примеры «Пинг».
-- Сюда же потом добавляются свои RP-квикхаки (exports.open77_quickhack:register).
--
-- Документация: docs/rpp_quickhack.md в корне проекта.
resource "rpp_quickhack"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

dependency "open77_quickhack >=0.1.0"

server_script "server/main.lua"
