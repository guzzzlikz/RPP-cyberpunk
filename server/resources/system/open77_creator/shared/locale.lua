-- open77_creator texts. RPP: переведены на русский (docs/ui-theme.md). The
-- game's own labels follow the game's language, so option and choice names are written here or
-- derived from the catalogue's internal names instead.
CreatorText = {
    title = "Создание персонажа", titleTop = "Создание", titleBottom = "персонажа",
    identity = "Внешность",
    subtitle = "Каким тебя увидит Найт-Сити",
    bodyType = "Тип тела", male = "Мужской", female = "Женский",
    presets = "Готовые образы", random = "Случайно",
    save = "Готово", cancel = "Отмена", later = "Позже",
    categories = { body = "Тело", face = "Лицо", eyes = "Глаза и брови", hair = "Волосы и борода",
                   makeup = "Макияж", marks = "Тату и пирсинг" },
    presetNames = { nomad = "Кочевник", street = "Дитя улиц", streetkid = "Дитя улиц", street_kid = "Дитя улиц", corpo = "Корпорат" },
    none = "Нет", shape = "Форма", style = "Стиль", option = "Вариант",
    hintRotate = "Поворот", hintZoom = "Приблизить", hintDrag = "Тяни мышью, чтобы вращать и сдвигать",
    applying = "Применяем", rebuilding = "Пересобираем тело", saving = "Сохраняем", saved = "Внешность сохранена",
    noAnswer = "Сервер не ответил, попробуй ещё раз",
    failed = "Не удалось открыть создание персонажа: %s",
    empty = "Для этого типа тела здесь нечего менять.",
}

-- One name per catalogue uiSlot.
CreatorText.slots = {
    skin_color = "Тон кожи", skin_type_switcher = "Тип кожи", breast = "Размер груди",
    nipples_switcher = "Соски", body_tattoo_switcher = "Тату на теле", body_scars_switcher = "Шрамы на теле",
    nails_l = "Длина ногтей", nails_color = "Цвет ногтей",
    eyes = "Форма глаз", nose = "Нос", mouth = "Рот", jaw = "Челюсть", ear = "Уши", teeth = "Зубы",
    scars = "Шрамы на лице", cyberware_switcher = "Импланты на лице",
    eyes_color = "Цвет глаз", eyebrows = "Брови", eyebrows_color = "Цвет бровей", eyelash_color = "Цвет ресниц",
    hairstyle = "Причёска", hair_color = "Цвет волос", beard = "Борода", beard_part = "Форма бороды", beard_color = "Цвет бороды",
    makeupEyes = "Макияж глаз", makeupEyes_color = "Цвет макияжа глаз",
    makeupLips_type = "Помада", makeupLips = "Стиль помады", makeupLips_color = "Цвет помады",
    makeupCheeks = "Румяна", makeupCheeks_color = "Цвет румян",
    makeupPimples = "Несовершенства кожи", makeupPimples_color = "Цвет несовершенств",
    facial_tattoo_switcher = "Тату на лице", piercings = "Пирсинг", piercings_color = "Цвет пирсинга",
}

local SKIP = { ca = true, bl = true, pwa = true, pma = true, wa = true, ma = true, base = true, fpp = true, tpp = true }
-- A name left with only these words is the option's base look.
local GENERIC = { basehead = true, head = true, default = true, body = true, base = true }

local function titleCase(words)
    local out = {}
    for _, word in ipairs(words) do out[#out + 1] = word:sub(1, 1):upper() .. word:sub(2):lower() end
    return table.concat(out, " ")
end

-- "h0_000_pwa__basehead__01_ca_pale_00_warm_ivory" -> "Warm Ivory", "05_brown_liquorice" -> "Brown Liquorice".
function CreatorInternalName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name == "None" then return CreatorText.none end
    local tail = name:match(".*__(.+)$") or name
    local tokens = {}
    for token in tail:gmatch("[^_]+") do tokens[#tokens + 1] = token end
    -- The words after the last number are the variant's own name.
    local last = 0
    for i, token in ipairs(tokens) do
        if token:match("^%d+$") then last = i end
    end
    local words = {}
    for i = last + 1, #tokens do
        if not SKIP[tokens[i]:lower()] then words[#words + 1] = tokens[i] end
    end
    if #words == 0 then
        for _, token in ipairs(tokens) do
            if not token:match("^%d+$") and not SKIP[token:lower()] then words[#words + 1] = token end
        end
    end
    if #words == 0 then return nil end
    local generic = true
    for _, word in ipairs(words) do
        if not GENERIC[word:lower()] then generic = false end
    end
    if generic then return "Базовый" end
    return titleCase(words)
end
