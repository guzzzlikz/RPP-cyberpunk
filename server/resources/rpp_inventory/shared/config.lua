-- rpp_inventory: настройки и каталог предметов.
--
-- Каталог читает только сервер: клиенту приходит уже готовое описание
-- каждого предмета (название, размер, иконка), поэтому подменить предмет
-- или его размер с клиента нельзя.
RppInventoryConfig = {
    -- Сетка рюкзака: 6 колонок x 12 строк.
    cols = 6,
    rows = 12,

    -- Клавиша открытия (игрок может переназначить в настройках клавиш Open77).
    key = { id = "rpp_inventory.toggle", name = "Инвентарь", key = "I" },
    -- Пытаться заблокировать штатный инвентарь игры, чтобы клавиша I не
    -- открывала оба сразу.
    blockVanillaInventory = true,

    -- Деньги нового персонажа и стартовый набор (id из RppItemDefs ниже или
    -- запись оружия Items.Preset_*).
    starterMoney = 500,
    starterItems = { "Items.Preset_Unity_Default", "junk_lighter", "item_bandage" },
    -- При первом открытии забрать в инвентарь одежду, которая уже надета
    -- на персонаже (как экипированную).
    importWornClothing = true,

    -- Оружие: три штатных слота Open77.
    weaponSlots = 3,
    -- Патроны в запасе, которые выдаются при экипировке (по классу оружия).
    reserveByClass = {
        handgun = 120, revolver = 60, smg = 240, rifle = 240, precision = 90,
        sniper = 40, shotgun = 60, dual = 60, lmg = 400,
    },
    -- Убрать оружие в кобуру после экипировки (иначе оно сразу в руках).
    holsterAfterEquip = true,

    -- Брошенные предметы.
    pickupDistance = 3.0,    -- м, с какого расстояния можно подобрать
    dropShowDistance = 60.0, -- м, на каком расстоянии клиент видит метку
    dropShowMax = 40,        -- меток на клиенте одновременно (лимит worldui 64)
    dropLifetimeMin = 30,    -- через сколько минут брошенное исчезает
    dropMax = 400,           -- всего брошенных предметов на сервере

    -- Не чаще стольких действий в секунду от одного игрока.
    actionsPerSecond = 8,
}

-- Размер оружия в ячейках (w x h) по классу из shared/weapons.lua.
RppWeaponSizes = {
    handgun   = { w = 2, h = 2, icon = "pistol",  label = "Пистолет" },
    revolver  = { w = 2, h = 2, icon = "pistol",  label = "Револьвер" },
    smg       = { w = 3, h = 2, icon = "smg",     label = "Пистолет-пулемёт" },
    rifle     = { w = 5, h = 2, icon = "rifle",   label = "Штурмовая винтовка" },
    precision = { w = 5, h = 2, icon = "rifle",   label = "Точная винтовка" },
    sniper    = { w = 6, h = 2, icon = "sniper",  label = "Снайперская винтовка" },
    shotgun   = { w = 5, h = 2, icon = "shotgun", label = "Дробовик" },
    dual      = { w = 4, h = 2, icon = "shotgun", label = "Двустволка" },
    lmg       = { w = 6, h = 3, icon = "lmg",     label = "Пулемёт" },
    blade     = { w = 5, h = 1, icon = "blade",   label = "Клинок" },
    knife     = { w = 2, h = 1, icon = "knife",   label = "Нож" },
    blunt     = { w = 4, h = 1, icon = "blunt",   label = "Дробящее" },
}

-- Слоты тела для одежды. `wire` — имя слота в Open77.clothing.set.
RppWearSlots = {
    { slot = "Head",       wire = "head",        label = "Голова" },
    { slot = "Face",       wire = "face",        label = "Лицо" },
    { slot = "OuterChest", wire = "outer_chest", label = "Верхняя одежда" },
    { slot = "InnerChest", wire = "inner_chest", label = "Торс" },
    { slot = "Legs",       wire = "legs",        label = "Ноги" },
    { slot = "Feet",       wire = "feet",        label = "Обувь" },
    { slot = "Outfit",     wire = "outfit",      label = "Комплект" },
}

-- Размер и иконка одежды по слоту (если у предмета не задано своё).
RppClothingSizes = {
    Head       = { w = 2, h = 1, icon = "hat" },
    Face       = { w = 2, h = 1, icon = "glasses" },
    OuterChest = { w = 2, h = 3, icon = "jacket" },
    InnerChest = { w = 2, h = 2, icon = "shirt" },
    Legs       = { w = 2, h = 3, icon = "pants" },
    Feet       = { w = 2, h = 2, icon = "boots" },
    Outfit     = { w = 3, h = 3, icon = "jacket" },
}

-- Предметы, которые не оружие. kind: clothing | junk | item.
-- Одежда: record — запись TweakDB (Items.*), slot — слот тела.
RppItemDefs = {
    -- Одежда
    cl_cap         = { kind = "clothing", label = "Кепка", record = "Items.Cap_01_basic_01", slot = "Head" },
    cl_balaclava   = { kind = "clothing", label = "Балаклава", record = "Items.Balaclava_01_basic_01", slot = "Head" },
    cl_glasses     = { kind = "clothing", label = "Очки", record = "Items.Glasses_01_basic_01", slot = "Face" },
    cl_jacket      = { kind = "clothing", label = "Куртка", record = "Items.Jacket_01_basic_01", slot = "OuterChest" },
    cl_formal      = { kind = "clothing", label = "Пиджак", record = "Items.FormalJacket_01_basic_01", slot = "OuterChest" },
    cl_tshirt      = { kind = "clothing", label = "Футболка", record = "Items.TShirt_01_basic_01", slot = "InnerChest" },
    cl_pants       = { kind = "clothing", label = "Штаны", record = "Items.Pants_01_basic_01", slot = "Legs" },
    cl_formalpants = { kind = "clothing", label = "Брюки", record = "Items.FormalPants_01_basic_01", slot = "Legs" },
    cl_boots       = { kind = "clothing", label = "Ботинки", record = "Items.Boots_01_basic_01", slot = "Feet" },

    -- Хлам
    junk_lighter   = { kind = "junk", label = "Зажигалка", w = 1, h = 1, icon = "junk", price = 5 },
    junk_cigs      = { kind = "junk", label = "Пачка сигарет", w = 1, h = 1, icon = "junk", price = 8 },
    junk_chip      = { kind = "junk", label = "Сгоревший чип", w = 1, h = 1, icon = "chip", price = 15 },
    junk_scrap     = { kind = "junk", label = "Электронный лом", w = 2, h = 1, icon = "junk", price = 20 },
    junk_bottle    = { kind = "junk", label = "Пустая бутылка", w = 1, h = 2, icon = "bottle", price = 2 },

    -- Предметы
    item_bandage   = { kind = "item", label = "Бинт", w = 1, h = 1, icon = "medkit" },
    item_medkit    = { kind = "item", label = "Аптечка", w = 2, h = 2, icon = "medkit" },
    item_shard     = { kind = "item", label = "Дата-шард", w = 1, h = 1, icon = "chip" },
    item_water     = { kind = "item", label = "Вода", w = 1, h = 2, icon = "bottle" },
}

-- Зоны киберимплантов (левый модуль, вкладка «Импланты»). Сейчас Open77
-- ставит импланты только на руки и ноги; остальные зоны показываются пустыми.
RppCyberZones = {
    { id = "os",       label = "Операционная система" },
    { id = "frontal",  label = "Лобная кора" },
    { id = "ocular",   label = "Глазные импланты" },
    { id = "circulatory", label = "Кровеносная система" },
    { id = "nervous",  label = "Нервная система" },
    { id = "skeleton", label = "Скелет" },
    { id = "integumentary", label = "Кожа" },
    { id = "hands",    label = "Кисти" },
    { id = "arms",     label = "Руки" },
    { id = "legs",     label = "Ноги" },
}
