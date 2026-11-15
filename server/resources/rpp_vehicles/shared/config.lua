-- rpp_vehicles: настройки личных машин.
RppVehiclesConfig = {
    -- Сколько своих машин игрок может держать вызванными одновременно.
    maxSpawnedPerPlayer = 1,
    -- Где появляется вызванная машина относительно игрока (м, оси мира).
    spawnOffset = { x = 3.0, y = 0.0, z = 0.25 },
    -- Новая машина закрыта на замок.
    lockedOnSpawn = true,

    -- С какого расстояния (м) работают действия из ALT-меню.
    interactDistance = 6.0,
    -- Багажник: с какого расстояния открыть и дальше какого закрывается сам.
    trunkDistance = 4.0,
    trunkKeepDistance = 7.0,
    -- Вместимость багажника в ячейках инвентаря (рюкзак — 72).
    trunkCapacity = 40,
    -- «Припарковать» (ALT на машине): с какого расстояния (м); пассажиров быть не должно.
    parkDistance = 6.0,
    -- Убирать машину в гараж, когда владелец выходит с сервера.
    parkOnDisconnect = true,

    -- Автосалон: купленная машина сразу попадает в гараж (/garage).
    -- position — где стоит метка «Автосалон» (подойти и нажать E).
    dealership = {
        enabled = true,
        label = "Автосалон",
        position = { x = -1442.2, y = 127.4, z = 18.0 }, -- Westbrook (точка «dealer» freeroam)
        catalog = {
            { record = "Vehicle.v_standard2_makigai_maimai_player", label = "Makigai MaiMai", price = 8000 },
            { record = "Vehicle.v_standard2_archer_hella_player", label = "Archer Hella", price = 12000 },
            { record = "Vehicle.v_sport2_quadra_type66_player", label = "Quadra Type-66", price = 30000 },
            { record = "Vehicle.v_sport1_herrera_outlaw_player", label = "Herrera Outlaw", price = 45000 },
        },
    },

    -- Прокат: временная машина на выбранный срок. Пока аренда идёт, у
    -- арендатора права как у владельца (замок, багажник, высадка, ключи).
    -- Когда срок вышел или игрок вышел с сервера — машина исчезает вместе
    -- с вещами в багажнике.
    rental = {
        enabled = true,
        label = "Прокат машин",
        position = { x = -1428.6, y = 1252.8, z = 22.9 }, -- Watson, у точки появления
        minutes = { 15, 30, 60 },  -- сроки на выбор
        warnBeforeEndSec = 120,    -- предупредить, что аренда скоро кончится
        catalog = {
            { record = "Vehicle.v_standard2_makigai_maimai_player", label = "Makigai MaiMai", pricePerMinute = 10 },
            { record = "Vehicle.v_standard2_archer_hella_player", label = "Archer Hella", pricePerMinute = 15 },
            { record = "Vehicle.v_sport2_quadra_type66_player", label = "Quadra Type-66", pricePerMinute = 30 },
        },
    },

    -- С какого расстояния (м) от метки открывается окно салона / проката.
    promptDistance = 2.5,
    -- Метки автосалона и проката на карте.
    blips = true,

    -- Названия моделей для списков (необязательно). Модель без названия
    -- показывается как запись без «Vehicle.»: v_standard2_archer_hella_player.
    labels = {
        ["Vehicle.v_standard2_archer_hella_player"] = "Archer Hella",
        ["Vehicle.v_standard2_makigai_maimai_player"] = "Makigai MaiMai",
        ["Vehicle.v_sport2_quadra_type66_player"] = "Quadra Type-66",
        ["Vehicle.v_sport1_herrera_outlaw_player"] = "Herrera Outlaw",
    },
}
