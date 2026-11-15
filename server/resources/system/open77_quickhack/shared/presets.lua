-- Ready-made quickhack definitions with the game's names, costs and timings.
-- A server registers one with `exports.open77_quickhack:registerPreset("short_circuit", { ... })`.
-- The overrides are merged over the preset. Presets carry presentation and balance only. What a
-- quickhack DOES is always the registering resource's own code (its onExecute export or the
-- open77_quickhack:executed event). `impactSound` is the game's own sound event for that quickhack
-- (checked against the 2.31 audio metadata); the server plays it on the target when an upload lands.
QuickhackPresets = {
    breach_protocol = { label = "Breach Protocol", icon = "breach_protocol", category = "device", ram = 0, upload = 2.0, cooldown = 30,
        description = "Infiltrate the local subnet. Lowers the RAM cost of other quickhacks on this network." },
    ping = { impactSound = "quickhack_ping", label = "Ping", icon = "ping", category = "covert", ram = 2, upload = 1.0, cooldown = 10,
        description = "Reveals enemies and devices connected to the target's local network." },
    reboot_optics = { impactSound = "quickhack_reboot_optics", label = "Reboot Optics", icon = "reboot_optics", category = "covert", ram = 4, upload = 1.5, cooldown = 15,
        description = "Temporarily blinds the target." },
    memory_wipe = { impactSound = "quickhack_memory_wipe", label = "Memory Wipe", icon = "memory_wipe", category = "covert", ram = 6, upload = 2.0, cooldown = 30,
        description = "Makes the target forget about you." },
    sonic_shock = { impactSound = "quickhack_sonic_shock", label = "Sonic Shock", icon = "sonic_shock", category = "covert", ram = 3, upload = 1.0, cooldown = 12,
        description = "Deafens the target and cuts their communication." },
    request_backup = { impactSound = "quickhack_request_backup", label = "Request Backup", icon = "request_backup", category = "covert", ram = 2, upload = 1.0, cooldown = 20,
        description = "Calls the target's allies to its position." },
    distract = { label = "Distract Enemies", icon = "distract", category = "device", ram = 2, upload = 0.8, cooldown = 6,
        description = "Draws the attention of nearby people to the device." },
    cripple_movement = { impactSound = "quickhack_locomotion_malfunction", label = "Cripple Movement", icon = "cripple_movement", category = "control", ram = 4, upload = 1.5, cooldown = 15,
        description = "The target cannot move for a short time." },
    weapon_glitch = { impactSound = "quickhack_weapon_malfunction", label = "Weapon Glitch", icon = "weapon_glitch", category = "control", ram = 4, upload = 1.5, cooldown = 15,
        description = "The target's weapon jams and its smart link fails." },
    cyberware_malfunction = { impactSound = "quickhack_cyberware_malfunction", label = "Cyberware Malfunction", icon = "malfunction", category = "control", ram = 4, upload = 1.5, cooldown = 15,
        description = "Disables the target's cyberware." },
    short_circuit = { impactSound = "quickhack_shortcircuit", label = "Short Circuit", icon = "short_circuit", category = "damage", ram = 5, upload = 1.5, cooldown = 8,
        description = "Deals electrical damage. Effective against cyberware and mechanical targets." },
    overheat = { impactSound = "quickhack_overheat", label = "Overheat", icon = "overheat", category = "damage", ram = 5, upload = 1.8, cooldown = 10,
        description = "Sets the target on fire and deals burn damage over time." },
    contagion = { impactSound = "quickhack_contagion", label = "Contagion", icon = "contagion", category = "damage", ram = 5, upload = 1.5, cooldown = 12,
        description = "Poisons the target. Spreads to nearby enemies on the same network." },
    synapse_burnout = { impactSound = "quickhack_synapse_burnout", label = "Synapse Burnout", icon = "synapse_burnout", category = "damage", ram = 6, upload = 2.0, cooldown = 15,
        description = "Deals damage that rises the lower the target's health is." },
    system_reset = { impactSound = "quickhack_system_reset", label = "System Reset", icon = "system_reset", category = "ultimate", ram = 14, upload = 3.0, cooldown = 60,
        description = "Knocks the target unconscious without raising an alarm." },
    cyberpsychosis = { impactSound = "quickhack_cyberpsychosis", label = "Cyberpsychosis", icon = "cyberpsychosis", category = "ultimate", ram = 16, upload = 3.0, cooldown = 60,
        description = "Turns the target against everyone around it." },
    suicide = { label = "Suicide", icon = "suicide", category = "ultimate", ram = 18, upload = 3.5, cooldown = 90,
        description = "Forces the target to end its own life." },
    detonate_grenade = { label = "Detonate Grenade", icon = "detonate_grenade", category = "ultimate", ram = 14, upload = 2.5, cooldown = 60,
        description = "Detonates a grenade in the target's inventory." },
    takeover = { label = "Take Control", icon = "takeover", category = "device", ram = 3, upload = 1.0, cooldown = 5,
        description = "Takes control of the device." },
    malfunction = { label = "Malfunction", icon = "malfunction", category = "device", ram = 2, upload = 1.0, cooldown = 10,
        description = "Makes the device malfunction and damage people next to it." },
    overload = { label = "Overload", icon = "overload", category = "device", ram = 4, upload = 1.2, cooldown = 15,
        description = "Overloads the device's power supply." },
}

-- The game orders its list by category and colours the ultimates. The UI uses this order.
QuickhackCategories = { device = 1, covert = 2, control = 3, damage = 4, ultimate = 5 }
