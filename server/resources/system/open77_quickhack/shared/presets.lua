-- Ready-made quickhack definitions with the game's names, costs and timings.
-- A server registers one with `exports.open77_quickhack:registerPreset("short_circuit", { ... })`.
-- The overrides are merged over the preset. Presets carry presentation and balance only. What a
-- quickhack DOES is always the registering resource's own code (its onExecute export or the
-- open77_quickhack:executed event). `impactSound` is the game's own sound event for that quickhack
-- (checked against the 2.31 audio metadata); the server plays it on the target when an upload lands.
QuickhackPresets = {
    breach_protocol = { label = "Протокол взлома", icon = "breach_protocol", category = "device", ram = 0, upload = 2.0, cooldown = 30,
        description = "Проникновение в локальную подсеть. Снижает расход ОЗУ на другие скрипты в этой сети." },
    ping = { impactSound = "quickhack_ping", label = "Пинг", icon = "ping", category = "covert", ram = 2, upload = 1.0, cooldown = 10,
        description = "Показывает врагов и устройства в локальной сети цели." },
    reboot_optics = { impactSound = "quickhack_reboot_optics", label = "Перезагрузка оптики", icon = "reboot_optics", category = "covert", ram = 4, upload = 1.5, cooldown = 15,
        description = "Временно ослепляет цель." },
    memory_wipe = { impactSound = "quickhack_memory_wipe", label = "Стирание памяти", icon = "memory_wipe", category = "covert", ram = 6, upload = 2.0, cooldown = 30,
        description = "Цель забывает о вас." },
    sonic_shock = { impactSound = "quickhack_sonic_shock", label = "Звуковой шок", icon = "sonic_shock", category = "covert", ram = 3, upload = 1.0, cooldown = 12,
        description = "Оглушает цель и обрывает её связь." },
    request_backup = { impactSound = "quickhack_request_backup", label = "Вызов подкрепления", icon = "request_backup", category = "covert", ram = 2, upload = 1.0, cooldown = 20,
        description = "Вызывает союзников цели к её позиции." },
    distract = { label = "Отвлечь врагов", icon = "distract", category = "device", ram = 2, upload = 0.8, cooldown = 6,
        description = "Привлекает к устройству внимание людей рядом." },
    cripple_movement = { impactSound = "quickhack_locomotion_malfunction", label = "Обездвиживание", icon = "cripple_movement", category = "control", ram = 4, upload = 1.5, cooldown = 15,
        description = "Цель ненадолго не может двигаться." },
    weapon_glitch = { impactSound = "quickhack_weapon_malfunction", label = "Сбой оружия", icon = "weapon_glitch", category = "control", ram = 4, upload = 1.5, cooldown = 15,
        description = "Оружие цели заклинивает, смарт-связь отказывает." },
    cyberware_malfunction = { impactSound = "quickhack_cyberware_malfunction", label = "Сбой киберимплантов", icon = "malfunction", category = "control", ram = 4, upload = 1.5, cooldown = 15,
        description = "Отключает киберимпланты цели." },
    short_circuit = { impactSound = "quickhack_shortcircuit", label = "Короткое замыкание", icon = "short_circuit", category = "damage", ram = 5, upload = 1.5, cooldown = 8,
        description = "Наносит электрический урон. Эффективно против киберимплантов и механических целей." },
    overheat = { impactSound = "quickhack_overheat", label = "Перегрев", icon = "overheat", category = "damage", ram = 5, upload = 1.8, cooldown = 10,
        description = "Поджигает цель и наносит урон огнём со временем." },
    contagion = { impactSound = "quickhack_contagion", label = "Заражение", icon = "contagion", category = "damage", ram = 5, upload = 1.5, cooldown = 12,
        description = "Отравляет цель. Переходит на ближайших врагов в той же сети." },
    synapse_burnout = { impactSound = "quickhack_synapse_burnout", label = "Синаптический ожог", icon = "synapse_burnout", category = "damage", ram = 6, upload = 2.0, cooldown = 15,
        description = "Урон тем выше, чем меньше у цели здоровья." },
    system_reset = { impactSound = "quickhack_system_reset", label = "Сброс системы", icon = "system_reset", category = "ultimate", ram = 14, upload = 3.0, cooldown = 60,
        description = "Тихо вырубает цель, не поднимая тревоги." },
    cyberpsychosis = { impactSound = "quickhack_cyberpsychosis", label = "Киберпсихоз", icon = "cyberpsychosis", category = "ultimate", ram = 16, upload = 3.0, cooldown = 60,
        description = "Натравливает цель на всех вокруг." },
    suicide = { label = "Самоубийство", icon = "suicide", category = "ultimate", ram = 18, upload = 3.5, cooldown = 90,
        description = "Заставляет цель покончить с собой." },
    detonate_grenade = { label = "Подрыв гранаты", icon = "detonate_grenade", category = "ultimate", ram = 14, upload = 2.5, cooldown = 60,
        description = "Взрывает гранату в инвентаре цели." },
    takeover = { label = "Взять под контроль", icon = "takeover", category = "device", ram = 3, upload = 1.0, cooldown = 5,
        description = "Перехватывает управление устройством." },
    malfunction = { label = "Неисправность", icon = "malfunction", category = "device", ram = 2, upload = 1.0, cooldown = 10,
        description = "Устройство выходит из строя и ранит людей рядом." },
    overload = { label = "Перегрузка", icon = "overload", category = "device", ram = 4, upload = 1.2, cooldown = 15,
        description = "Перегружает питание устройства." },
}

-- The game orders its list by category and colours the ultimates. The UI uses this order.
QuickhackCategories = { device = 1, covert = 2, control = 3, damage = 4, ultimate = 5 }
