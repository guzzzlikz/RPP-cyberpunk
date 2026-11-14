-- rpp_ripperdoc, клиент: пункты ALT-меню и панель риппердока (WebUI).
local RESOURCE = GetCurrentResourceName()
local cfg = RppRipperdocConfig

local amDoctor = false
local doctors = {}        -- [playerId] = true
local page, ready, open = nil, false, false
local queue = {}
local patient = nil

local function log(text) print("[" .. RESOURCE .. "] " .. text) end

local function send(event, payload)
    if not page then return end
    if not ready then queue[#queue + 1] = { event, payload }; return end
    page:send("rd:" .. event, payload or {})
end

local function focus(enabled) if page then pcall(page.setFocus, page, enabled, enabled) end end

local function close(notifyServer)
    if not open then return end
    open = false
    send("hide")
    focus(false)
    if notifyServer then TriggerServerEvent("rpp_ripperdoc:close") end
end

local function ensurePage()
    if page then return true end
    local reason
    page, reason = WebUI.create({ entry = "web/index.html", layer = "menu", width = 1920, height = 1080,
        fps = 60, zIndex = 742, transparent = true, visible = true })
    if not page then log("WebUI failed: " .. tostring(reason)); return false end
    page:on("rd:ready", function()
        ready = true
        for _, item in ipairs(queue) do page:send("rd:" .. item[1], item[2] or {}) end
        queue = {}
    end)
    page:on("rd:close", function() close(true) end)
    page:on("rd:refresh", function() TriggerServerEvent("rpp_ripperdoc:refresh") end)
    page:on("rd:install", function(p)
        if type(p) ~= "table" or not patient then return end
        TriggerServerEvent("rpp_ripperdoc:install", patient, p.source == "doctor" and "doctor" or "patient", tostring(p.item or ""))
    end)
    page:on("rd:remove", function(p)
        if type(p) ~= "table" or not patient then return end
        TriggerServerEvent("rpp_ripperdoc:remove", patient, tostring(p.slot or ""))
    end)
    return true
end

RegisterNetEvent("rpp_ripperdoc:role", function(value) amDoctor = value == true end)
RegisterNetEvent("rpp_ripperdoc:doctors", function(list)
    doctors = {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if tonumber(id) then doctors[tonumber(id)] = true end
    end
end)

RegisterNetEvent("rpp_ripperdoc:open", function()
    if not ensurePage() then return end
    open = true
    send("show")
    focus(true)
end)

RegisterNetEvent("rpp_ripperdoc:view", function(view)
    if type(view) ~= "table" then return end
    patient = tonumber(view.patient)
    send("view", view)
end)

RegisterNetEvent("rpp_ripperdoc:close", function() close(false) end)

-- ---------------------------------------------------------------------------
-- ALT-меню
-- ---------------------------------------------------------------------------
local function targetId(context)
    local target = context and context.target
    local id = target and tonumber(target.playerId)
    if not id or target.isLocalPlayer == true then return nil end
    return id
end

exports("canOperate", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    return amDoctor and targetId(context) ~= nil
end)
exports("selectOperate", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    if not id then return false end
    TriggerServerEvent("rpp_ripperdoc:open", id)
    return true
end)
exports("canConsent", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    return id ~= nil and doctors[id] == true
end)
exports("selectConsent", function(context)
    if GetInvokingResource() ~= "open77_contextmenu" then return false end
    local id = targetId(context)
    if not id then return false end
    TriggerServerEvent("rpp_ripperdoc:consent", id)
    return true
end)

local function registerContext()
    local entries = {
        { id = "rpp_ripperdoc_operate", label = "Импланты (риппердок)", icon = "tool",
          description = "Поставить или снять импланты этому игроку.",
          canInteract = "canOperate", onSelect = "selectOperate" },
        { id = "rpp_ripperdoc_consent", label = "Разрешить операцию", icon = "person",
          description = "Риппердок сможет ставить и снимать ваши импланты (" .. math.floor(cfg.consentSec / 60) .. " мин).",
          canInteract = "canConsent", onSelect = "selectConsent" },
    }
    for _, entry in ipairs(entries) do
        entry.distance = cfg.distance
        entry.group = "Риппердок"
        local pending, reason = Open77.exports.call("open77_contextmenu", "registerPlayers", entry)
        if pending then
            local token
            token, reason = pending:await()
            if token then reason = nil end
        end
        if reason then log("context menu " .. entry.id .. " failed: " .. tostring(reason)) end
    end
end

AddEventHandler("onClientResourceStart", function(name)
    if name == RESOURCE then
        TriggerServerEvent("rpp_ripperdoc:hello")
        CreateThread(registerContext)
    elseif name == "open77_contextmenu" then
        CreateThread(registerContext)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    focus(false)
    page, ready, open = nil, false, false
end)
