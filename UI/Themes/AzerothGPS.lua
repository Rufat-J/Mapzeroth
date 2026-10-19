local addonName, addon = ...

-- AzerothGPS: a compact dark navigation palette with cyan guidance accents.
-- comes from the design mock-ups (docs/ui): ink #111923, edge #344253, cream #f3f7fb,
-- brass #63d7ff, verdigris #52d6bd.

local function rgb(hex, alpha)
    local r, g, b = hex:match("(%x%x)(%x%x)(%x%x)")
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha or 1 }
end

local FLAT = "Interface\\Buttons\\WHITE8x8"

addon.Theme:Register("azerothgps", {
    label = "AzerothGPS",
    colors = {
        panel = rgb("111923"), panelBorder = rgb("344253"), header = rgb("1b2937"),
        text = rgb("f3f7fb"), dim = rgb("9eadbc"), accent = rgb("63d7ff"),
        good = rgb("52d6bd"), warn = rgb("e6a35a"),
        buttonBg = rgb("243545"), buttonHover = rgb("344253"), buttonPressed = rgb("1b2937"),
        buttonText = rgb("f3f7fb"), primaryBg = rgb("63d7ff"), primaryText = rgb("111923"),
        editBg = rgb("0d1721"), editBorder = rgb("344253"),
        rowHover = rgb("f3f7fb", 0.06), rowSelected = rgb("63d7ff", 0.16), divider = rgb("344253"),
    },
    fonts = { title = "GameFontNormalLarge", body = "GameFontHighlight", small = "GameFontHighlightSmall" },
    stopBadges = true,                           -- a tour's stops numbered in a disc, their steps set in under them
    methodTimes = true,                          -- step times in the colour of how the step travels
    panel = { backdrop = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
                           insets = { left = 1, right = 1, top = 1, bottom = 1 } } },
    button = "flat",
    edit = { backdrop = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } } },
    styles = {
        foot = rgb("f3f7fb"), flight = rgb("52d6bd"), boat = rgb("6ba9ff"), ability = rgb("b38cf0"),   -- the map's hues, softer
        default = rgb("9eadbc"),
    },
    map = {                                      -- brighter than the panel's: the map is parchment
        foot = rgb("f3f7fb"), flight = rgb("4fd8c0"), boat = rgb("5aa0ff"), ability = rgb("c070ff"),
        casing = rgb("111923", 0.85), stop = rgb("f3f7fb"), dest = rgb("e5533f"),
    },
    stepIcon = { size = 18, crop = 0.1 },        -- trimmed of their frame: flat squares, like the rest
    markers = {
        place = rgb("63d7ff"), flight = rgb("52d6bd"), transport = rgb("52d6bd"), instance = rgb("c0554d"),
        leyline = rgb("8f7bd4"), convergence = rgb("d47f5a"), waypoint = rgb("63d7ff"), default = rgb("9eadbc"),
    },
})
