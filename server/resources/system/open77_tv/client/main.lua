-- open77_tv -- client/main.lua
-- A YouTube television in front of the player. The game's own TV mesh; Open77.screens
-- swaps its screen material for one showing the player page, and plays the video's
-- sound from the set (3D: distance and walls).

if type(Open77.screens) ~= "table" then
    print("[open77_tv] Open77.screens unavailable on this client (needs client 237+)")
    return
end

local tv = { props = {}, page = nil, screen = nil, url = nil }

local function clear()
    if tv.screen then Open77.screens.destroy(tv.screen) end
    if tv.page then tv.page:destroy() end
    for _, id in ipairs(tv.props) do Open77.props.remove(id) end
    tv = { props = {}, page = nil, screen = nil, url = nil }
end

local function inFront(distance)
    local x, y, z = Open77.character.position()
    local yaw = Open77.character.yaw() or 0.0
    local r = math.rad(yaw) -- yaw 0 faces +Y, counter-clockwise seen from above
    return x - math.sin(r) * distance, y + math.cos(r) * distance, z, yaw
end

-- The player page (web/tv.html): it takes a URL and plays YouTube, Vimeo or a file.
local function createPage(url, attempt)
    attempt = attempt or 1
    local page, reason = WebUI.create({ entry = "web/tv.html", width = 1920, height = 1080, fps = 30,
                                        worldScreen = true, transparent = false, policy = "media" })
    if not page then
        if reason == "resource_preparing" and attempt < 40 then
            SetTimeout(500, function() createPage(url, attempt + 1) end)
        else
            print("[open77_tv] page failed: " .. tostring(reason))
        end
        return
    end
    page:on("media:ready", function()
        page:send("media:state", { id = "open77_tv", label = "Open77", url = url, volume = 80, muted = false,
                                   paused = false, border = false, curtain = "open" })
    end)
    tv.page = page
    if tv.screen then Open77.screens.setSource(tv.screen, { page = page }) end
end

local function place(url)
    clear()
    tv.url = url
    local x, y, z, yaw = inFront(3.0)
    local facing = yaw + 180.0 -- the screen faces the player
    local panel
    for _, model in ipairs({ "electronics.tv.16x9", "electronics.tv.screen.16x9" }) do
        local id, reason = Open77.props.create({ model = model, position = { x = x, y = y, z = z }, yaw = facing })
        if not id then
            print("[open77_tv] prop failed: " .. tostring(reason))
            return
        end
        tv.props[#tv.props + 1] = id
        panel = id
    end
    local screen, why = Open77.screens.create({ width = 1920, height = 1080,
                                                audio = { volume = 1.0, minDistance = 2.0, maxDistance = 25.0 } })
    if not screen then
        print("[open77_tv] screen failed: " .. tostring(why))
        return
    end
    tv.screen = screen
    -- The panel's screen chunk is found by its material; the attachment waits for the prop.
    Open77.screens.attach(screen, { localProp = panel })
    createPage(url)
    print(("[open77_tv] television at %.1f %.1f %.1f playing %s"):format(x, y, z, url))
end

RegisterNetEvent("open77_tv:here", function(url)
    place(type(url) == "string" and url ~= "" and url or "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
end)

-- J: sit in front of the set with the cursor on the player; Escape (or J) gives the view back.
RegisterKeyMapping("open77_tv.use", "Television: use it", "J", function()
    if not tv.screen then return end
    if Open77.screens.interacting() then
        Open77.screens.leave()
        return
    end
    local ok, err = Open77.screens.interact(tv.screen, { blendMs = 600 })
    if not ok then print("[open77_tv] interact: " .. tostring(err)) end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then clear() end
end)
