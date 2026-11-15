-- open77_creator texts, in English (Open77 UIs are English whatever the game's language). The
-- game's own labels follow the game's language, so option and choice names are written here or
-- derived from the catalogue's internal names instead.
CreatorText = {
    title = "Character creator", titleTop = "Character", titleBottom = "Creator",
    identity = "Identity",
    subtitle = "Define your appearance in Night City",
    bodyType = "Body type", male = "Masculine", female = "Feminine",
    presets = "Starting looks", random = "Randomize",
    save = "Confirm", cancel = "Cancel", later = "Later",
    categories = { body = "Body", face = "Face", eyes = "Eyes & brows", hair = "Hair & beard",
                   makeup = "Makeup", marks = "Tattoos & piercings" },
    presetNames = { nomad = "Nomad", street = "Street Kid", streetkid = "Street Kid", street_kid = "Street Kid", corpo = "Corpo" },
    none = "None", shape = "Shape", style = "Style", option = "Option",
    hintRotate = "Rotate", hintZoom = "Zoom", hintDrag = "Drag to turn and pan",
    applying = "Applying", rebuilding = "Rebuilding body", saving = "Saving", saved = "Look saved",
    noAnswer = "No answer from the server, try again",
    failed = "The creator could not open: %s",
    empty = "Nothing to change here for this body type.",
}

-- One name per catalogue uiSlot.
CreatorText.slots = {
    skin_color = "Skin tone", skin_type_switcher = "Skin type", breast = "Chest size",
    nipples_switcher = "Nipples", body_tattoo_switcher = "Body tattoos", body_scars_switcher = "Body scars",
    nails_l = "Nail length", nails_color = "Nail color",
    eyes = "Eye shape", nose = "Nose", mouth = "Mouth", jaw = "Jaw", ear = "Ears", teeth = "Teeth",
    scars = "Face scars", cyberware_switcher = "Face cyberware",
    eyes_color = "Eye color", eyebrows = "Eyebrows", eyebrows_color = "Eyebrow color", eyelash_color = "Eyelash color",
    hairstyle = "Hairstyle", hair_color = "Hair color", beard = "Beard", beard_part = "Beard style", beard_color = "Beard color",
    makeupEyes = "Eye makeup", makeupEyes_color = "Eye makeup color",
    makeupLips_type = "Lipstick", makeupLips = "Lipstick style", makeupLips_color = "Lipstick color",
    makeupCheeks = "Blush", makeupCheeks_color = "Blush color",
    makeupPimples = "Blemishes", makeupPimples_color = "Blemish color",
    facial_tattoo_switcher = "Face tattoo", piercings = "Piercings", piercings_color = "Piercing color",
}

local SKIP = { ca = true, bl = true, pwa = true, pma = true, wa = true, ma = true, base = true, fpp = true, tpp = true }
-- A name left with only these words is the option's base look.
local GENERIC = { basehead = true, head = true, default = true, body = true, base = true }

local function titleCase(words)
    local out = {}
    for _, word in ipairs(words) do out[#out + 1] = word:sub(1, 1):upper() .. word:sub(2):lower() end
    return table.concat(out, " ")
end

-- "h0_000_pwa__basehead__01_ca_pale_00_warm_ivory" -> "Warm Ivory", "05_brown_liquorice" -> "Brown Liquorice".
function CreatorInternalName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name == "None" then return CreatorText.none end
    local tail = name:match(".*__(.+)$") or name
    local tokens = {}
    for token in tail:gmatch("[^_]+") do tokens[#tokens + 1] = token end
    -- The words after the last number are the variant's own name.
    local last = 0
    for i, token in ipairs(tokens) do
        if token:match("^%d+$") then last = i end
    end
    local words = {}
    for i = last + 1, #tokens do
        if not SKIP[tokens[i]:lower()] then words[#words + 1] = tokens[i] end
    end
    if #words == 0 then
        for _, token in ipairs(tokens) do
            if not token:match("^%d+$") and not SKIP[token:lower()] then words[#words + 1] = token end
        end
    end
    if #words == 0 then return nil end
    local generic = true
    for _, word in ipairs(words) do
        if not GENERIC[word:lower()] then generic = false end
    end
    if generic then return "Default" end
    return titleCase(words)
end
