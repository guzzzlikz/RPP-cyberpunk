-- rpp_vehicles, клиентская часть: окно гаража и пункты ALT-меню на машине и на игроке.
-- Права присылает сервер (rpp_vehicles:rights); он же заново проверяет всё
-- при каждом действии. Здесь — только показать нужные пункты.
local cfg = RppVehiclesConfig
local RESOURCE = GetCurrentResourceName()

local rights = {}      -- [vehicleId] = { carId, label, locked, owner }
local ownsSpawned = false
local keyHolders = {}  -- [playerId] = true: держит ключи от моей машины

local function log(text) print("[" .. RESOURCE .. "] " .. text) end

RegisterNetEvent("rpp_vehicles:rights", function(list, holders)
    rights, ownsSpawned, keyHolders = {}, false, {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        local id = tonumber(entry.vehicleId)
        if id then
            rights[id] = entry
            if entry.owner then ownsSpawned = true end
        end
    end
    for _, id in ipairs(type(holders) == "table" and holders or {}) do
        if tonumber(id) then keyHolders[tonumber(id)] = true end
    end
end)

-- ---------------------------------------------------------------------------
-- Окно гаража (/garage)
-- ---------------------------------------------------------------------------
local page, ready, open = nil, false, false
local queue = {}

local function send(event, payload)
    if not page then return end
    if not ready then queue[#queue + 1] = { event, payload }; return end
    page:send("garage:" .. event, payload or {})
end

local function focus(enabled) if page then pcall(page.setFocus, page, enabled, enabled) end end

local function closeGarage()
    if not open then return end
    open = false
    send("hide")
    focus(false)
end

local function ensurePage()
    if page then return true end
    local reason
    page, reason = WebUI.create({ entry = "web/index.html", layer = "menu", width = 1920, height = 1080,
        fps = 60, zIndex = 743, transparent = true, visible = true })
    if not page then log("WebUI failed: " .. tostring(reason)); return false end
    page:on("garage:ready", function()
        ready = true
        for _, item in ipairs(queue) do page:send("garage:" .. item[1], item[2] or {}) end
        queue = {}
    end)
    page:on("garage:close", function() open = false; focus(false) end)
    page:on("garage:spawn", function(p)
        if type(p) == "table" and tonumber(p.id) then TriggerServerEvent("rpp_vehicles:spawn", tonumber(p.id)) end
    end)
    page:on("garage:buy", function(p)
        if type(p) == "table" and tonumber(p.index) then TriggerServerEvent("rpp_vehicles:buy", tonumber(p.index)) end
    end)
    page:on("garage:rent", function(p)
        if type(p) == "table" and tonumber(p.index) and tonumber(p.minutes) then
            TriggerServerEvent("rpp_vehicles:rent", tonumber(p.index), tonumber(p.minutes))
        end
    end)
    return true
end

RegisterNetEvent("rpp_vehicles:garage", function(view, openWindow)
    if type(view) ~= "table" then return end
    if not openWindow and not open then return end
    if not ensurePage() then return end
    send("view", view)
    if openWindow and not open then
        open = true
        send("show")
        focus(true)
    end
end)

RegisterNetEvent("rpp_vehicles:garageClose", closeGarage)

-- ---------------------------------------------------------------------------
-- Автосалон и прокат: метка в мире (E — открыть окно) и на карте
-- ---------------------------------------------------------------------------
local points = {}   -- [mode] = handle метки worldui
local blipsMade = false

local function worldui(name, arg)
    local pending, reason = Open77.exports.call("open77_worldui", name, arg)
    if not pending then return nil, reason end
    return pending:await()
end

local function createPoint(mode, section)
    if points[mode] or not section.enabled then return end
    points[mode] = "pending"
    local result = worldui("create", {
        id = "rpp_" .. mode,
        position = section.position,
        style = "interaction",
        radius = 0.8,
        maxDistance = 25,
        label = section.label,
        description = mode == "dealer" and "Купить машину" or "Взять машину на время",
        key = "E",
        promptDistance = cfg.promptDistance,
        event = "rpp_vehicles:" .. mode .. "Prompt",
    })
    if type(result) == "table" and result.ok then points[mode] = result.handle
    else
        points[mode] = nil
        log(mode .. " marker failed: " .. tostring(type(result) == "table" and result.error or result))
    end
end

local function createBlips()
    if blipsMade or not cfg.blips or type(Open77.blips) ~= "table" then return end
    local made = 0
    for _, row in ipairs({ { cfg.dealership, "fast_travel", "Купить машину" }, { cfg.rental, "objective", "Взять машину на время" } }) do
        if row[1].enabled then
            local ok, id = pcall(Open77.blips.create, { position = row[1].position, sprite = row[2],
                title = row[1].label, description = row[3] })
            if ok and id ~= nil then made = made + 1 end
        end
    end
    if made > 0 then blipsMade = true end
end

local function setupPoints()
    createPoint("dealer", cfg.dealership)
    createPoint("rental", cfg.rental)
    createBlips()
end

AddEventHandler("rpp_vehicles:dealerPrompt", function() TriggerServerEvent("rpp_vehicles:shopOpen", "dealer") end)
AddEventHandler("rpp_vehicles:rentalPrompt", function() TriggerServerEvent("rpp_vehicles:shopOpen", "rental") end)
AddEventHandler("open77:worldReady", function()
    points, blipsMade = {}, false -- новый мир: метки ставятся заново
    CreateThread(setupPoints)
end)

-- ---------------------------------------------------------------------------
-- ALT-меню
-- ---------------------------------------------------------------------------
local function fromMenu() return GetInvokingResource() == "open77_contextmenu" end

local function vehicleOf(context)
    local id = context and context.target and tonumber(context.target.vehicleId)
    return id, id and rights[id]
end

local function playerOf(context)
    local target = context and context.target
    local id = target and tonumber(target.playerId)
    if not id or target.isLocalPlayer == true then return nil end
    return id
end

--- В какой машине сидит игрок (ID машины) или nil.
local function vehicleOfPlayer(playerId)
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat, playerId)
    return ok and type(seat) == "table" and tonumber(seat.vehicleId) or nil
end

-- На машине -----------------------------------------------------------------
exports("canLock", function(ctx)
    if not fromMenu() then return false end
    local _, r = vehicleOf(ctx)
    return r ~= nil and not r.locked
end)
exports("canUnlock", function(ctx)
    if not fromMenu() then return false end
    local _, r = vehicleOf(ctx)
    return r ~= nil and r.locked
end)
exports("selectLock", function(ctx)
    if not fromMenu() then return false end
    local id = vehicleOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:lock", id)
    return true
end)
exports("canTrunk", function(ctx)
    if not fromMenu() then return false end
    local _, r = vehicleOf(ctx)
    return r ~= nil
end)
exports("selectTrunk", function(ctx)
    if not fromMenu() then return false end
    local id = vehicleOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:trunk", id)
    return true
end)
exports("canPark", function(ctx)
    if not fromMenu() then return false end
    local _, r = vehicleOf(ctx)
    return r ~= nil and r.owner == true and not r.rental
end)
exports("canReturn", function(ctx)
    if not fromMenu() then return false end
    local _, r = vehicleOf(ctx)
    return r ~= nil and r.owner == true and r.rental == true
end)
exports("selectPark", function(ctx)
    if not fromMenu() then return false end
    local id = vehicleOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:park", id)
    return true
end)
exports("selectEject", function(ctx)
    if not fromMenu() then return false end
    local id = vehicleOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:eject", id)
    return true
end)

-- На игроке -----------------------------------------------------------------
exports("canEjectPlayer", function(ctx)
    if not fromMenu() then return false end
    local id = playerOf(ctx)
    local vehicleId = id and vehicleOfPlayer(id)
    return vehicleId ~= nil and rights[vehicleId] ~= nil
end)
exports("selectEjectPlayer", function(ctx)
    if not fromMenu() then return false end
    local id = playerOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:ejectPlayer", id)
    return true
end)
exports("canGiveKeys", function(ctx)
    if not fromMenu() then return false end
    local id = playerOf(ctx)
    return id ~= nil and ownsSpawned and not keyHolders[id]
end)
exports("selectGiveKeys", function(ctx)
    if not fromMenu() then return false end
    local id = playerOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:giveKeys", id)
    return true
end)
exports("canTakeKeys", function(ctx)
    if not fromMenu() then return false end
    local id = playerOf(ctx)
    return id ~= nil and keyHolders[id] == true
end)
exports("selectTakeKeys", function(ctx)
    if not fromMenu() then return false end
    local id = playerOf(ctx)
    if not id then return false end
    TriggerServerEvent("rpp_vehicles:takeKeys", id)
    return true
end)

local function register(method, entry)
    local pending, reason = Open77.exports.call("open77_contextmenu", method, entry)
    if pending then
        local token
        token, reason = pending:await()
        if token then return end
    end
    log("context menu " .. entry.id .. " failed: " .. tostring(reason))
end

local function registerContext()
    local d = cfg.interactDistance
    -- Не больше пяти регистраций за раз (лимит инструкций клиента): по одной.
    register("registerVehicles", { id = "rpp_veh_lock", label = "Закрыть машину", icon = "lock",
        description = "Закрыть на замок.", group = "Машина", distance = d,
        canInteract = "canLock", onSelect = "selectLock" })
    register("registerVehicles", { id = "rpp_veh_unlock", label = "Открыть машину", icon = "lock",
        description = "Снять с замка.", group = "Машина", distance = d,
        canInteract = "canUnlock", onSelect = "selectLock" })
    register("registerVehicles", { id = "rpp_veh_trunk", label = "Багажник", icon = "vehicle",
        description = "Открыть багажник: вещи из него видят все, у кого есть ключи.", group = "Машина",
        distance = cfg.trunkDistance, canInteract = "canTrunk", onSelect = "selectTrunk" })
    register("registerVehicles", { id = "rpp_veh_eject", label = "Высадить пассажиров", icon = "person",
        description = "Высадить всех, кто сидит в машине (кроме вас).", group = "Машина", distance = d,
        canInteract = "canTrunk", onSelect = "selectEject" })
    register("registerVehicles", { id = "rpp_veh_park", label = "Припарковать", icon = "location",
        description = "Убрать машину в гараж. Багажник сохранится, вызвать снова — /garage.", group = "Машина",
        distance = cfg.parkDistance, canInteract = "canPark", onSelect = "selectPark" })
    register("registerVehicles", { id = "rpp_veh_return", label = "Вернуть в прокат", icon = "location",
        description = "Закончить аренду сейчас. Вещи из багажника пропадут.", group = "Машина",
        distance = cfg.parkDistance, canInteract = "canReturn", onSelect = "selectPark" })
    register("registerPlayers", { id = "rpp_veh_eject_player", label = "Высадить из машины", icon = "person",
        description = "Высадить этого человека из вашей машины.", group = "Машина", distance = d,
        canInteract = "canEjectPlayer", onSelect = "selectEjectPlayer" })
    register("registerPlayers", { id = "rpp_veh_givekeys", label = "Дать ключи от машины", icon = "interact",
        description = "Он сможет открывать машину, пользоваться багажником и высаживать пассажиров.",
        group = "Машина", distance = d, canInteract = "canGiveKeys", onSelect = "selectGiveKeys" })
    register("registerPlayers", { id = "rpp_veh_takekeys", label = "Забрать ключи от машины", icon = "interact",
        description = "Забрать у него ключи от ваших машин.", group = "Машина", distance = d,
        canInteract = "canTakeKeys", onSelect = "selectTakeKeys" })
end

AddEventHandler("onClientResourceStart", function(name)
    if name == RESOURCE then
        TriggerServerEvent("rpp_vehicles:hello")
        CreateThread(registerContext)
        CreateThread(setupPoints)
    elseif name == "open77_contextmenu" then
        CreateThread(registerContext)
    elseif name == "open77_worldui" then
        points = {}
        CreateThread(setupPoints)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    focus(false)
    page, ready, open = nil, false, false
end)
