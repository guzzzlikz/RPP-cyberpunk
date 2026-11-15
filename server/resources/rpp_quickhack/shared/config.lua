-- Настройки RP-квикхаков. Названия, иконки, стоимость ОЗУ, время загрузки и
-- перезарядку берёт штатный пресет open77_quickhack (shared/presets.lua);
-- здесь можно переопределить их и задать, что квикхак делает.
RppQuickhackConfig = {
    -- Короткое замыкание: разовый электрический урон.
    short_circuit = {
        enabled = true,
        targets = { "player", "npc", "vehicle" },
        damage = 25,             -- урон игроку / NPC
        engineOffSeconds = 4,    -- машина: на сколько глохнет двигатель
        effect = "cyber.electrocuted_body", -- на теле цели
        effectMs = 1500,
        sparks = "sparks.burst.small",       -- в точке цели
        -- ram = 5, upload = 1.5, cooldown = 8,  -- раскомментировать, чтобы поменять пресет
    },
    -- Перегрев: поджигает цель, урон огнём каждую секунду.
    overheat = {
        enabled = true,
        targets = { "player", "npc" },
        tickDamage = 6,          -- урон за тик
        ticks = 5,               -- сколько тиков (по 1 с)
        effect = "fire.small",
        -- ram = 5, upload = 1.8, cooldown = 10,
    },
}
