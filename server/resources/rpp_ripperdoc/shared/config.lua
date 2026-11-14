-- rpp_ripperdoc: настройки и определения имплантов.
RppRipperdocConfig = {
    distance = 3.0,      -- м, на каком расстоянии от пациента можно оперировать
    consentSec = 120,    -- сколько действует согласие пациента
}

-- Определения имплантов этого ресурса. Грейды те же, что у кибер-лаборатории
-- (open77_cyberware_lab/server/config.lua), id свои: lab.* принадлежат лаборатории.
-- Предмет в инвентаре: cw_<slot>_<grade> (каталог rpp_inventory, RppImplantNames).
RppRipperdocConfig.definitions = {
    arms = {
        id = "rpp.gorilla", version = 1, slot = "arms", profile = "gorilla_arms",
        grades = {
            { id = "training", normalDamage = 15, chargedDamage = 35, knockbackMeters = 3.5,
                cooldownMs = 800, chargeMs = 650, nonlethal = true, cosmetic = false },
            { id = "industrial", normalDamage = 25, chargedDamage = 60, knockbackMeters = 4.5,
                cooldownMs = 1000, chargeMs = 800, nonlethal = false, cosmetic = false },
            { id = "cosmetic", normalDamage = 0, chargedDamage = 0, knockbackMeters = 0,
                cooldownMs = 800, chargeMs = 650, nonlethal = true, cosmetic = true },
        },
    },
    legs = {
        id = "rpp.double_jump", version = 1, slot = "legs", profile = "double_jump",
        grades = {
            { id = "training", normalDamage = 0, chargedDamage = 0, knockbackMeters = 0, cooldownMs = 800,
                chargeMs = 650, jumpStaminaCost = 15, maxAirborneMs = 10000, maxFallSpeed = 30 },
            { id = "athlete", normalDamage = 0, chargedDamage = 0, knockbackMeters = 0, cooldownMs = 500,
                chargeMs = 650, jumpStaminaCost = 8, maxAirborneMs = 10000, maxFallSpeed = 30 },
        },
    },
}

-- Стили рук гориллы (Glamdoc, Cyberpunk 2.5): характеристики тренировочных.
for _, style in ipairs({ "aldecaldos", "barghest", "jinguji", "militech", "mox", "tsunami",
    "tyger_claws", "voodoo_boys", "wraiths", "kang_tao" }) do
    local grades = RppRipperdocConfig.definitions.arms.grades
    grades[#grades + 1] = { id = style, normalDamage = 15, chargedDamage = 35, knockbackMeters = 3.5,
        cooldownMs = 800, chargeMs = 650, nonlethal = true, cosmetic = false, armStyle = style }
end

RppRipperdocConfig.slotLabels = { arms = "Руки", legs = "Ноги" }
