# Команды сервера

Команды вводятся в чат (клавиша **T**) со слешем: `/passport`. Из консоли сервера
и через RCON — без слеша: `weather.set rain 30`.

## Как устроены права

- **Игрок** — команда доступна всем.
- **Админ** — команда зарегистрирована как ограниченная (`restricted`). Чтобы игрок
  мог её выполнить, ему нужно право `command.<имя команды>` в ACL: например,
  `command.weather.set`. Права выдаются в Warden (Players → Rights) или в `acl.jsonc`.
  Шаблон `command.weather.*` даёт все команды группы, но **не** саму `command.weather`.
- Консоль сервера может выполнять любые команды.

Список собран из исходников ресурсов, загруженных в `server.jsonc` (ноябрь 2026).
Ресурсы с `auto_start false` (`open77_braindance`, `open77_scenes`) работают,
только если их запустить командой `ensure <ресурс>` в консоли.

---

## Паспорт жителя — `rpp_identity` (наш мод)

Подробности: [rpp_identity.md](rpp_identity.md).

| Команда | Доступ | Что делает |
|---|---|---|
| `/passport` | Игрок | Показать свой номер жителя, имя и число знакомых |
| `/register` | Игрок | Открыть оформление паспорта, если его ещё нет (или если закрыли форму) |
| `/accept` | Игрок | Принять последнее предложение знакомства |
| `/decline` | Игрок | Отклонить все предложения знакомства |
| `rpp.identity.info <playerId>` | Админ | Кто за номером: аккаунт, номер жителя, имя |
| `rpp.identity.reset <playerId>` | Админ | Удалить паспорт игрока; он пройдёт регистрацию заново |

Знакомство также доступно в меню **ALT + клик по игроку → «Познакомиться»**.

---

## Личные машины — `rpp_vehicles` (наш мод)

Подробности: [rpp_vehicles.md](rpp_vehicles.md).

| Команда | Доступ | Что делает |
|---|---|---|
| `/garage` | Игрок | Окно гаража: выбрать свою машину и вызвать её к себе |
| `/carkeys` | Игрок | Забрать ключи от всех своих машин у всех |
| `/givecar <ID игрока> <Vehicle.запись> [название]` | Админ | Выдать игроку машину навсегда |
| `/cars <ID игрока>` | Админ | Машины игрока с номерами в базе |
| `/delcar <номер>` | Админ | Удалить машину вместе с багажником |

**ALT + клик по машине** (если вы владелец или у вас есть ключи): «Открыть / Закрыть машину»,
«Багажник», «Высадить пассажиров», «Припарковать» (убрать в гараж, только владелец),
«Вернуть в прокат» (арендатор). **Автосалон** и **прокат** — метки на карте, у стойки нажать **E**. **ALT + клик по игроку**: «Дать ключи от машины» /
«Забрать ключи от машины» (только владелец), «Высадить из машины».

---

## Чат — `open77_chat`

| Команда | Доступ | Что делает |
|---|---|---|
| `/help` | Игрок | Справка по чату и командам |
| `/clear` | Игрок | Очистить свою историю чата |
| `/id` | Игрок | Показать свой временный ID сессии (меняется при переподключении) |
| `/me <действие>` | Игрок | Ролевое действие от третьего лица: строка в чате и пузырь над головой — оранжевые. Видят игроки в радиусе голоса |
| `/ooc <текст>` | Игрок | Общий чат вне роли (OOC), серым: видят все игроки на сервере; не чаще раза в 3 с |
| `/b <текст>` | Игрок | Локальный чат вне роли (LOOC), серым — то же, что `((текст))`. Видят игроки в радиусе голоса |
| `/togooc` | Игрок | Скрыть / снова показать OOC и LOOC других игроков (запоминается) |
| `/roll` | Игрок | Бросок кубика 1–100: результат видят вы и игроки в радиусе вашего голоса (в чате и над головой); не чаще раза в 2 с |

**Локальный и общий чат:** обычное сообщение (метка IC), `((LOOC))`, `/me`, `*действия*` и
`/roll` видят автор и игроки в радиусе его голоса (режим `open-voice`, F11): шёпот — 3 м,
обычно — 20 м, крик — 40 м. Шёпот и крик видны в имени: «Имя (шёпотом)», «Имя (кричит)».
Всем на сервере уходит только `/ooc текст` (метка OOC). OOC и LOOC — серые, без пузыря над
головой; каждый может скрыть чужие командой `/togooc`. Системные сообщения сервера видят все.

**Действия в обычном сообщении:** текст в звёздочках вплотную к словам — `*дал ляща*` —
показывается оранжевым и без звёздочек: «Че как чумба? *Дал ляща далбоебу.* Че будем
делать?». `* с пробелами *` и `2 * 3` остаются как есть.

**Над головой:** каждое сообщение и `/me` видны над головой автора в киберпанк-рамке
(жёлтой для речи, оранжевой для действий). Видят их только игроки в радиусе голоса автора
(режим `open-voice`, переключается F11): шёпот — 3 м, обычно — 20 м, крик — 40 м. Сервер
рассылает пузырь только тем, кто в радиусе, а страница прячет его, если автор отошёл дальше.
Время показа зависит от длины: 4 с минимум, +0,06 с на символ, не дольше 16 с; длиннее
256 символов текст обрезается с «…» в конце. Над собой пузыря нет. Таблички видны до 40 м
(`nameplateDistance` в `rpp_identity`), чтобы крик было видно на всю дальность. Рисует страница `open77_nameplates`
(режим `RPP_WEB_NAMEPLATES = true`).

Клавиши: **T** — открыть чат, **Enter** — отправить, **Esc** — закрыть, **Tab** — дополнить команду.

Сообщение — до 1000 символов (счётчик под полем ввода). Недописанный текст не стирается
при закрытии чата: он остаётся в поле, пока вы его не отправите или не удалите. Длинные
строки переносятся внутри рамки чата.

## Внешность — `open77_appearance`

> Редактор внешности работает **только с включённой MySQL** (`database.enabled` в `server.jsonc`).
> Без базы `/appearance` отвечает `database_unavailable`.

| Команда | Доступ | Что делает |
|---|---|---|
| `/creator` | Игрок | Создание персонажа `open77_creator` (77.248): тело, лицо, волосы, макияж, тату. Новому персонажу открывается само. Работает и без MySQL |
| `/appearance [ripperdoc\|hairdresser] [male\|female]` | Игрок | Открыть редактор внешности (рипердок — всё тело, парикмахер — причёска) |
| `/appearance male` / `/appearance female` | Игрок | Полный редактор с выбором тела |
| `/barber` | Игрок | Редактор причёски |
| `/gender` | Игрок | Сменить тип тела (только без базы данных; с базой — `/appearance male\|female`) |
| `/wardrobe` (или **F2**) | Игрок | Гардероб: 7 сохраняемых комплектов одежды |
| `/appearance.status` | Игрок | Диагностика: готовность тел и внешности соседей |

## Freeroam — `freeroam`

### Для игроков

| Команда | Что делает |
|---|---|
| `/freeroam` | Главное меню режима (транспорт, оружие, телепорты, анимации) |
| `/freeroam.help` | Список команд режима |
| `/freeroam.status` | Диагностика режима |
| `/car [модель]` | Заспавнить машину рядом |
| `/dv [all]` | Убрать последнюю (или все) свои машины |
| `/goto <место>` | Телепорт в настроенную точку |
| `/locations` | Список точек для `/goto` |
| `/tpc <x> <y> <z> [heading]` | Телепорт по координатам |
| `/spawn [имя]` | Вернуться на точку спавна |
| `/suicide` | Умереть (штатный цикл смерти) |
| `/revive` | Воскреснуть на месте, если мёртв |
| `/players` | Список игроков и их состояние |
| `/guns` | Набор оружия |
| `/anim` | Меню анимаций (70 вариантов в 12 группах) |
| `/camchange`, `/cinematic` | Режимы камеры |
| `/race`, `/race.join`, `/race.leave`, `/race.status`, `/race.where`, `/race.course.list` | Гонки на машинах |
| `/footrace` | Забег пешком |
| `/pvp`, `/pvp.join`, `/pvp.leave`, `/pvp.blade` | PvP-арена (обычная и на клинках) |
| `/dm`, `/deathmatch.join`, `/deathmatch.leave`, `/deathmatch.status` | Deathmatch |
| `/dm.arena`, `/dm.queue`, `/dm.loadout`, `/dm.rounds`, `/dm.score`, `/dm.stats`, `/dm.where`, `/dm.bounds`, `/dm.instances` | Информация и настройки PvP-матча |

### Для администраторов

| Команда | Что делает |
|---|---|
| `freeroam.tp`, `freeroam.respawn`, `freeroam.revive`, `freeroam.cleanup` | Управление игроками и уборка мира |
| `tv [url]` | Поставить перед собой телевизор с видео (YouTube, Vimeo, файл), `open77_tv`. Его видит только тот, кто поставил. **J** — сесть перед экраном |
| `race.editor`, `race.course.select`, `race.force`, `race.probe` | Редактор трасс и управление гонкой |
| `dm.goto`, `dm.leash`, `dm.map`, `dm.bot`, `dm.survey`, `dm.stats.of`, `dm.rating.sim`, `dm.arena.mock` | Служебные команды PvP: карты, боты, рейтинг |
| `admin.playtest.foot`, `.race`, `.ffa`, `.blade`, `.cancel` | Массово отправить игроков в режим для теста |

## Администрирование — `open77_admin`

Все команды ограниченные. Право = `command.<имя>`. Меню: `/admin` (компактное), `/adminfull` (полная панель).
Публичные: `/pos`, `/rot` — показать свои координаты и поворот.

| Группа | Команды |
|---|---|
| Сводки | `admin.read.players`, `admin.read.vehicles`, `admin.read.world`, `admin.read.props [радиус]`, `admin.read.audit`, `admin.read.weapons [id]` |
| Себе | `admin.self.noclip [on\|off]`, `admin.self.fly`, `admin.self.speed <м/с>`, `admin.self.god`, `admin.self.heal`, `admin.self.revive`, `admin.self.pos`, `admin.self.maptravel` |
| Игрокам | `admin.player.goto <id>`, `admin.player.bring <id>`, `admin.player.tp <id\|me> <x> <y> <z> [yaw]`, `admin.player.at [id] <место>`, `admin.player.observe <id>`, `admin.player.heal\|revive\|kill <id>`, `admin.player.god <id> [on\|off]`, `admin.player.health <id> <0..1>`, `admin.player.armor <id> <броня>` |
| Модерация | `admin.moderate.kick <id> [причина]`, `admin.moderate.ban <id> [30m\|12h\|7d\|perm] [причина]` |
| Транспорт | `admin.veh.spawn`, `admin.veh.give`, `admin.veh.remove`, `admin.veh.repair`, `admin.veh.flag`, `admin.veh.speed`, `admin.veh.speed.here`, `admin.veh.speed.global`, `admin.veh.speed.clear` |
| Оружие | `admin.weap.give <id\|me> <запись>`, `admin.weap.ammo`, `admin.weap.remove`, `admin.weap.holster`, `admin.weap.catalog` |
| Пропсы и свет | `admin.props.spawn`, `.here`, `.list`, `.move`, `.remove`, `.clear`, `.catalog`, `.light`, `.light.here`, `.light.toggle` |
| Эффекты | `admin.fx.play`, `.loop`, `.list`, `.stop`, `.fireworks`, `.show <пресет>`, `.show.stop`, `.stage`, `.stage.clear` |
| Мир | `admin.world.announce <текст>`, `admin.world.loc.add <имя>`, `admin.world.loc.remove <имя>`, `admin.world.cleanup`, `admin.server.status` |

Короткие псевдонимы (`noclip`, `fly`, `bring`, `tp`, `kick`, `ban`, `god`, `heal`, `announce`…)
требуют своё право `command.<псевдоним>`. Если имя занято `freeroam` (`car`, `dv`, `goto`, `players`),
работает команда freeroam.

## Модерация и база — `open77_freeroam`

| Команда | Доступ | Что делает |
|---|---|---|
| `kick <playerId> [причина]` | Админ | Кикнуть игрока |
| `ban <playerId> [причина]` | Админ | Забанить на этом сервере (нужна MySQL) |
| `makeadmin <playerId>` | Только консоль | Записать игрока в таблицу `admin_groups` (нужна MySQL) |

## Погода и время — `open77_weather`

| Команда | Доступ | Что делает |
|---|---|---|
| `/weather`, `/weather.status`, `/weather.time` | Игрок | Текущие погода и время |
| `weather.set <пресет> [секунд перехода]` | Админ | Сменить погоду, например `weather.set rain 30` |
| `weather.next`, `weather.random on\|off` | Админ | Следующая погода / случайная смена |
| `weather.time.set ЧЧ:ММ:СС` | Админ | Установить время |
| `weather.time.freeze`, `weather.time.resume` | Админ | Остановить / продолжить ход времени |
| `weather.rate <множитель>` | Админ | Скорость течения времени |

## Транспорт — `open77_vehicles`

| Команда | Доступ |
|---|---|
| `vehicle.list`, `vehicle.damage.dump` | Игрок (диагностика) |
| `vehicle.create`, `vehicle.create.player`, `vehicle.remove`, `vehicle.repair`, `vehicle.health`, `vehicle.engine`, `vehicle.lock`, `vehicle.exitlock`, `vehicle.horn`, `vehicle.seat`, `vehicle.warp`, `vehicle.out`, `vehicle.paint`, `vehicle.paint.reset`, `vehicle.glass.break`, `vehicle.glass.repair`, `vehicle.probe`, `vehicle.weapons.probe` | Админ |

## Оружие — `open77_weapons`

`weapon.give`, `weapon.ammo`, `weapon.remove`, `weapon.clear`, `weapon.read`, `weapon.blasts` — все админские.

## Мир

| Ресурс | Команды | Доступ |
|---|---|---|
| `open77_elevators` | `elevator.list` | Игрок |
| | `elevator.goto`, `elevator.teleport`, `elevator.pause`, `elevator.resume`, `elevator.adopt`, `elevator.adopt.player`, `elevator.remove` | Админ |
| `open77_traffic` | `traffic [open\|state <радиус>\|set <ключ> <значение>\|pattern\|panic\|reset confirm]`, `traffic.status`, `traffic.esp` | Админ |
| `open77_pedestrians` | `pedestrians.status`, `pedestrians.enable`, `pedestrians.crowd on\|off`, `pedestrians.density`, `pedestrians.seats`, `pedestrians.reset` | Админ |
| `op77_map3d` | `map3d.jam`, `map3d.unjam` — глушилка карты | Админ |
| `open77_remote_camera` | `remote-camera.editor`, `.cameras`, `.hud`, `.webui`, `.slots`, `.off` | Админ |

## Прочее

| Ресурс | Команда | Доступ | Что делает |
|---|---|---|---|
| `open77_perspective` | `perspective` | Админ | Политика вида от 1-го/3-го лица |
| `open77_prediction` | `prediction [status\|on\|off <семейство>\|ping <мс>\|telemetry <с>]` | Админ | Настройки сетевого предсказания |
| `open77_notifications` | `notification.test [info\|success\|warning\|error]` | Админ | Тестовое уведомление |
| `open77_cyberware_lab` | `/cyberlab` | Игрок | Панель кибер-лаборатории |
| `open77_braindance`* | `bd` (игрок), `braindance`, `bdlayer` (админ) | — | Брейнданс-сцены |
| `open77_scenes`* | `scene`, `standup` (игрок), `scenes.start`, `.stand`, `.idle`, `.near`, `.status`, `.tune` (админ) | — | RP-сцены на мебели |

\* Ресурс не запускается сам: `ensure open77_braindance` / `ensure open77_scenes` в консоли.

## Клавиши

| Клавиша | Действие |
|---|---|
| **T** | Чат |
| **ALT + клик** | Контекстное меню на игроке, машине, предмете (в т. ч. «Познакомиться») |
| **M** | 3D-карта города |
| **F2** | Гардероб |
| **~** | Консоль разработчика Open77 (клиент) |
