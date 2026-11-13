# Локальная база данных (MariaDB)

Нужна для редактора внешности (`/appearance`, создание персонажа) и сохранения
персонажей в Open77. Сервер подключается к `127.0.0.1:3306`, база `open77`.

В git лежат только скрипты. Бинарники (`server/`), данные (`data/`) и пароли
(`credentials.txt`) в `.gitignore`.

## Запуск

`server/Start.cmd` запускает базу сам. Вручную:

- `start-db.cmd` — запустить (если уже запущена, ничего не делает);
- `stop-db.cmd` — корректно остановить.

Лог: `data/<имя компьютера>.err`.

Сервер берёт строку подключения из переменной окружения пользователя
`OP77_DATABASE_CONNECTION`:

```
Server=127.0.0.1;Port=3306;Database=open77;User ID=open77;Password=<из credentials.txt>;
```

## Установка с нуля (на другом компьютере)

1. Скачать MariaDB 11.4 LTS (ZIP для Windows x64) с <https://archive.mariadb.org/mariadb-11.4.8/winx64-packages/>
   и распаковать содержимое папки `mariadb-11.4.8-winx64` в `db/server/`.
2. Инициализировать данные (пароль root придумать):
   ```
   db\server\bin\mariadb-install-db.exe --datadir=<путь к репо>\db\data --password=<root> --port=3306
   ```
3. В `db/data/my.ini` в секцию `[mysqld]` добавить:
   ```
   bind-address=127.0.0.1
   character-set-server=utf8mb4
   collation-server=utf8mb4_unicode_ci
   ```
4. Запустить `start-db.cmd` и создать базу и пользователя:
   ```sql
   CREATE DATABASE open77 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'open77'@'127.0.0.1' IDENTIFIED BY '<пароль>';
   CREATE USER 'open77'@'localhost' IDENTIFIED BY '<пароль>';
   GRANT ALL PRIVILEGES ON open77.* TO 'open77'@'127.0.0.1';
   GRANT ALL PRIVILEGES ON open77.* TO 'open77'@'localhost';
   ```
5. Записать `credentials.txt` (`root=`, `user=`, `password=`, `database=`) и задать переменную
   `OP77_DATABASE_CONNECTION` (Параметры Windows → Переменные среды пользователя).
6. В `server/server.jsonc`: `"database": { "enabled": true, ... }`.

Таблицы Open77 (`open77_characters`, `open77_player_appearances`, `players`…) создаются сами
при первом запуске сервера.
