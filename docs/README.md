# Документация сервера RPPCyber

Сервер: OPEN//77 (мультиплеер Cyberpunk 2077), режим Freeroam + собственные моды.

| Документ | О чём |
|---|---|
| [commands.md](commands.md) | Все команды сервера: для игроков и для администраторов |
| [rpp_identity.md](rpp_identity.md) | Мод «Паспорт жителя»: регистрация, номер жителя, знакомства |
| [rpp_ripperdoc.md](rpp_ripperdoc.md) | Профессия «Риппердок»: установка и снятие имплантов другим игрокам |
| [rpp_animwheel.md](rpp_animwheel.md) | Колесо анимаций на U: 12 слотов, список анимаций, перетаскивание |
| [rpp_music.md](rpp_music.md) | Музыка при заходе на сервер: свой трек, затихание, /music |
| [rpp_inventory.md](rpp_inventory.md) | Мод «Инвентарь»: экипировка, импланты, рюкзак 6×12, евродоллары, выброс и подбор |
| [ui-theme.md](ui-theme.md) | Жёлто-чёрная тема интерфейса, кириллица, HP-бар |
| [rpp_vehicles.md](rpp_vehicles.md) | Личные машины: гараж, ключи, багажник, автосалон и прокат |
| [rpp_quickhack.md](rpp_quickhack.md) | Сканер и квикхаки (open77_quickhack): включение, управление, что работает |
| [open77-update.md](open77-update.md) | Версия Open77 (77.248), что в ней нового и как обновлять сервер |

Документация самого Open77 (конфигурация, RCON, метрики) лежит в `server/docs/`
и на сайте <https://open2077.net/docs>.

## Быстрые ссылки

- Админ-панель (Warden): <http://localhost:11780/>
- Конфигурация сервера: `server/server.jsonc`
- Права игроков (ACL): `server/acl.jsonc`, удобнее через Warden → Players → Rights
- Свои моды: `server/resources/rpp_*`
