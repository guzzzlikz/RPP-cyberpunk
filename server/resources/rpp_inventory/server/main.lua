-- rpp_inventory, серверная часть. Сервер — единственный источник правды:
-- он раскладывает предметы по сетке, решает, влезает ли предмет, выдаёт и
-- снимает оружие и одежду и ведёт брошенные на землю предметы.
--
-- Экземпляр предмета: { uid, id, x, y, meta? }
--   id   — ключ в RppItemDefs или запись оружия (Items.Preset_*);
--   x, y — левый верхний угол в сетке (с нуля), только для предметов в рюкзаке;
--   meta — { record, slot, label } для одежды не из каталога (забрана с персонажа).
local cfg = RppInventoryConfig
local RESOURCE = GetCurrentResourceName()
local COLS, ROWS = cfg.cols, cfg.rows

local inv = {}        -- [playerId] = { guid, money, nextUid, items = {uid=inst}, weapons = {[slot]=inst}, wear = {[slot]=inst}, importWear }
local loading = {}    -- [playerId] = true
local dirty = {}      -- [playerId] = true, если надо сохранить
local actions = {}    -- [playerId] = { second, count }
local pending = {}    -- [tostring(requestId)] = { playerId, kind, slot, reserve }
local drops = {}      -- [dropId] = { id, inst, x, y, z, bucket, expires }
local dropCount, nextDropId = 0, 1
local sentDrops = {}  -- [playerId] = подпись последнего отправленного списка
local trades = {}     -- [tradeId] = обмен (см. раздел «Обмен» ниже)
local playerTrade = {} -- [playerId] = tradeId

local WEAR = {}       -- [slot] = { wire, label }
for _, row in ipairs(RppWearSlots) do WEAR[row.slot] = row end

local function log(text) print("[" .. RESOURCE .. "] " .. text) end
local function now() return Open77.time.monotonic() end

local function notify(player, kind, message)
    local ok, err = pcall(Open77.notifications.send, player, {
        type = kind, title = "Инвентарь", message = message,
        durationMs = kind == "error" and 5000 or 4000,
    })
    if not ok then log("notification failed: " .. tostring(err)) end
end

local function reply(player, raw, ok, message)
    if player == nil or player <= 0 then print(message); return end
    TriggerClientEvent("open77:command:result", player, raw, ok, message)
end

-- ---------------------------------------------------------------------------
-- Каталог
-- ---------------------------------------------------------------------------
--- Описание предмета для экземпляра: kind, label, w, h, icon и т. д. nil — неизвестный.
local function describe(id, meta)
    local def = RppItemDefs[id]
    if def then
        if def.kind == "clothing" then
            local size = RppClothingSizes[def.slot] or { w = 2, h = 2, icon = "shirt" }
            return { kind = "clothing", label = def.label, w = def.w or size.w, h = def.h or size.h,
                icon = def.icon or size.icon, record = def.record, slot = def.slot,
                sub = (WEAR[def.slot] and WEAR[def.slot].label) or "Одежда" }
        end
        return { kind = def.kind, label = def.label, w = def.w or 1, h = def.h or 1, icon = def.icon or "junk",
            sub = ({ junk = "Хлам", resource = "Ресурс", food = "Еда", implant = "Киберимплант" })[def.kind] or "Предмет", price = def.price }
    end
    local class = RppWeaponCatalog.classOfRecord(id)
    if class then
        local size = RppWeaponSizes[class.key] or { w = 3, h = 2, icon = "rifle", label = class.label }
        return { kind = "weapon", label = RppWeaponCatalog.nameOf(id), w = size.w, h = size.h, icon = size.icon,
            record = id, class = class.key, sub = size.label, ammo = class.ammo == true }
    end
    -- Оружие не из каталога (выдано мимо инвентаря, например меню /freeroam).
    if id == "weapon" and type(meta) == "table" and type(meta.record) == "string" then
        local size = RppWeaponSizes.rifle
        return { kind = "weapon", label = tostring(meta.label or meta.record), w = 3, h = 2, icon = size.icon,
            record = meta.record, class = "unknown", sub = "Оружие", ammo = false }
    end
    if id == "clothing" and type(meta) == "table" and WEAR[meta.slot] then
        local size = RppClothingSizes[meta.slot] or { w = 2, h = 2, icon = "shirt" }
        return { kind = "clothing", label = tostring(meta.label or "Одежда"), w = size.w, h = size.h,
            icon = size.icon, record = meta.record, slot = meta.slot, sub = WEAR[meta.slot].label }
    end
    return nil
end

--- Ищет id предмета по тексту команды: ключ каталога, запись оружия или кусок названия.
local function resolveItemId(text)
    if type(text) ~= "string" or text == "" then return nil end
    if RppItemDefs[text] or RppWeaponCatalog.index[text] then return text end
    if RppWeaponCatalog.index["Items." .. text] then return "Items." .. text end
    if RppWeaponCatalog.index["Items.Preset_" .. text] then return "Items.Preset_" .. text end
    local needle = text:lower()
    for position, name in ipairs(RppWeaponCatalog.names) do
        if name:lower() == needle then return RppWeaponCatalog.records[position] end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Сетка
-- ---------------------------------------------------------------------------
local function sizeOf(inst)
    local d = describe(inst.id, inst.meta)
    return d and d.w or 1, d and d.h or 1
end

local function fits(state, w, h, x, y, ignoreUid)
    if x < 0 or y < 0 or x + w > COLS or y + h > ROWS then return false end
    for uid, other in pairs(state.items) do
        if uid ~= ignoreUid then
            local ow, oh = sizeOf(other)
            if x < other.x + ow and other.x < x + w and y < other.y + oh and other.y < y + h then
                return false
            end
        end
    end
    return true
end

--- Первое свободное место (сверху вниз, слева направо) или nil.
local function findSpot(state, w, h, ignoreUid)
    for y = 0, ROWS - h do
        for x = 0, COLS - w do
            if fits(state, w, h, x, y, ignoreUid) then return x, y end
        end
    end
    return nil
end

local function newInst(state, id, meta)
    local uid = state.nextUid
    state.nextUid = uid + 1
    return { uid = uid, id = id, meta = meta }
end

--- Кладёт экземпляр в рюкзак на первое свободное место. false, если не влез.
--- Раскладывает список предметов заново, каждый — на первое свободное место
--- (сверху вниз, слева направо). false, если какой-то не влез.
local function packList(state, list)
    state.items = {}
    for _, inst in ipairs(list) do
        local w, h = sizeOf(inst)
        local x, y = findSpot(state, w, h)
        if not x then return false end
        inst.x, inst.y = x, y
        state.items[inst.uid] = inst
    end
    return true
end

--- Сдвигает предметы к верхнему левому углу. Сначала в прежнем порядке
--- (как читается сетка), если так не влезает — от крупных к мелким. Если
--- не выходит ни так, ни так, раскладка остаётся прежней. `extra` —
--- предмет, который надо добавить. true, если всё (и extra) уместилось.
local function compact(state, extra)
    local list, saved = {}, {}
    for _, inst in pairs(state.items) do
        list[#list + 1] = inst
        saved[#saved + 1] = { inst = inst, x = inst.x, y = inst.y }
    end
    table.sort(list, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.uid < b.uid
    end)
    if extra then list[#list + 1] = extra end
    if packList(state, list) then return true end
    local bySize = {}
    for index, inst in ipairs(list) do bySize[index] = inst end
    table.sort(bySize, function(a, b)
        local aw, ah = sizeOf(a)
        local bw, bh = sizeOf(b)
        if aw * ah ~= bw * bh then return aw * ah > bw * bh end
        if aw ~= bw then return aw > bw end
        return a.uid < b.uid
    end)
    if packList(state, bySize) then return true end
    state.items = {}
    for _, row in ipairs(saved) do
        row.inst.x, row.inst.y = row.x, row.y
        state.items[row.inst.uid] = row.inst
    end
    if extra then extra.x, extra.y = nil, nil end
    return false
end

--- Кладёт экземпляр в рюкзак. Если свободного места нужной формы нет,
--- пробует переложить остальное плотнее. false, если не влез.
local function putInBag(state, inst)
    local w, h = sizeOf(inst)
    local x, y = findSpot(state, w, h)
    if x then
        inst.x, inst.y = x, y
        state.items[inst.uid] = inst
        return true
    end
    return compact(state, inst)
end

-- ---------------------------------------------------------------------------
-- Сохранение и отправка состояния
-- ---------------------------------------------------------------------------
local function serialize(state)
    local data = { v = 1, nextUid = state.nextUid, items = {}, weapons = {}, wear = {}, importWear = state.importWear }
    for _, inst in pairs(state.items) do
        data.items[#data.items + 1] = { uid = inst.uid, id = inst.id, x = inst.x, y = inst.y, meta = inst.meta }
    end
    for slot, inst in pairs(state.weapons) do
        data.weapons[#data.weapons + 1] = { slot = slot, uid = inst.uid, id = inst.id, meta = inst.meta }
    end
    for slot, inst in pairs(state.wear) do
        data.wear[#data.wear + 1] = { slot = slot, uid = inst.uid, id = inst.id, meta = inst.meta }
    end
    return data
end

local function markDirty(playerId) dirty[playerId] = true end

local function flush(playerId)
    local state = inv[playerId]
    if not state or not dirty[playerId] then return end
    dirty[playerId] = nil
    local ok, err = RppInvStore.save(state.guid, state.money, serialize(state))
    if not ok then
        dirty[playerId] = true
        log("save failed for " .. tostring(playerId) .. ": " .. tostring(err))
    end
end

local function view(inst)
    local d = describe(inst.id, inst.meta) or { kind = "junk", label = "?", w = 1, h = 1, icon = "junk" }
    return { uid = inst.uid, x = inst.x, y = inst.y, w = d.w, h = d.h, kind = d.kind, label = d.label,
        icon = d.icon, sub = d.sub, slot = d.slot, class = d.class, price = d.price }
end

local function cyberView(playerId)
    local zones = {}
    local record = nil
    if type(Open77.cyberware) == "table" and type(Open77.cyberware.current) == "function" then
        local ok, value = pcall(Open77.cyberware.current, playerId)
        if ok and type(value) == "table" then record = value end
    end
    local function installed(part)
        local entry = record and record[part]
        if type(entry) ~= "table" then return nil end
        local gradeId = type(entry.grade) == "table" and (entry.grade.id or entry.grade.label) or entry.grade
        local names = RppImplantNames and RppImplantNames[part]
        local grade = names and gradeId and names.grades[gradeId] or gradeId
        local name = names and names.name or entry.label or entry.name or entry.definition or entry.profile or "Имплант"
        return { name = tostring(name), grade = grade and tostring(grade) or nil }
    end
    for _, zone in ipairs(RppCyberZones) do
        local item = (zone.id == "arms" or zone.id == "legs") and installed(zone.id) or nil
        zones[#zones + 1] = { id = zone.id, label = zone.label, item = item }
    end
    return zones
end

local function pushState(playerId, withCyber)
    local state = inv[playerId]
    if not state then return end
    local items, weapons, wear = {}, {}, {}
    local trade = playerTrade[playerId] and trades[playerTrade[playerId]]
    local offered = trade and trade.offer[playerId] and trade.offer[playerId].items or {}
    for uid, inst in pairs(state.items) do
        local v = view(inst)
        if offered[uid] then v.offered = true end
        items[#items + 1] = v
    end
    for slot = 1, cfg.weaponSlots do
        local inst = state.weapons[slot]
        if inst then local v = view(inst); v.equippedSlot = slot; weapons[#weapons + 1] = v end
    end
    for slot, inst in pairs(state.wear) do local v = view(inst); v.wornSlot = slot; wear[#wear + 1] = v end
    local wearSlots = {}
    for _, row in ipairs(RppWearSlots) do wearSlots[#wearSlots + 1] = { slot = row.slot, label = row.label } end
    TriggerClientEvent("rpp_inventory:state", playerId, {
        cols = COLS, rows = ROWS, money = state.money, items = items,
        weapons = weapons, weaponSlots = cfg.weaponSlots, wear = wear, wearSlots = wearSlots,
        cyber = withCyber and cyberView(playerId) or nil,
    })
end

-- ---------------------------------------------------------------------------
-- Оружие и одежда на персонаже
-- ---------------------------------------------------------------------------
-- Когда инвентарь сам последний раз менял слот: [playerId]["w1"|"cHead"] = секунды.
-- Свежие изменения не сверяются с игрой, пока игра их не применила.
local touched = {}
local TOUCH_GRACE = 8
local function touch(playerId, key)
    touched[playerId] = touched[playerId] or {}
    touched[playerId][key] = now()
end
local function recentlyTouched(playerId, key)
    local at = touched[playerId] and touched[playerId][key]
    return at ~= nil and now() - at < TOUCH_GRACE
end

local function weaponsApi() return type(Open77.weapons) == "table" and type(Open77.weapons.assign) == "function" end

local function assignWeapon(playerId, slot, inst)
    if not weaponsApi() then return false, "weapons_unavailable" end
    local d = describe(inst.id, inst.meta)
    touch(playerId, "w" .. slot)
    local requestId, reason = Open77.weapons.assign(playerId, d.record, slot, { active = true, addToInventory = true })
    if requestId == nil then return false, reason end
    pending[tostring(requestId)] = {
        playerId = playerId, kind = "assign", slot = slot,
        reserve = d.ammo and (cfg.reserveByClass[d.class] or 0) or 0,
        at = now(),
    }
    return true
end

local function removeWeapon(playerId, slot)
    if not weaponsApi() then return end
    touch(playerId, "w" .. slot)
    local requestId = Open77.weapons.remove(playerId, slot)
    if requestId ~= nil then pending[tostring(requestId)] = { playerId = playerId, kind = "remove", slot = slot, at = now() } end
end

AddEventHandler("open77:weapons:completed", function(playerId, requestId, operation, accepted, reason)
    playerId = tonumber(playerId)
    local key = tostring(requestId)
    local entry = pending[key]
    if entry == nil or entry.playerId ~= playerId then return end
    pending[key] = nil
    if accepted ~= true then
        if entry.kind == "assign" then
            log(("weapon assign for %d slot %d failed: %s"):format(playerId, entry.slot, tostring(reason)))
            notify(playerId, "error", "Не удалось взять оружие в руки: " .. tostring(reason))
        end
        return
    end
    if entry.kind == "assign" then
        if entry.reserve > 0 then
            local ammoId = Open77.weapons.setAmmo(playerId, entry.slot, { reserve = entry.reserve, activate = true })
            if ammoId ~= nil then
                pending[tostring(ammoId)] = { playerId = playerId, kind = "ammo", slot = entry.slot, at = now() }
                return
            end
        end
        entry.kind = "ammo"
    end
    if entry.kind == "ammo" and cfg.holsterAfterEquip and type(Open77.weapons.holster) == "function" then
        pcall(Open77.weapons.holster, playerId)
    end
end)

local function setClothing(playerId, slot, record)
    if type(Open77.clothing) ~= "table" or type(Open77.clothing.set) ~= "function" then return false end
    local wear = WEAR[slot]
    if not wear then return false end
    touch(playerId, "c" .. slot)
    local ok, result = pcall(Open77.clothing.set, playerId, { [wear.wire] = record or false })
    if not ok or result == nil then
        log(("clothing set %s for %d failed: %s"):format(slot, playerId, tostring(result)))
        return false
    end
    return true
end

--- Выдаёт персонажу всё, что записано экипированным (после входа в мир).
local function applyLoadout(playerId)
    local state = inv[playerId]
    if not state then return end
    for slot = 1, cfg.weaponSlots do
        local inst = state.weapons[slot]
        if inst then assignWeapon(playerId, slot, inst) end
    end
end

-- ---------------------------------------------------------------------------
-- Загрузка игрока
-- ---------------------------------------------------------------------------
local function fromData(state, data)
    local maxUid = 0
    local function inst(row)
        if type(row) ~= "table" or type(row.id) ~= "string" then return nil end
        local meta = type(row.meta) == "table" and row.meta or nil
        if not describe(row.id, meta) then return nil end
        local uid = math.floor(tonumber(row.uid) or 0)
        if uid <= 0 then return nil end
        if uid > maxUid then maxUid = uid end
        return { uid = uid, id = row.id, meta = meta }
    end
    local lost = {}
    for _, row in ipairs(type(data.items) == "table" and data.items or {}) do
        local item = inst(row)
        if item then
            local w, h = sizeOf(item)
            local x, y = math.floor(tonumber(row.x) or -1), math.floor(tonumber(row.y) or -1)
            if fits(state, w, h, x, y) then
                item.x, item.y = x, y
                state.items[item.uid] = item
            else
                lost[#lost + 1] = item -- размер поменяли в конфиге: переложить
            end
        end
    end
    for _, row in ipairs(type(data.weapons) == "table" and data.weapons or {}) do
        local item, slot = inst(row), math.floor(tonumber(row.slot) or 0)
        if item and describe(item.id, item.meta).kind == "weapon" and slot >= 1 and slot <= cfg.weaponSlots then
            state.weapons[slot] = item
        end
    end
    for _, row in ipairs(type(data.wear) == "table" and data.wear or {}) do
        local item = inst(row)
        local d = item and describe(item.id, item.meta)
        if d and d.kind == "clothing" and row.slot == d.slot then state.wear[d.slot] = item end
    end
    state.nextUid = math.max(math.floor(tonumber(data.nextUid) or 1), maxUid + 1)
    state.importWear = data.importWear == true
    for _, item in ipairs(lost) do
        if not putInBag(state, item) then log(("item %s of %s did not fit after reload, dropped"):format(item.id, state.guid)) end
    end
end

local function load(playerId)
    if not playerId then return nil end
    while loading[playerId] do Wait(20) end
    if inv[playerId] then return inv[playerId] end
    local guid = GetPlayerIdentifier(playerId)
    if guid == nil or guid == "" then return nil end
    loading[playerId] = true
    local ok, record, err = pcall(RppInvStore.load, guid)
    loading[playerId] = nil
    if not ok or err then
        log("inventory load failed for " .. tostring(playerId) .. ": " .. tostring(ok and err or record))
        return nil
    end
    local state = { guid = guid, money = 0, nextUid = 1, items = {}, weapons = {}, wear = {} }
    if record then
        state.money = math.max(0, math.floor(record.money))
        fromData(state, record.data)
    else
        state.money = cfg.starterMoney
        for _, id in ipairs(cfg.starterItems) do
            local real = resolveItemId(id)
            if real then putInBag(state, newInst(state, real)) else log("unknown starter item " .. tostring(id)) end
        end
        state.importWear = cfg.importWornClothing == true
        dirty[playerId] = true
    end
    inv[playerId] = state
    return state
end

-- ---------------------------------------------------------------------------
-- Действия игрока
-- ---------------------------------------------------------------------------
local function allowed(playerId)
    local second = math.floor(now())
    local row = actions[playerId]
    if not row or row.second ~= second then row = { second = second, count = 0 }; actions[playerId] = row end
    row.count = row.count + 1
    return row.count <= cfg.actionsPerSecond
end

-- Во время обмена нельзя ничего выбрасывать, надевать и снимать: иначе
-- предмет из предложения мог бы исчезнуть из рюкзака в последний момент.
local TRADE_BLOCKED = { drop = true, equipWeapon = true, equipClothing = true, unequip = true }

--- Обёртка обработчика: игрок, загрузка, лимит, затем сохранение и отправка.
local function action(name, handler)
    RegisterNetEvent("rpp_inventory:" .. name, function(...)
        local playerId = tonumber(source)
        if not playerId or not allowed(playerId) then return end
        local args = table.pack(...)
        CreateThread(function()
            local state = load(playerId)
            if not state then return end
            if TRADE_BLOCKED[name] and playerTrade[playerId] then
                notify(playerId, "error", "Во время обмена нельзя выбрасывать, надевать и снимать вещи.")
                pushState(playerId, false)
                return
            end
            local okCall, changed, message = pcall(handler, playerId, state, table.unpack(args, 1, args.n))
            if not okCall then
                log(name .. " failed: " .. tostring(changed))
                changed, message = false, "Внутренняя ошибка инвентаря."
            end
            if message then notify(playerId, changed and "success" or "error", message) end
            if changed then markDirty(playerId) end
            pushState(playerId, name == "open")
        end)
    end)
end

local function int(value)
    value = tonumber(value)
    if value == nil or value ~= value or value % 1 ~= 0 then return nil end
    return value
end


action("hello", function(playerId, state)
    applyLoadout(playerId)
    if state.importWear then TriggerClientEvent("rpp_inventory:requestWear", playerId) end
    sentDrops[playerId] = nil
    return false
end)

-- Одежда, надетая до первого входа (только один раз на персонажа).
action("wearSnapshot", function(playerId, state, slots)
    if not state.importWear or type(slots) ~= "table" then return false end
    state.importWear = false
    local taken = 0
    for slot, record in pairs(slots) do
        if WEAR[slot] and not state.wear[slot] and type(record) == "string"
            and #record <= 128 and record:match("^Items%.[%w_]+$") then
            local id, meta = "clothing", nil
            for key, def in pairs(RppItemDefs) do
                if def.kind == "clothing" and def.record == record then id = key; break end
            end
            if id == "clothing" then
                local pretty = record:gsub("^Items%.", ""):gsub("_", " ")
                meta = { record = record, slot = slot, label = pretty }
            end
            state.wear[slot] = newInst(state, id, meta)
            taken = taken + 1
        end
    end
    if taken > 0 then log(("imported %d worn clothing item(s) for %d"):format(taken, playerId)) end
    return true
end)

action("move", function(_, state, uid, x, y)
    uid, x, y = int(uid), int(x), int(y)
    local inst = uid and state.items[uid]
    if not inst or not x or not y then return false end
    local w, h = sizeOf(inst)
    if x < 0 or y < 0 or x + w > COLS or y + h > ROWS then return false end
    if fits(state, w, h, x, y, uid) then
        inst.x, inst.y = x, y
        return true
    end
    -- Брошен на другой предмет: если он там один и встаёт на старое место
    -- перетаскиваемого, предметы меняются местами.
    local hit = nil
    for otherUid, other in pairs(state.items) do
        if otherUid ~= uid then
            local ow, oh = sizeOf(other)
            if x < other.x + ow and other.x < x + w and y < other.y + oh and other.y < y + h then
                if hit then return false end
                hit = other
            end
        end
    end
    if not hit then return false end
    local ax, ay, bx, by = inst.x, inst.y, hit.x, hit.y
    local bw, bh = sizeOf(hit)
    inst.x, inst.y = x, y
    hit.x, hit.y = -100, -100
    if fits(state, bw, bh, ax, ay, hit.uid) then
        hit.x, hit.y = ax, ay
        return true
    end
    inst.x, inst.y, hit.x, hit.y = ax, ay, bx, by
    return false
end)

-- Кнопка «Упорядочить»: уплотнить рюкзак к верхнему левому углу.
action("sort", function(_, state)
    return compact(state)
end)

action("equipWeapon", function(playerId, state, uid, slot)
    uid, slot = int(uid), int(slot)
    local inst = uid and state.items[uid]
    if not inst or not slot or slot < 1 or slot > cfg.weaponSlots then return false end
    local d = describe(inst.id, inst.meta)
    if d.kind ~= "weapon" then return false, "Это не оружие." end
    if not weaponsApi() then return false, "Оружие недоступно на этом сервере." end
    local old = state.weapons[slot]
    state.items[uid] = nil
    if old then
        -- Старое оружие из слота возвращается в рюкзак; место нового уже свободно.
        if not putInBag(state, old) then
            state.items[uid] = inst
            return false, "Нет места в рюкзаке для " .. describe(old.id, old.meta).label .. "."
        end
    end
    inst.x, inst.y = nil, nil
    state.weapons[slot] = inst
    assignWeapon(playerId, slot, inst)
    return true, old and (d.label .. " в слоте " .. slot .. " вместо " .. describe(old.id, old.meta).label .. ".")
        or (d.label .. " в слоте " .. slot .. ".")
end)

action("equipClothing", function(playerId, state, uid)
    uid = int(uid)
    local inst = uid and state.items[uid]
    if not inst then return false end
    local d = describe(inst.id, inst.meta)
    if d.kind ~= "clothing" then return false, "Это нельзя надеть." end
    local old = state.wear[d.slot]
    state.items[uid] = nil
    if old and not putInBag(state, old) then
        state.items[uid] = inst
        return false, "Нет места в рюкзаке, чтобы снять " .. describe(old.id, old.meta).label .. "."
    end
    inst.x, inst.y = nil, nil
    state.wear[d.slot] = inst
    if not setClothing(playerId, d.slot, d.record) then
        notify(playerId, "warning", "Одежда записана, но персонаж её пока не надел.")
    end
    return true
end)

action("unequip", function(playerId, state, where, key)
    if where == "weapon" then
        local slot = int(key)
        local inst = slot and state.weapons[slot]
        if not inst then return false end
        if not putInBag(state, inst) then return false, "Рюкзак полон." end
        state.weapons[slot] = nil
        removeWeapon(playerId, slot)
        return true
    elseif where == "wear" and WEAR[key] then
        local inst = state.wear[key]
        if not inst then return false end
        if not putInBag(state, inst) then return false, "Рюкзак полон." end
        state.wear[key] = nil
        setClothing(playerId, key, false)
        return true
    end
    return false
end)

-- ---------------------------------------------------------------------------
-- Брошенные предметы
-- ---------------------------------------------------------------------------
local function playerPos(playerId)
    local ok, pos = pcall(Open77.players.position, playerId)
    if not ok or type(pos) ~= "table" or tonumber(pos.x) == nil then return nil end
    return pos
end

-- Модель предмета на земле: лут Open77 (Open77.loot). У дропа два разных
-- параметра: `visualItem` — какая модель лежит (запись оружия/одежды), и
-- `item` — что игра выдаст при подборе. Настоящий предмет кладёт в
-- инвентарь этот ресурс (onLootPickup ниже), а игра выдаёт только
-- cfg.dropLootGrant (1 €$ в кошелёк игры) — его не убрать: подбор лута
-- всегда что-то выдаёт.
local lootDrops = {} -- [tostring(lootId)] = dropId

local function lootApi()
    return cfg.dropModels and type(Open77.loot) == "table" and type(Open77.loot.create) == "function"
end

local function spawnLoot(drop)
    if not lootApi() then return end
    local d = describe(drop.inst.id, drop.inst.meta)
    if not d or not d.record or (d.kind ~= "weapon" and d.kind ~= "clothing") then return end
    local ok, lootId, reason = pcall(Open77.loot.create, {
        item = cfg.dropLootGrant, quantity = 1,
        position = { x = drop.x, y = drop.y, z = drop.z }, bucket = drop.bucket or 0,
        -- Без своей подписи: игра покажет название предмета сама (подпись Open77
        -- рисовалась бы нативным шрифтом без кириллицы).
        radius = cfg.pickupDistance, visualItem = d.record,
        ttlMs = math.floor(math.max(0, drop.expires - now()) * 1000),
    })
    if ok and lootId ~= nil and lootId ~= false then
        drop.lootId = lootId
        lootDrops[tostring(lootId)] = drop.id
    else
        log("loot model for drop " .. drop.id .. " failed: " .. tostring(ok and reason or lootId))
    end
end

local function removeDrop(id)
    local drop = drops[id]
    if not drop then return end
    drops[id] = nil
    dropCount = dropCount - 1
    if drop.lootId ~= nil then
        lootDrops[tostring(drop.lootId)] = nil
        if type(Open77.loot) == "table" and type(Open77.loot.remove) == "function" then
            pcall(Open77.loot.remove, drop.lootId)
        end
    end
    sentDrops = {} -- метка пропала у всех
end

local function addDrop(inst, pos)
    if dropCount >= cfg.dropMax then
        -- Самый старый исчезает первым.
        local oldestId, oldest = nil, math.huge
        for id, drop in pairs(drops) do if drop.expires < oldest then oldestId, oldest = id, drop.expires end end
        if oldestId then removeDrop(oldestId) end
    end
    local id = nextDropId
    nextDropId = id + 1
    local angle = math.random() * math.pi * 2
    drops[id] = {
        id = id, inst = { id = inst.id, meta = inst.meta },
        x = pos.x + math.cos(angle) * 0.6, y = pos.y + math.sin(angle) * 0.6, z = pos.z,
        bucket = pos.bucket, expires = now() + cfg.dropLifetimeMin * 60,
    }
    dropCount = dropCount + 1
    spawnLoot(drops[id])
end

-- Игрок подобрал модель с земли штатным «Взять». Аргументы события в
-- документации не описаны, поэтому id дропа и игрока ищутся по значениям.
AddEventHandler("onLootPickup", function(...)
    local args = table.pack(...)
    local dropId, playerId = nil, nil
    local function consider(value)
        if value == nil then return end
        if type(value) == "table" then
            for _, key in ipairs({ "id", "lootId", "dropId", "drop" }) do consider(value[key]) end
            for _, key in ipairs({ "playerId", "player", "source" }) do
                local n = tonumber(value[key]); if n and inv[n] then playerId = playerId or n end
            end
            return
        end
        if not dropId and lootDrops[tostring(value)] then dropId = lootDrops[tostring(value)]; return end
        local n = tonumber(value)
        if n and inv[n] and not playerId then playerId = n end
    end
    for index = 1, args.n do consider(args[index]) end
    if not dropId then return end
    local drop = drops[dropId]
    if not drop then return end
    -- Штатный лут уже исчез с земли: дроп закрывается в любом случае.
    lootDrops[tostring(drop.lootId)] = nil
    drop.lootId = nil
    if not playerId then
        log("loot pickup without a known player, args: " .. args.n)
        spawnLoot(drop)
        return
    end
    CreateThread(function()
        local state = load(playerId)
        if not state then spawnLoot(drop); return end
        local inst = newInst(state, drop.inst.id, drop.inst.meta)
        local label = describe(inst.id, inst.meta).label
        if not putInBag(state, inst) then
            state.nextUid = state.nextUid - 1
            spawnLoot(drop) -- вернуть модель на землю
            notify(playerId, "error", "Инвентарь полон: " .. label .. " не помещается.")
            return
        end
        removeDrop(dropId)
        markDirty(playerId)
        pushState(playerId, false)
        notify(playerId, "success", "Подобрано: " .. label .. ".")
    end)
end)

-- ---------------------------------------------------------------------------
-- Сверка с игрой: оружие и одежда, выданные мимо инвентаря (меню /freeroam,
-- гардероб, админ-команды), попадают в слоты; то, что снято мимо инвентаря,
-- возвращается в рюкзак. Запускается при каждом открытии инвентаря.
-- ---------------------------------------------------------------------------
local function prettyRecord(record)
    return (record:gsub("^Items%.", ""):gsub("^Preset_", ""):gsub("_Default$", ""):gsub("_", " "))
end

local function weaponInst(state, record)
    if RppWeaponCatalog.index[record] then return newInst(state, record) end
    return newInst(state, "weapon", { record = record, label = prettyRecord(record) })
end

local function clothingInst(state, record, slot)
    for key, def in pairs(RppItemDefs) do
        if def.kind == "clothing" and def.record == record then return newInst(state, key) end
    end
    return newInst(state, "clothing", { record = record, slot = slot, label = prettyRecord(record) })
end

--- Снятый с персонажа предмет: в рюкзак, а если не влез — на землю под ноги.
local function stash(playerId, state, inst)
    if putInBag(state, inst) then return end
    local pos = playerPos(playerId)
    if pos then
        addDrop(inst, pos)
        notify(playerId, "warning", "Рюкзак полон: " .. describe(inst.id, inst.meta).label .. " лежит на земле.")
    end
end

local function syncWeapons(playerId, state)
    if type(Open77.weapons) ~= "table" or type(Open77.weapons.get) ~= "function" then return false end
    local ok, read = pcall(Open77.weapons.get, playerId)
    -- Клиент ещё ни разу не присылал список слотов: сверять не с чем.
    if not ok or type(read) ~= "table" or type(read.slots) ~= "table" or read.loadoutAgeMs == nil then return false end
    local game = {}
    for _, row in ipairs(read.slots) do
        local slot = tonumber(row.slot)
        if slot and type(row.record) == "string" and row.record ~= "" then game[slot] = row.record end
    end
    local changed = false
    for slot = 1, cfg.weaponSlots do
        if not recentlyTouched(playerId, "w" .. slot) then
            local ours, record = state.weapons[slot], game[slot]
            local oursRecord = ours and describe(ours.id, ours.meta).record
            if record and record ~= oursRecord then
                if ours then stash(playerId, state, ours) end
                state.weapons[slot] = weaponInst(state, record)
                changed = true
            elseif not record and ours then
                state.weapons[slot] = nil
                stash(playerId, state, ours)
                changed = true
            end
        end
    end
    return changed
end

local clothingRequests = {} -- [tostring(requestId)] = { playerId, at }

local function requestClothing(playerId)
    if type(Open77.clothing) ~= "table" or type(Open77.clothing.requestSnapshot) ~= "function" then return end
    local ok, requestId = pcall(Open77.clothing.requestSnapshot, playerId)
    if ok and requestId ~= nil then clothingRequests[tostring(requestId)] = { playerId = playerId, at = now() } end
end

local WIRE = {}
for _, row in ipairs(RppWearSlots) do WIRE[row.wire] = row.slot end

AddEventHandler("open77:clothing:completed", function(player, requestId, operation, accepted, reason, result)
    local entry = clothingRequests[tostring(requestId)]
    if not entry then return end
    clothingRequests[tostring(requestId)] = nil
    local playerId = entry.playerId
    local state = inv[playerId]
    if not state or accepted ~= true or type(result) ~= "table" then return end
    local game, seen = {}, {}
    for _, row in ipairs(result) do
        local slot = type(row) == "table" and WIRE[row.slot]
        if slot then
            seen[slot] = true
            if row.equipped == true and type(row.record) == "string" and row.record ~= "" then game[slot] = row.record end
        end
    end
    local changed = false
    for slot in pairs(seen) do
        if not recentlyTouched(playerId, "c" .. slot) then
            local ours, record = state.wear[slot], game[slot]
            local oursRecord = ours and describe(ours.id, ours.meta).record
            if record and record ~= oursRecord then
                if ours then stash(playerId, state, ours) end
                state.wear[slot] = clothingInst(state, record, slot)
                changed = true
            elseif not record and ours then
                state.wear[slot] = nil
                stash(playerId, state, ours)
                changed = true
            end
        end
    end
    if changed then
        markDirty(playerId)
        pushState(playerId, false)
    end
end)

action("open", function(playerId, state)
    requestClothing(playerId)
    return syncWeapons(playerId, state)
end)

action("drop", function(playerId, state, where, key)
    local pos = playerPos(playerId)
    if not pos then return false, "Не удалось определить, где вы стоите." end
    local inst
    if where == "bag" then
        local uid = int(key)
        inst = uid and state.items[uid]
        if not inst then return false end
        state.items[uid] = nil
    elseif where == "weapon" then
        local slot = int(key)
        inst = slot and state.weapons[slot]
        if not inst then return false end
        state.weapons[slot] = nil
        removeWeapon(playerId, slot)
    elseif where == "wear" and WEAR[key] then
        inst = state.wear[key]
        if not inst then return false end
        state.wear[key] = nil
        setClothing(playerId, key, false)
    else
        return false
    end
    addDrop(inst, pos)
    return true, "Выброшено: " .. describe(inst.id, inst.meta).label .. "."
end)

action("pickup", function(playerId, state)
    local pos = playerPos(playerId)
    if not pos then return false end
    local best, bestDist = nil, cfg.pickupDistance * cfg.pickupDistance
    for _, drop in pairs(drops) do
        if drop.bucket == pos.bucket then
            local dx, dy, dz = drop.x - pos.x, drop.y - pos.y, drop.z - pos.z
            local dist = dx * dx + dy * dy + dz * dz
            if dist <= bestDist then best, bestDist = drop, dist end
        end
    end
    if not best then return false, "Рядом нечего подобрать." end
    local inst = newInst(state, best.inst.id, best.inst.meta)
    local label = describe(inst.id, inst.meta).label
    if not putInBag(state, inst) then
        state.nextUid = state.nextUid - 1
        return false, "Инвентарь полон: " .. label .. " не помещается."
    end
    removeDrop(best.id)
    return true, "Подобрано: " .. label .. "."
end)

-- Раз в 2 с: каждому игроку — брошенные предметы рядом с ним; раз в 5 с — сохранение.
CreateThread(function()
    local tick = 0
    while true do
        Wait(2000)
        tick = tick + 1
        local t = now()
        for id, drop in pairs(drops) do
            if drop.expires < t then removeDrop(id) end
        end
        local limit = cfg.dropShowDistance * cfg.dropShowDistance
        for playerId in pairs(inv) do
            local pos = playerPos(playerId)
            if pos then
                local near = {}
                for _, drop in pairs(drops) do
                    -- Метка показывается всегда, даже если у дропа есть модель: модель
                    -- доходит до клиентов не на каждом сервере (см. dropModels в конфиге).
                    if drop.bucket == pos.bucket then
                        local dx, dy, dz = drop.x - pos.x, drop.y - pos.y, drop.z - pos.z
                        local dist = dx * dx + dy * dy + dz * dz
                        if dist <= limit then near[#near + 1] = { drop = drop, dist = dist } end
                    end
                end
                table.sort(near, function(a, b) return a.dist < b.dist end)
                local list, parts = {}, {}
                for index = 1, math.min(#near, cfg.dropShowMax) do
                    local drop = near[index].drop
                    local d = describe(drop.inst.id, drop.inst.meta)
                    list[#list + 1] = { id = drop.id, x = drop.x, y = drop.y, z = drop.z, label = d and d.label or "?" }
                    parts[#parts + 1] = tostring(drop.id)
                end
                table.sort(parts)
                local sig = table.concat(parts, ",")
                if sentDrops[playerId] ~= sig then
                    sentDrops[playerId] = sig
                    TriggerClientEvent("rpp_inventory:drops", playerId, list)
                end
            end
        end
        if tick % 3 == 0 then
            for playerId in pairs(dirty) do flush(playerId) end
        end
        for key, entry in pairs(pending) do
            if t - entry.at > 30 then pending[key] = nil end
        end
        for key, entry in pairs(clothingRequests) do
            if t - entry.at > 30 then clothingRequests[key] = nil end
        end
    end
end)

AddEventHandler("onPlayerDisconnected", function(playerIdStr)
    local playerId = tonumber(playerIdStr)
    if not playerId then return end
    local state = inv[playerId]
    if state and dirty[playerId] then
        CreateThread(function()
            dirty[playerId] = nil
            local ok, err = RppInvStore.save(state.guid, state.money, serialize(state))
            if not ok then log("save on disconnect failed: " .. tostring(err)) end
        end)
    end
    inv[playerId], actions[playerId], sentDrops[playerId], dirty[playerId], touched[playerId] = nil, nil, nil, nil, nil
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then return end
    for playerId in pairs(dirty) do
        local state = inv[playerId]
        if state then pcall(RppInvStore.save, state.guid, state.money, serialize(state)) end
    end
end)

-- ---------------------------------------------------------------------------
-- Обмен между игроками
--
-- 1. A предлагает обмен B (ALT-меню или /trade): offers[B][A] = срок.
-- 2. B принимает: у обоих открывается окно обмена.
-- 3. Каждый кладёт в своё предложение предметы из рюкзака и деньги.
--    Пока игрок нажал «Готов», менять своё предложение он не может. Любое
--    изменение предложения сбрасывает готовность обоих.
-- 4. Оба готовы -> через tradeDelaySec обмен. Перед обменом всё проверяется
--    заново (предметы на месте, деньги есть, место в рюкзаках, дистанция);
--    обмен атомарный: либо целиком, либо никак.
-- ---------------------------------------------------------------------------
local offers = {}       -- [targetId] = { [fromId] = expiresAt }
local nextTradeId = 1
local TRADE_MAX_ITEMS = 24

local function distance(a, b)
    local pa, pb = playerPos(a), playerPos(b)
    if not pa or not pb then return nil end
    if pa.bucket ~= pb.bucket then return math.huge end
    local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Как `viewer` видит `target`: имя знакомого или «Житель #N» (rpp_identity).
local function nameFor(viewer, target)
    local ok, label = pcall(function()
        local promise = Open77.exports.call("rpp_identity", "labelFor", viewer, target)
        return promise and promise:await() or nil
    end)
    if ok and type(label) == "string" and label ~= "" then return label end
    return "Игрок #" .. tostring(target)
end

local function partnerOf(trade, playerId) return trade.a == playerId and trade.b or trade.a end

local function pushOffers(targetId)
    local list = {}
    local t = now()
    for fromId, expires in pairs(offers[targetId] or {}) do
        if expires > t then list[#list + 1] = fromId end
    end
    TriggerClientEvent("rpp_inventory:tradeOffers", targetId, list)
end

local function offerView(playerId, trade)
    local state, offer = inv[playerId], trade.offer[playerId]
    local items = {}
    for uid in pairs(offer.items) do
        local inst = state and state.items[uid]
        if inst then items[#items + 1] = view(inst) end
    end
    table.sort(items, function(l, r) return l.uid < r.uid end)
    return { items = items, money = offer.money, ready = trade.ready[playerId] == true }
end

local function pushTrade(trade)
    local left = trade.executeAt and math.max(0, trade.executeAt - now()) or nil
    for _, playerId in ipairs({ trade.a, trade.b }) do
        local partner = partnerOf(trade, playerId)
        TriggerClientEvent("rpp_inventory:trade", playerId, {
            id = trade.id,
            partner = trade.names[playerId],
            mine = offerView(playerId, trade),
            theirs = offerView(partner, trade),
            countdown = left,
            delay = cfg.tradeDelaySec,
        })
        pushState(playerId, false)
    end
end

local function closeTrade(trade, reason, kind)
    if not trades[trade.id] then return end
    trades[trade.id] = nil
    for _, playerId in ipairs({ trade.a, trade.b }) do
        if playerTrade[playerId] == trade.id then playerTrade[playerId] = nil end
        TriggerClientEvent("rpp_inventory:tradeClosed", playerId, reason)
        if reason then notify(playerId, kind or "warning", reason) end
        pushState(playerId, false)
    end
end

--- Сбрасывает готовность обоих и отменяет отсчёт (после любого изменения).
local function unready(trade)
    trade.ready[trade.a], trade.ready[trade.b] = false, false
    trade.executeAt = nil
    trade.version = trade.version + 1
end

-- Снимок рюкзака для отката.
local function snapshot(state)
    local copy = { items = {}, pos = {}, nextUid = state.nextUid, money = state.money }
    for uid, inst in pairs(state.items) do copy.items[uid] = inst; copy.pos[uid] = { inst.x, inst.y } end
    return copy
end

local function restore(state, copy)
    state.items = {}
    for uid, inst in pairs(copy.items) do
        inst.x, inst.y = copy.pos[uid][1], copy.pos[uid][2]
        state.items[uid] = inst
    end
    state.nextUid, state.money = copy.nextUid, copy.money
end

--- Проверяет, что предложение игрока всё ещё выполнимо. nil или текст ошибки.
local function offerProblem(playerId, trade)
    local state, offer = inv[playerId], trade.offer[playerId]
    if not state then return "Игрок вышел." end
    for uid in pairs(offer.items) do
        if not state.items[uid] then return "Предмет из предложения пропал из рюкзака." end
    end
    if offer.money > state.money then return "Не хватает денег на предложенную сумму." end
    return nil
end

local function executeTrade(trade)
    local a, b = trade.a, trade.b
    local sa, sb = inv[a], inv[b]
    local problem = offerProblem(a, trade) or offerProblem(b, trade)
    if problem then return closeTrade(trade, "Обмен отменён: " .. problem, "error") end
    local d = distance(a, b)
    if d and d > cfg.tradeKeepDistance then
        return closeTrade(trade, "Обмен отменён: вы слишком далеко друг от друга.", "error")
    end

    -- Что уходит от каждого.
    local outA, outB = {}, {}
    for uid in pairs(trade.offer[a].items) do outA[#outA + 1] = sa.items[uid] end
    for uid in pairs(trade.offer[b].items) do outB[#outB + 1] = sb.items[uid] end
    local function bySize(l, r)
        local lw, lh = sizeOf(l)
        local rw, rh = sizeOf(r)
        return lw * lh > rw * rh
    end
    table.sort(outA, bySize)
    table.sort(outB, bySize)

    local copyA, copyB = snapshot(sa), snapshot(sb)
    for _, inst in ipairs(outA) do sa.items[inst.uid] = nil end
    for _, inst in ipairs(outB) do sb.items[inst.uid] = nil end

    local function receive(state, incoming)
        for _, inst in ipairs(incoming) do
            if not putInBag(state, newInst(state, inst.id, inst.meta)) then return false end
        end
        return true
    end
    if not receive(sa, outB) then
        restore(sa, copyA); restore(sb, copyB)
        return closeTrade(trade, "Обмен отменён: не хватает места в рюкзаке (" .. trade.names[b] .. ").", "error")
    end
    if not receive(sb, outA) then
        restore(sa, copyA); restore(sb, copyB)
        return closeTrade(trade, "Обмен отменён: не хватает места в рюкзаке (" .. trade.names[a] .. ").", "error")
    end
    local ma, mb = trade.offer[a].money, trade.offer[b].money
    sa.money = sa.money - ma + mb
    sb.money = sb.money - mb + ma

    markDirty(a); markDirty(b)
    log(("trade #%d done: %d gave %d item(s) + %d eddies, %d gave %d item(s) + %d eddies")
        :format(trade.id, a, #outA, ma, b, #outB, mb))
    closeTrade(trade, nil)
    notify(a, "success", "Обмен завершён.")
    notify(b, "success", "Обмен завершён.")
end

local function scheduleExecute(trade)
    trade.executeAt = now() + cfg.tradeDelaySec
    local version = trade.version
    pushTrade(trade)
    CreateThread(function()
        Wait(math.floor(cfg.tradeDelaySec * 1000))
        if trades[trade.id] ~= trade or trade.version ~= version then return end
        if not (trade.ready[trade.a] and trade.ready[trade.b]) then return end
        executeTrade(trade)
    end)
end

local function startTrade(a, b)
    local trade = {
        id = nextTradeId, a = a, b = b, version = 0,
        offer = { [a] = { items = {}, money = 0 }, [b] = { items = {}, money = 0 } },
        ready = { [a] = false, [b] = false },
        names = { [a] = nameFor(a, b), [b] = nameFor(b, a) }, -- имя партнёра глазами игрока
    }
    nextTradeId = nextTradeId + 1
    trades[trade.id] = trade
    playerTrade[a], playerTrade[b] = trade.id, trade.id
    pushTrade(trade)
end

--- Предложение обмена from -> target. true или false, сообщение.
local function offerTrade(from, target)
    if from == target then return false, "Нельзя обменяться с самим собой." end
    if not inv[from] or not load(target) then return false, "Игрок недоступен." end
    if playerTrade[from] then return false, "Вы уже в обмене." end
    if playerTrade[target] then return false, "Этот игрок уже с кем-то меняется." end
    local d = distance(from, target)
    if d and d > cfg.tradeDistance then return false, "Подойдите ближе, чтобы предложить обмен." end
    -- Встречное предложение — сразу начинаем.
    if offers[from] and offers[from][target] and offers[from][target] > now() then
        offers[from][target] = nil
        pushOffers(from)
        startTrade(target, from)
        return true
    end
    offers[target] = offers[target] or {}
    offers[target][from] = now() + cfg.tradeOfferSec
    pushOffers(target)
    notify(target, "info", nameFor(target, from) .. " предлагает обмен. ALT на игроке -> «Принять обмен» или /trade accept.")
    return true, "Предложение обмена отправлено: " .. nameFor(from, target) .. "."
end

local function acceptTrade(target, from)
    local list = offers[target] or {}
    if not from then
        -- последнее предложение
        local best = 0
        for id, expires in pairs(list) do if expires > now() and expires > best then from, best = id, expires end end
    end
    if not from or not list[from] or list[from] <= now() then return false, "Нет предложений обмена." end
    list[from] = nil
    pushOffers(target)
    if playerTrade[from] or playerTrade[target] then return false, "Кто-то из вас уже в обмене." end
    local d = distance(from, target)
    if d and d > cfg.tradeDistance then return false, "Подойдите ближе, чтобы начать обмен." end
    startTrade(from, target)
    return true
end

--- Обработчик действия в обмене: игрок, его обмен; handler(trade) -> ok, сообщение.
local function tradeEvent(name, handler)
    RegisterNetEvent("rpp_inventory:" .. name, function(...)
        local playerId = tonumber(source)
        if not playerId or not allowed(playerId) then return end
        local args = table.pack(...)
        CreateThread(function()
            if not load(playerId) then return end
            local ok, result, message = pcall(handler, playerId, table.unpack(args, 1, args.n))
            if not ok then log(name .. " failed: " .. tostring(result)); message = "Внутренняя ошибка обмена." end
            if message then notify(playerId, (ok and result) and "success" or "error", message) end
        end)
    end)
end

tradeEvent("tradeOffer", function(playerId, target)
    target = int(target)
    if not target then return false end
    return offerTrade(playerId, target)
end)

tradeEvent("tradeAccept", function(playerId, from)
    return acceptTrade(playerId, int(from))
end)

tradeEvent("tradeDecline", function(playerId, from)
    from = int(from)
    local list = offers[playerId] or {}
    if from then list[from] = nil else offers[playerId] = {} end
    pushOffers(playerId)
    if from and inv[from] then notify(from, "warning", nameFor(from, playerId) .. " отказался от обмена.") end
    return true
end)

--- Своё предложение можно менять только пока не нажата «Готов».
local function editable(playerId)
    local trade = playerTrade[playerId] and trades[playerTrade[playerId]]
    if not trade then return nil, "Вы не в обмене." end
    if trade.ready[playerId] then return nil, "Снимите готовность, чтобы менять предложение." end
    return trade
end

tradeEvent("tradeAdd", function(playerId, uid)
    uid = int(uid)
    local trade, why = editable(playerId)
    if not trade then return false, why end
    local state, offer = inv[playerId], trade.offer[playerId]
    if not uid or not state.items[uid] then return false, "Этого предмета нет в рюкзаке." end
    local count = 0
    for _ in pairs(offer.items) do count = count + 1 end
    if count >= TRADE_MAX_ITEMS then return false, "В обмен можно положить не больше " .. TRADE_MAX_ITEMS .. " предметов." end
    offer.items[uid] = true
    unready(trade)
    pushTrade(trade)
    return true
end)

tradeEvent("tradeRemove", function(playerId, uid)
    uid = int(uid)
    local trade, why = editable(playerId)
    if not trade then return false, why end
    if uid and trade.offer[playerId].items[uid] then
        trade.offer[playerId].items[uid] = nil
        unready(trade)
        pushTrade(trade)
    end
    return true
end)

tradeEvent("tradeMoney", function(playerId, amount)
    amount = int(amount)
    local trade, why = editable(playerId)
    if not trade then return false, why end
    if not amount or amount < 0 then return false, "Неверная сумма." end
    if amount > inv[playerId].money then return false, "У вас нет столько денег." end
    trade.offer[playerId].money = amount
    unready(trade)
    pushTrade(trade)
    return true
end)

tradeEvent("tradeReady", function(playerId, value)
    local trade = playerTrade[playerId] and trades[playerTrade[playerId]]
    if not trade then return false end
    if value == true then
        local problem = offerProblem(playerId, trade)
        if problem then return false, problem end
        trade.ready[playerId] = true
        trade.version = trade.version + 1
        if trade.ready[trade.a] and trade.ready[trade.b] then scheduleExecute(trade) else pushTrade(trade) end
    else
        -- Отжать готовность можно и во время отсчёта: обмен тогда не состоится.
        trade.ready[playerId] = false
        trade.executeAt = nil
        trade.version = trade.version + 1
        pushTrade(trade)
    end
    return true
end)

tradeEvent("tradeCancel", function(playerId)
    local trade = playerTrade[playerId] and trades[playerTrade[playerId]]
    if trade then closeTrade(trade, "Обмен отменён.", "warning") end
    return true
end)

-- Разошлись далеко — обмен отменяется; просроченные предложения убираются.
CreateThread(function()
    while true do
        Wait(1000)
        for _, trade in pairs(trades) do
            local d = distance(trade.a, trade.b)
            if d and d > cfg.tradeKeepDistance then
                closeTrade(trade, "Обмен отменён: вы отошли слишком далеко.", "warning")
            end
        end
        local t = now()
        for targetId, list in pairs(offers) do
            local changedList = false
            for fromId, expires in pairs(list) do
                if expires <= t then list[fromId] = nil; changedList = true end
            end
            if changedList and inv[targetId] then pushOffers(targetId) end
        end
    end
end)

AddEventHandler("onPlayerDisconnected", function(playerIdStr)
    local playerId = tonumber(playerIdStr)
    if not playerId then return end
    local trade = playerTrade[playerId] and trades[playerTrade[playerId]]
    if trade then closeTrade(trade, "Обмен отменён: партнёр вышел.", "warning") end
    offers[playerId] = nil
    for _, list in pairs(offers) do list[playerId] = nil end
end)

-- /trade accept | decline | <ID игрока>
RegisterCommand("trade", function(player, args, raw)
    player = tonumber(player)
    if not player or player <= 0 then return reply(player, raw, false, "trade — команда игрока") end
    CreateThread(function()
        if not load(player) then return end
        local sub = args[1] and args[1]:lower() or ""
        local ok, message
        if sub == "accept" or sub == "принять" then
            ok, message = acceptTrade(player, nil)
        elseif sub == "decline" or sub == "отказ" then
            offers[player] = {}
            pushOffers(player)
            ok, message = true, "Предложения обмена отклонены."
        elseif tonumber(sub) then
            ok, message = offerTrade(player, tonumber(sub))
        else
            ok, message = false, "использование: /trade accept | /trade decline | /trade <ID игрока>"
        end
        if message then reply(player, raw, ok == true, message) end
    end)
end, false)

-- ---------------------------------------------------------------------------
-- API для других ресурсов
-- ---------------------------------------------------------------------------
-- Все функции, кроме describe, ждут базу: вызывать внутри CreateThread.
local function changed(playerId)
    -- раскладка не трогается: новые предметы сами встают сверху слева
    markDirty(playerId); pushState(playerId, false)
end

exports("getMoney", function(playerId)
    local state = load(tonumber(playerId))
    return state and state.money or nil
end)

exports("addMoney", function(playerId, amount)
    playerId, amount = tonumber(playerId), int(amount)
    local state = load(playerId)
    if not state or not amount or amount <= 0 then return false, "invalid" end
    state.money = state.money + amount
    changed(playerId)
    return true, state.money
end)

exports("removeMoney", function(playerId, amount)
    playerId, amount = tonumber(playerId), int(amount)
    local state = load(playerId)
    if not state or not amount or amount <= 0 then return false, "invalid" end
    if state.money < amount then return false, "not_enough_money" end
    state.money = state.money - amount
    changed(playerId)
    return true, state.money
end)

--- Кладёт предмет в рюкзак. false, "inventory_full", если не влез.
exports("addItem", function(playerId, item)
    playerId = tonumber(playerId)
    local state = load(playerId)
    local id = resolveItemId(item)
    if not state then return false, "not_loaded" end
    if not id then return false, "unknown_item" end
    local inst = newInst(state, id)
    if not putInBag(state, inst) then state.nextUid = state.nextUid - 1; return false, "inventory_full" end
    changed(playerId)
    return true, inst.uid
end)

exports("canCarry", function(playerId, item)
    local state = load(tonumber(playerId))
    local id = resolveItemId(item)
    local d = id and describe(id)
    if not state or not d then return false end
    return findSpot(state, d.w, d.h) ~= nil
end)

--- Убирает из рюкзака первый предмет с этим id. true, если нашёлся.
exports("removeItem", function(playerId, item)
    playerId = tonumber(playerId)
    local state = load(playerId)
    local id = resolveItemId(item)
    if not state or not id then return false end
    for uid, inst in pairs(state.items) do
        if inst.id == id then state.items[uid] = nil; changed(playerId); return true end
    end
    return false
end)

--- Предметы в рюкзаке игрока (по виду, например "implant"): { {id, label, uid}, ... }.
exports("listItems", function(playerId, kind)
    local state = load(tonumber(playerId))
    if not state then return {} end
    local list = {}
    for uid, inst in pairs(state.items) do
        local d = describe(inst.id, inst.meta)
        if d and (kind == nil or d.kind == kind) then
            list[#list + 1] = { id = inst.id, label = d.label, uid = uid }
        end
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    return list
end)

exports("describe", function(item)
    local id = resolveItemId(item)
    return id and describe(id) or nil
end)

-- ---------------------------------------------------------------------------
-- Команды
-- ---------------------------------------------------------------------------
-- Ограниченная: нужен `command.rpp.item.give` в acl.jsonc.
RegisterCommand("rpp.item.give", function(player, args, raw)
    CreateThread(function()
        local target = args[1] == "me" and tonumber(player) or tonumber(args[1])
        local id = resolveItemId(args[2])
        if not target or not id then
            return reply(tonumber(player), raw, false,
                "usage: rpp.item.give <playerId|me> <itemId|Items.Preset_*|название>  (список: rpp.item.list)")
        end
        local state = load(target)
        if not state then return reply(tonumber(player), raw, false, "player " .. tostring(target) .. " не загружен") end
        local inst = newInst(state, id)
        if not putInBag(state, inst) then
            state.nextUid = state.nextUid - 1
            return reply(tonumber(player), raw, false, "инвентарь полон")
        end
        changed(target)
        notify(target, "success", "Получено: " .. describe(id).label .. ".")
        reply(tonumber(player), raw, true, ("выдано %s игроку %d"):format(id, target))
    end)
end, true)

-- Ограниченная: нужен `command.rpp.money.give` в acl.jsonc. Отрицательная сумма забирает.
RegisterCommand("rpp.money.give", function(player, args, raw)
    CreateThread(function()
        local target = args[1] == "me" and tonumber(player) or tonumber(args[1])
        local amount = int(args[2])
        if not target or not amount or amount == 0 then
            return reply(tonumber(player), raw, false, "использование: rpp.money.give <ID игрока|me> <сумма>")
        end
        local state = load(target)
        if not state then return reply(tonumber(player), raw, false, "игрок не загружен") end
        state.money = math.max(0, state.money + amount)
        changed(target)
        reply(tonumber(player), raw, true, ("у игрока %d теперь %d €$"):format(target, state.money))
    end)
end, true)

RegisterCommand("rpp.item.list", function(player, args, raw)
    local filter = args[1] and args[1]:lower() or nil
    local lines = {}
    local keys = {}
    for key in pairs(RppItemDefs) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local d = describe(key)
        if not filter or key:find(filter, 1, true) or d.label:lower():find(filter, 1, true) then
            lines[#lines + 1] = ("%s — %s (%dx%d)"):format(key, d.label, d.w, d.h)
        end
    end
    if filter then
        for position, record in ipairs(RppWeaponCatalog.records) do
            if record:lower():find(filter, 1, true) or RppWeaponCatalog.names[position]:lower():find(filter, 1, true) then
                local d = describe(record)
                lines[#lines + 1] = ("%s — %s, %s (%dx%d)"):format(record, d.label, d.sub, d.w, d.h)
            end
            if #lines > 40 then break end
        end
    else
        lines[#lines + 1] = "оружие: rpp.item.list <часть названия>, например rpp.item.list katana"
    end
    reply(tonumber(player), raw, true, table.concat(lines, "\n"))
end, false)

-- ---------------------------------------------------------------------------
-- Старт
-- ---------------------------------------------------------------------------
CreateThread(function()
    RppInvStore.init()
    local ok, players = pcall(Open77.players.all)
    for _, playerId in ipairs(ok and type(players) == "table" and players or {}) do
        playerId = tonumber(type(playerId) == "table" and playerId.id or playerId)
        if playerId then load(playerId) end
    end
end)
