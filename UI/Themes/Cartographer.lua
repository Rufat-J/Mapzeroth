local addonName, addon = ...

-- Cartographer: a light theme that sits beside the world map as part of it. Parchment a shade darker than the map's
-- own, sepia ink, a wax-seal red for what to press, the quest titles' serif for headings. The game's fonts carry a
-- dark drop shadow that blurs dark text on a light ground, so this theme goes without it (noShadow).

local function rgb(hex, alpha)
    local r, g, b = hex:match("(%x%x)(%x%x)(%x%x)")
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha or 1 }
end

local FLAT = "Interface\\Buttons\\WHITE8x8"

addon.Theme:Register("cartographer", {
    label = "Cartographer",
    colors = {
        panel = rgb("b49c72"), panelBorder = rgb("6e5636"), header = rgb("a68e65"),
        text = rgb("20180e"), dim = rgb("3f3019"), accent = rgb("7a2214"),
        good = rgb("1f5c54"), warn = rgb("8a4a10"),
        buttonBg = rgb("c4ad84"), buttonHover = rgb("cfb991"), buttonPressed = rgb("a68e65"),
        buttonText = rgb("20180e"), primaryBg = rgb("7a2214"), primaryText = rgb("f0e4c8"),
        editBg = rgb("c9b48c"), editBorder = rgb("6e5636"),
        rowHover = rgb("20180e", 0.08), rowSelected = rgb("7a2214", 0.16), divider = rgb("8c7350"),
    },
    fonts = { title = "QuestTitleFont", body = "GameFontHighlight", small = "GameFontHighlightSmall" },
    noShadow = true,
    stopBadges = true,
    methodTimes = true,
    panel = { backdrop = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
                           insets = { left = 1, right = 1, top = 1, bottom = 1 } } },
    button = "flat",
    edit = { backdrop = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } } },
    styles = {                                   -- ink colours: they sit on parchment
        foot = rgb("3f3019"), flight = rgb("1f5c54"), boat = rgb("1f4f7a"), ability = rgb("5b3f7a"),
        default = rgb("3f3019"),
    },
    map = {                                      -- the same as Modern Dark's: bright on a dark casing reads on any map art
        foot = rgb("f4f1ea"), flight = rgb("4fd8c0"), boat = rgb("5aa0ff"), ability = rgb("c070ff"),
        casing = rgb("14181e", 0.85), stop = rgb("f4f1ea"), dest = rgb("e5533f"),
    },
    stepIcon = { size = 18, crop = 0.1 },
    markers = {
        place = rgb("7a2214"), flight = rgb("1f5c54"), transport = rgb("1f4f7a"), instance = rgb("8a2e1f"),
        leyline = rgb("5b3f7a"), convergence = rgb("8a4a10"), waypoint = rgb("7a2214"), default = rgb("3f3019"),
    },
})
