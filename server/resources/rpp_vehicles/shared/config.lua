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

    -- Названия моделей для списков (необязательно). Модель без названия
    -- показывается как запись без «Vehicle.»: v_standard2_archer_hella_player.
    labels = {
        ["Vehicle.v_standard2_archer_hella_player"] = "Archer Hella",
        ["Vehicle.v_standard2_makigai_maimai_player"] = "Makigai MaiMai",
        ["Vehicle.v_sport2_quadra_type66_player"] = "Quadra Type-66",
        ["Vehicle.v_sport1_herrera_outlaw_player"] = "Herrera Outlaw",
    },
}
