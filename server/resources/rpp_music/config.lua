-- Настройки музыки при заходе.
RppMusicConfig = {
    enabled = true,
    -- Треки в web/music/. Форматы: .ogg (лучше всего), .opus, .webm.
    -- MP3 и M4A встроенный браузер игры может не воспроизвести.
    -- Несколько файлов — при каждом заходе выбирается случайный.
    tracks = { "music/Piernikowski-Daj-Mi-Jeszcze-Jedna-Szanse-Cyberpunk-Edgerunners-2-_Original-Series-Soundtrack_-SonySo.ogg" },
    volume = 0.6,          -- 0..1, поверх общего ползунка веб-звука в паузе
    loop = true,           -- повторять трек, пока мир грузится
    fadeInMs = 2500,
    fadeOutMs = 6000,
    -- Через сколько секунд после появления персонажа начать затихание.
    -- 0 — затихать сразу; -1 — доиграть трек до конца (без повтора).
    stopAfterWorldReadySec = 120,
    -- Не играть, если ресурс запустился, когда игрок уже в мире
    -- (перезапуск ресурса или переподключение без загрузки).
    -- false: всё равно сыграть, а затихание начать через stopAfterWorldReadySec.
    skipIfAlreadyInWorld = false,
}
