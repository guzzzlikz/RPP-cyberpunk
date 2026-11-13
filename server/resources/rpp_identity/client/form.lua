-- Окно паспорта (WebUI): ввод имени/фамилии и подтверждение с номером жителя.
-- Страница создаётся лениво, при первом показе, и держит фокус ввода только
-- пока открыта.
RppForm = {}

local page, ready, open = nil, false, false
local queue = {}

local function send(event, payload)
    if not page then return end
    if not ready then queue[#queue + 1] = { event, payload }; return end
    local ok, reason = page:send("rpp:" .. event, payload or {})
    if ok == false then print("[rpp_identity] page send " .. event .. " refused: " .. tostring(reason)) end
end

local function focus(enabled)
    if not page then return end
    local ok, reason = page:setFocus(enabled, enabled)
    if ok == false then print("[rpp_identity] focus refused: " .. tostring(reason)) end
end

local function close()
    open = false
    focus(false)
    send("hide")
end

local function ensurePage()
    if page then return true end
    local reason
    page, reason = WebUI.create({
        entry = "web/index.html", layer = "menu",
        width = 1920, height = 1080, fps = 30, zIndex = 760,
        transparent = true, visible = true,
    })
    if not page then
        print("[rpp_identity] WebUI failed: " .. tostring(reason))
        return false
    end
    page:on("rpp:ready", function()
        ready = true
        for _, item in ipairs(queue) do page:send("rpp:" .. item[1], item[2] or {}) end
        queue = {}
    end)
    page:on("rpp:submit", function(payload)
        if not open or type(payload) ~= "table" then return end
        TriggerServerEvent("rpp_identity:submitName", tostring(payload.first or ""), tostring(payload.last or ""))
    end)
    page:on("rpp:close", function(payload)
        local wasForm = type(payload) == "table" and payload.stage == "form"
        close()
        if wasForm then
            TriggerEvent("rpp_identity:formClosed")
        end
    end)
    return true
end

function RppForm.askName()
    if not ensurePage() then return end
    open = true
    send("askName", {
        minLength = RppIdentityConfig.nameMinLength,
        maxLength = RppIdentityConfig.nameMaxLength,
    })
    focus(true)
end

function RppForm.rejected(field, message)
    send("error", { field = field, message = message })
end

function RppForm.confirm(citizen)
    if not ensurePage() then return end
    open = true
    send("confirm", {
        tag = RppNames.citizenTag(citizen.id),
        first = citizen.first,
        last = citizen.last,
    })
    focus(true)
end

function RppForm.isOpen() return open end

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    if page then pcall(page.setFocus, page, false, false) end
    page, ready, open = nil, false, false
end)
