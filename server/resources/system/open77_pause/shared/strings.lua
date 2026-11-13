-- THE string table for the pause menu.
--
-- Every player-facing word this resource owns lives here and nowhere else --
-- not in ui/pause.rml, not inline in client/ui.lua, not in a Lua print that
-- reaches the screen. client/ui.lua paints the menu from this table (sent again
-- as `pause:strings`); the client script reads the same table directly, because
-- `shared_script` runs it in the same Lua state as `client/main.lua`
-- (ResourceHost.cpp:868 prepends shared scripts to the client list, so this
-- file is loaded first).
--
-- `{name}` is a placeholder, substituted by `fmt` on either side.
--
-- WHAT IS DELIBERATELY ABSENT, because it is data rather than language:
--
--   * every engine setting's label and every option name in a dropdown. They
--     come from the engine, already localised, on the `meta:` line the script
--     bridge now emits (Open77SettingLabel / Open77SettingOption in
--     client/redscript/Open77ScriptBridge.reds). Before that line existed the
--     page carried a hand-written English table of twenty names and camel-case
--     split the rest, which is exactly the hardcoding this file forbids;
--   * audio device names, which Windows supplies;
--   * key names and the human name a resource gave its own key mapping;
--   * server names, player names, endpoints and versions.
--
-- A missing key renders as its own dotted path. That is ugly ON PURPOSE: a
-- blank label hides the mistake, a visible `settings.filterPlaceholder` does
-- not, and the second one gets fixed.
--
-- RPP: translated to Russian (docs/ui-theme.md). Engine setting labels follow
-- the game's own interface language.

PauseStrings = {
    locale = "ru",

    -- Masthead and the dialog's accessible name.
    chip = "Пауза",
    dialogLabel = "Меню паузы",
    mapUnavailable = "Карта города не открылась ({reason}). Закрой другие меню и попробуй снова.",

    -- The keyboard legend along the bottom of the panel. Split label/key so the
    -- key can keep its own type treatment without HTML in a string.
    legend = {
        close = "ЗАКРЫТЬ",
        navigate = "ВЫБОР",
        adjust = "ИЗМЕНИТЬ",
        select = "ОК",
        escape = "ESC",
        updown = "\u{2191} \u{2193}",
        leftright = "\u{2190} \u{2192}",
        enter = "ENTER",
    },

    session = {
        eyebrow = "Сессия",
        none = "Нет сессии",
        connecting = "Подключение\u{2026}",
        connected = "Подключено",
        offline = "НЕ В СЕТИ",
        live = "В СЕТИ",
        hint = "Не подключено. Выбери мир в списке серверов.",
        player = "Игрок",
        ping = "Пинг",
        players = "Игроки",
        tick = "Тик",
        serverVersion = "Версия сервера",
        endpoint = "Адрес",
        showAddresses = "Показать IP-адреса",
        addressHidden = "[адрес скрыт]",
        client = "Клиент",
        milliseconds = "мс",
        -- `snap` is the snapshot rate; both figures are engine data.
        tickUnit = "Гц \u{b7} снимки {rate}",
        blank = "\u{2014}",
    },

    menu = {
        resume = "ПРОДОЛЖИТЬ",
        map = "КАРТА ГОРОДА",
        settings = "НАСТРОЙКИ",
        quitSession = "ВЫЙТИ С СЕРВЕРА",
        quitGame = "ВЫЙТИ ИЗ ИГРЫ",
    },

    -- Copy shown before each destructive action. Written out per action rather
    -- than derived from the label, so each one says what actually happens.
    confirm = {
        yes = "ПОДТВЕРДИТЬ",
        no = "ОТМЕНА",
        quitSessionTitle = "Выйти с сервера",
        quitSessionBody = "Ты отключишься и вернёшься к списку серверов. " ..
            "Персонаж останется на сервере.",
        quitGameTitle = "Выйти из игры",
        quitGameBody = "Cyberpunk 2077 закроется. Если ты на сервере, " ..
            "сначала произойдёт отключение.",
    },

    settings = {
        title = "Настройки",
        categories = "Разделы настроек",
        loading = "Загрузка\u{2026}",
        back = "НАЗАД",
        vanilla = "ВСЕ НАСТРОЙКИ ИГРЫ",
        vanillaHint = "Открывает экран настроек самой игры. Пока он открыт, " ..
            "мир на паузе.",
        empty = "Здесь пока нечего менять. Этот раздел есть в полных " ..
            "настройках игры.",
        noCategories = "Разделов нет.",
        noMatch = "Ничего не найдено по \u{201c}{query}\u{201d}.",
        filterLabel = "Фильтр настроек в разделе",
        filterPlaceholder = "ФИЛЬТР",
        filterClear = "Очистить фильтр",
        range = "{first} - {last} / {total}",
        scrollHint = "КОЛЕСО МЫШИ / PAGE UP / PAGE DOWN",
        on = "ВКЛ",
        off = "ВЫКЛ",
        previous = "Назад: {name}",
        next = "Вперёд: {name}",
        find = "НАЙТИ",
        findNoMatch = "не найдено",
        blank = "\u{2014}",
    },

    -- Tab names, keyed by the id `TABS` declares in client/main.lua. The panel
    -- heading is derived from the same word rather than stored twice.
    tabs = {
        video = "ЭКРАН",
        graphics = "ГРАФИКА",
        audio = "ЗВУК",
        voice = "ГОЛОС",
        controls = "УПРАВЛЕНИЕ",
        keybinds = "КЛАВИШИ",
        gameplay = "ИГРА",
    },

    -- Section headings inside a tab. One key per engine group a tab renders --
    -- the group PATH is not a heading: `/graphics/advanced` is a routing
    -- detail, and it is what the page used to print.
    webAudio = {
        volume = "Громкость WebUI",
        scope = "Веб-страницы и медиа",
        hint = "0% выключает радио, видео и звуки интерфейса.",
        failed = "Не удалось сохранить громкость WebUI. Оставлена прежняя.",
    },
    groups = {
        webAudio = "ЗВУК WEBUI",
        display = "ДИСПЛЕЙ",
        brightness = "ЯРКОСТЬ",
        upscaling = "МАСШТАБИРОВАНИЕ И ГЕНЕРАЦИЯ КАДРОВ",
        effects = "ЭФФЕКТЫ",
        quality = "КАЧЕСТВО",
        raytracing = "ТРАССИРОВКА ЛУЧЕЙ",
        crowds = "ТОЛПА",
        system = "СИСТЕМА",
        volume = "ГРОМКОСТЬ",
        audioMisc = "ВЫВОД ЗВУКА",
        audioRange = "ДИНАМИЧЕСКИЙ ДИАПАЗОН",
        voice = "ГОЛОСОВОЙ ЧАТ",
        keybinds = "ДЕЙСТВИЯ",
        controlsGeneral = "ОБЩЕЕ",
        mouse = "МЫШЬ",
        mouseTpp = "МЫШЬ \u{b7} ТРЕТЬЕ ЛИЦО",
        pad = "ГЕЙМПАД",
        padCamera = "КАМЕРА ГЕЙМПАДА",
        padCameraTpp = "КАМЕРА ГЕЙМПАДА \u{b7} ТРЕТЬЕ ЛИЦО",
        vehicle = "ТРАНСПОРТ",
        gameplayMisc = "ИГРА",
        difficulty = "СЛОЖНОСТЬ",
        hud = "HUD",
        performance = "ПРОИЗВОДИТЕЛЬНОСТЬ",
        interface = "ИНТЕРФЕЙС",
        hudElements = "ЭЛЕМЕНТЫ HUD",
    },

    -- Row tags. Each one answers "why did nothing visibly happen?" before the
    -- player has to ask -- the engine tells us, so the row says so.
    tag = {
        restart = "ПЕРЕЗАПУСК",
        restartHint = "Применится при следующем запуске игры.",
        checkpoint = "ПЕРЕЗАГРУЗКА",
        checkpointHint = "Применится после перезагрузки мира.",
        menuOnly = "ТОЛЬКО В МЕНЮ",
        menuOnlyHint = "Игра применяет это только из главного меню. " ..
            "Значение сохранится и сработает при следующем запуске.",
        locked = "ЗАБЛОКИРОВАНО",
        lockedHint = "Сейчас недоступно \u{2014} обычно потому, что " ..
            "выключена связанная настройка.",
        hidden = "СКРЫТО",
        hiddenHint = "На экране настроек самой игры этого пункта нет.",
        unavailable = "НЕДОСТУПНО",
        unavailableHint = "На этом компьютере вариантов нет.",
    },

    -- VOICE. These rows are built by the client script from the native voice
    -- status, not by the engine's settings tree, so their labels live here.
    voice = {
        transmitMode = "Режим передачи",
        transmitState = "Состояние микрофона",
        pushToTalkKey = "Клавиша рации",
        inputDevice = "Микрофон",
        outputDevice = "Устройство вывода",
        inputVolume = "Громкость микрофона",
        outputVolume = "Громкость голосов",
        reach = "Дальность голоса",
        captureEnabled = "Микрофон включён",
        activation = "Активация голосом",
        activationThreshold = "Порог активации",
        microphoneTest = "Проверка микрофона (слышишь себя)",
        inputLevel = "Уровень микрофона",
        outputLevel = "Уровень голосов",
        thresholdMarker = "Порог активации",

        systemDefault = "Устройство связи Windows по умолчанию",
        modeActivation = "АКТИВАЦИЯ ГОЛОСОМ",
        modePushToTalk = "РАЦИЯ \u{b7} ЗАЖМИ {key}",
        stateDisabled = "МИКРОФОН ВЫКЛЮЧЕН",
        stateTransmitting = "ПЕРЕДАЧА",
        stateReadyActivation = "ГОТОВ \u{b7} ГОВОРИ ГРОМЧЕ ПОРОГА",
        stateReadyPushToTalk = "ГОТОВ \u{b7} ЗАЖМИ {key}",
        reachValue = "ЗАДАЁТ СЕРВЕР \u{b7} {metres} м",

        saved = "СОХРАНЕНО",
        microphoneTestUpdated = "ПРОВЕРКА МИКРОФОНА ОБНОВЛЕНА",
        failed = "ОШИБКА НАСТРОЙКИ ГОЛОСА \u{b7} {reason}",
        restoreWaiting = "ЖДЁМ ВОССТАНОВЛЕНИЯ ГОЛОСА \u{b7} {reason}",
        restored = "НАСТРОЙКИ ГОЛОСА ВОССТАНОВЛЕНЫ",
        restoreGaveUp = "УСТРОЙСТВО НЕ ВОССТАНОВЛЕНО \u{b7} ВЫБОР СОХРАНЁН",
    },

    keybind = {
        press = "НАЖМИ КЛАВИШУ / КНОПКУ МЫШИ",
        resetTitle = "Сбросить ({key})",
        resetLabel = "Сбросить {name}",
    },
}
