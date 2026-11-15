-- open77_creator: what the creator shows, how it frames the player, and when it opens.
-- A server tunes it without editing the resource:
--   convar open77_creator_open_new      "true" (default): open by itself for a new character
--   convar open77_creator_command       "creator" (default): chat command that reopens it ("" = none)
CreatorConfig = {}
local C = CreatorConfig

-- The categories, in order. Each lists catalogue `uiSlot`s (Open77.body.catalog): the creator shows
-- the option of each slot that is active for the current choices (a hair colour per hairstyle,
-- a lipstick colour per lipstick type...). `shot` picks the camera framing.
C.categories = {
    { id = "body", shot = "body", slots = {
        "skin_color", "skin_type_switcher", "breast", "nipples_switcher", "body_tattoo_switcher",
        "body_scars_switcher", "nails_l", "nails_color" } },
    { id = "face", shot = "face", slots = {
        "eyes", "nose", "mouth", "jaw", "ear", "teeth", "scars", "cyberware_switcher" } },
    { id = "eyes", shot = "eyes", slots = {
        "eyes_color", "eyebrows", "eyebrows_color", "eyelash_color" } },
    { id = "hair", shot = "hair", slots = {
        "hairstyle", "hair_color", "beard", "beard_part", "beard_color" } },
    { id = "makeup", shot = "face", slots = {
        "makeupEyes", "makeupEyes_color", "makeupLips_type", "makeupLips", "makeupLips_color",
        "makeupCheeks", "makeupCheeks_color", "makeupPimples", "makeupPimples_color" } },
    { id = "marks", shot = "face", slots = {
        "facial_tattoo_switcher", "piercings", "piercings_color" } },
}

-- Camera shots, in the player's own frame (x right, y forward, z up), metres. `distance` is how far
-- in front, `height` the camera height, `look` the height it aims at, `side` a sideways offset
-- that centres the character between the two panels (the right one is wider).
C.shots = {
    body = { distance = 2.55, height = 1.15, look = 0.98, side = 0.09, fov = 46 },
    face = { distance = 1.05, height = 1.67, look = 1.62, side = 0.028, fov = 34 },
    eyes = { distance = 0.72, height = 1.69, look = 1.66, side = 0.017, fov = 30 },
    hair = { distance = 1.25, height = 1.76, look = 1.66, side = 0.035, fov = 36 },
}
C.turnSpeed = 110       -- degrees per second while Q / E are held (eased in and out)
C.zoomStep = 0.12       -- distance factor per mouse wheel notch
C.previewDelayMs = 120  -- a burst of changes is applied once, after this pause

-- The camera travels between shots instead of cutting: it eases along the way, swings around the
-- character and pulls back a little in the middle of the move, like a crane shot.
C.camera = {
    travelSeconds = { min = 0.85, max = 1.5 },  -- by how far the next shot is
    swingDegrees = 15,       -- how far it swings sideways during a travelling (0 = straight line)
    liftRatio = 0.14,        -- how much it pulls back in the middle, as a share of the distance covered
    intro = { seconds = 1.9, distance = 1.4, height = 0.28, angle = -26 }, -- the opening move
    dragDegrees = 0.32,      -- degrees per pixel of a drag across the character
    panMetres = 0.0016,      -- metres per pixel of a vertical drag
    panLimit = 0.45,
    driftDegrees = 0.7,      -- a slow idle sway, so the shot never looks frozen (0 = still)
    driftHeight = 0.006,
}
-- Depth: the panels are tilted toward the player like a cockpit, float slowly, and the whole
-- interface leans a little after the mouse and against the camera's turn. Degrees and dp.
C.depth = {
    perspective = 1500,   -- dp from the eye to the panels; smaller is stronger
    tilt = 8,             -- how far the side panels turn toward the player (0 = flat)
    lean = 9,             -- how far the command bar and the brand bar lean
    float = 4,            -- dp of the slow up and down drift (0 = still)
    sway = 0.8,           -- degrees of the slow turn that goes with it
    parallax = 1.1,       -- degrees the interface leans after the mouse (0 = none)
    inertia = 0.012,      -- degrees it leans per degree per second of camera turn
}
-- The picture of each starting look (ui/looks/<file>.png), by preset name of the game's catalogue.
C.looks = { nomad = "nomad", street = "street", streetkid = "street", street_kid = "street", corpo = "corpo" }
C.sounds = { hover = "ui_menu_hover", press = "ui_menu_onpress" } -- game UI sounds (nil = silent)

local function convar(name, fallback)
    if type(GetConvar) ~= "function" then return fallback end
    local value = GetConvar(name, fallback)
    if value == nil or value == "" then return fallback end
    return value
end

C.openForNewCharacters = convar("open77_creator_open_new", "true") ~= "false"
C.command = convar("open77_creator_command", "creator")
