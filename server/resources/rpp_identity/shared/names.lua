-- Проверка и нормализация имени/фамилии. Одна функция для клиента и сервера:
-- клиент проверяет для удобства, сервер — по-настоящему.
--
-- Разрешено: латиница, кириллица (включая Ё/ё), дефис и апостроф внутри слова.
-- Первая буква делается заглавной.
RppNames = {}

local cfg = RppIdentityConfig

local function isLetter(cp)
    return (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)   -- A-Z a-z
        or (cp >= 0x410 and cp <= 0x44F)                          -- А-я
        or cp == 0x401 or cp == 0x451                             -- Ё ё
end

local function upper(cp)
    if cp >= 97 and cp <= 122 then return cp - 32 end
    if cp >= 0x430 and cp <= 0x44F then return cp - 0x20 end
    if cp == 0x451 then return 0x401 end
    return cp
end

RppNames.errors = {
    empty = "Поле не заполнено.",
    invalid_utf8 = "Недопустимые символы.",
    too_short = ("Слишком коротко: минимум %d символа."):format(cfg.nameMinLength),
    too_long = ("Слишком длинно: максимум %d символов."):format(cfg.nameMaxLength),
    bad_chars = "Только буквы (русские или латинские), дефис и апостроф.",
    bad_edges = "Имя должно начинаться и заканчиваться буквой.",
    double_mark = "Два дефиса или апострофа подряд недопустимы.",
}

--- Возвращает нормализованную строку или nil и код ошибки.
function RppNames.validate(value)
    if type(value) ~= "string" then return nil, "empty" end
    value = value:match("^%s*(.-)%s*$") or ""
    if value == "" then return nil, "empty" end
    local length = utf8.len(value)
    if not length then return nil, "invalid_utf8" end
    if length < cfg.nameMinLength then return nil, "too_short" end
    if length > cfg.nameMaxLength then return nil, "too_long" end

    local codepoints, previousMark = {}, false
    for _, cp in utf8.codes(value) do
        local mark = cp == 45 or cp == 39   -- '-' или '\''
        if not mark and not isLetter(cp) then return nil, "bad_chars" end
        if mark and previousMark then return nil, "double_mark" end
        previousMark = mark
        codepoints[#codepoints + 1] = cp
    end
    if not isLetter(codepoints[1]) or not isLetter(codepoints[#codepoints]) then
        return nil, "bad_edges"
    end
    codepoints[1] = upper(codepoints[1])
    return utf8.char(table.unpack(codepoints))
end

function RppNames.errorText(code)
    return RppNames.errors[code] or ("Ошибка: " .. tostring(code))
end

function RppNames.citizenTag(id)
    return ("%s #%s"):format(cfg.citizenPrefix, tostring(id))
end
