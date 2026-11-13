# Документация сервера RPPCyber

Сервер: OPEN//77 (мультиплеер Cyberpunk 2077), режим Freeroam + собственные моды.

| Документ | О чём |
|---|---|
| [commands.md](commands.md) | Все команды сервера: для игроков и для администраторов |
| [rpp_identity.md](rpp_identity.md) | Мод «Паспорт жителя»: регистрация, номер жителя, знакомства |
| [ui-theme.md](ui-theme.md) | Жёлто-чёрная тема интерфейса, кириллица, HP-бар |

Документация самого Open77 (конфигурация, RCON, метрики) лежит в `server/docs/`
и на сайте <https://open2077.net/docs>.

## Быстрые ссылки

- Админ-панель (Warden): <http://localhost:11780/>
- Конфигурация сервера: `server/server.jsonc`
- Права игроков (ACL): `server/acl.jsonc`, удобнее через Warden → Players → Rights
- Свои моды: `server/resources/rpp_*`
