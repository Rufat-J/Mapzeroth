local addonName, addon = ...

-- The one-time question (per account) whether to share ley line and convergence sightings (LeyShare.lua). Asked a
-- few seconds after login or /reload on a Skyborne character, unless Skyborne Ley Line & Convergence Marker is loaded
-- (it asks its own). Sharing stays off until the player answers; either answer is final until changed on the
-- settings page.
--
-- All styling goes through addon.Theme. The frame is built on first use, never at load.

local SharePrompt = {}
addon.SharePrompt = SharePrompt

local L = addon.L
local Theme = addon.Theme

local WIDTH, PAD = 420, 16
local ASK_DELAY = 5             -- seconds after login, so it doesn't land in the middle of the loading screen's aftermath

local ui

local function build()
    ui = {}
    SharePrompt.widgets = ui                -- for tests
    local frame = Theme:Panel(UIParent, "MapzerothRebuildSharePrompt")
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    ui.frame = frame

    ui.title = Theme:Text(frame, "title")
    ui.title:SetPoint("TOPLEFT", PAD, -PAD)
    ui.title:SetWidth(WIDTH - 2 * PAD)
    ui.title:SetWordWrap(true)
    ui.title:SetText(L["SHARE_TITLE"])

    ui.text = Theme:Text(frame, "body")
    ui.text:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -12)
    ui.text:SetWidth(WIDTH - 2 * PAD)
    ui.text:SetWordWrap(true)
    ui.text:SetText(L["SHARE_TEXT"])

    ui.later = Theme:Text(frame, "dim")
    ui.later:SetPoint("TOPLEFT", ui.text, "BOTTOMLEFT", 0, -12)
    ui.later:SetWidth(WIDTH - 2 * PAD)
    ui.later:SetWordWrap(true)
    ui.later:SetText(L["SHARE_LATER"])

    ui.decline = Theme:Button(frame, L["SHARE_DECLINE"], 130, 24)
    ui.decline:SetPoint("BOTTOMLEFT", PAD, PAD)
    ui.decline:SetScript("OnClick", function() SharePrompt:Answer(false) end)

    ui.enable = Theme:Button(frame, L["SHARE_ENABLE"], 130, 24, true)
    ui.enable:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ui.enable:SetScript("OnClick", function() SharePrompt:Answer(true) end)
end

-- Height from the wrapped text: the frame grows to fit the language it is in.
local function fit()
    local h = PAD + ui.title:GetStringHeight() + 12 + ui.text:GetStringHeight() + 12 + ui.later:GetStringHeight()
        + 16 + 24 + PAD
    ui.frame:SetHeight(math.ceil(h))
end

function SharePrompt:Show()
    if not ui then build() end
    ui.frame:Show()
    fit()
end

function SharePrompt:IsShown()
    return ui ~= nil and ui.frame:IsShown()
end

-- The player's answer: kept, and asked no more on any character of the account.
function SharePrompt:Answer(on)
    addon.Options:Store("shareAsked", true)
    addon.Options:Set("shareSightings", on)
    if ui then ui.frame:Hide() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, _, isLogin, isReload)
    if not (isLogin or isReload) then return end           -- zoning: asked already, or not wanted
    C_Timer.After(ASK_DELAY, function()
        if addon.LeyShare:ShouldAsk() and not SharePrompt:IsShown() then SharePrompt:Show() end
    end)
end)
