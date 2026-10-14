local addonName, addon = ...

-- Finds ley line / elemental convergence blips on the minimap without the mouse, and hands each to LeyShare as a
-- sighting (a blip only shows while the node is up in the player's phase). Only while LeyShare:Networking() is true,
-- so never alongside SLLCM, which does the same itself.
--
-- The minimap's soft cursor (made for controllers) can be pointed at any spot and asked for the tooltip it would
-- show there. A coarse grid finds blips, then a fine grid around each hit puts its centre within a few yards. With a
-- controller the game drives that soft cursor itself, so instead of scanning, whatever points at the minimap (the
-- mouse, or the controller's SoftCursor) is watched and a blip it passes over is recorded.
--
-- SLLCM's Scan.lua is the reference (the approach came from Skyborne Compass's author); keep the two in step.

local LeyScan = {}
addon.LeyScan = LeyScan

local NAMES = { "Ley Line", "Elemental Convergence" }   -- the minimap tooltip's text; English only, as in SLLCM
local CHECK_SECONDS = 2        -- how often to decide whether to scan
local MOVE_YARDS = 30          -- scan after moving this far
local IDLE_SECONDS = 60        -- or after this long standing still: a node can come up next to you
local COARSE_STEP = 8          -- minimap units between coarse points; a blip is wider than this
local FINE_STEP = 2
local FINE_REACH = 8           -- the fine grid spans this far each way from a coarse hit
local PER_FRAME = 60           -- coarse points per frame, so the scan doesn't stutter
local HOVER_SECONDS = 0.1      -- controller / no scan APIs: how often to look at the pointer
local MAX_SAMPLE_YARDS = 60    -- a hover reading spread wider than this (moved, tooltip lingered) is dropped

local frame                    -- runs a scan in progress, a frame at a time (made by Start)
local scan                     -- the scan in progress: { mapID, points, i, hits, h }
local last                     -- where and when the last scan ran: { mapID, x, y, zoom, at }
local sample                   -- pointer watching: the box of zone positions while a node's tooltip stays up

local function enabled()
    return addon.Options:Get("detectMinimapNodes") and addon.LeyShare:Networking()
end

local function supported()
    return Minimap and Minimap.SetUsingSoftCursor and Minimap.UpdateMouseoverAtPoint and C_TooltipInfo
        and C_TooltipInfo.GetMinimapMouseover and C_Minimap and C_Minimap.GetViewRadius
end

local function strip(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

local function isNodeText(text)
    if type(text) ~= "string" then return false end
    text = strip(text)
    for _, name in ipairs(NAMES) do
        if text:find(name, 1, true) then return true end
    end
    return false
end

-- Does this tooltip data name a node? One tooltip can list several dots.
local function hasNode(data)
    for _, line in ipairs(data and data.lines or {}) do
        if isNodeText(line.leftText) then return true end
    end
    return false
end

-- Is there a node blip at this point (minimap units from its bottom left)?
local function nodeAt(lx, ly)
    local s = Minimap:GetEffectiveScale()
    Minimap:UpdateMouseoverAtPoint((Minimap:GetLeft() + lx) * s, (Minimap:GetBottom() + ly) * s)
    return hasNode(C_TooltipInfo.GetMinimapMouseover())
end

-- Runs fn with the soft cursor on, and always turns it back off.
local function withSoftCursor(fn)
    Minimap:SetUsingSoftCursor(true)
    local ok = pcall(fn)
    Minimap:SetUsingSoftCursor(false)
    return ok
end

local function playerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then return mapID, pos.x, pos.y end
end

-- A minimap point (minimap units from its bottom left) to zone coordinates, from the player's position now.
function LeyScan:ToZone(lx, ly)
    local mapID, px, py = playerPos()
    local zw, zh
    if mapID then zw, zh = addon.LeyShare:ZoneSizeYards(mapID) end
    if not zw then return nil end
    local w, h = Minimap:GetSize()
    local ypp = C_Minimap.GetViewRadius() / (w / 2)
    local dx, dy = (lx - w / 2) * ypp, (ly - h / 2) * ypp     -- yards; +x east, +y north
    if GetCVar("rotateMinimap") == "1" then
        local f = GetPlayerFacing() or 0
        dx, dy = dx * math.cos(f) - dy * math.sin(f), dx * math.sin(f) + dy * math.cos(f)
    end
    local x, y = px + dx / zw, py - dy / zh
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return mapID, x, y end
end

-- A controller is in use: it owns the minimap's soft cursor, so we must not switch it on and off.
local function controller()
    return GetCVarBool("GamePadEnable") or (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled())
end

-- Scan, or (a controller, or a client without the APIs) watch the pointer instead.
local function scanning()
    return supported() and not controller()
end

local function stop()
    scan = nil
    if frame then frame:Hide() end
end

local function blocked()
    return InCombatLockdown() or not Minimap:IsVisible() or Minimap:IsMouseOver()
end

-- One frame of a scan in progress.
function LeyScan:Update()
    if not scan then return stop() end
    -- The player's own mouse on the minimap wins; a zone change makes the hits meaningless.
    if blocked() or not enabled() or C_Map.GetBestMapForUnit("player") ~= scan.mapID then return stop() end

    if scan.i <= #scan.points then
        -- Coarse pass: remember hits, one per blip.
        local ok = withSoftCursor(function()
            for i = scan.i, math.min(scan.i + PER_FRAME - 1, #scan.points) do
                local p = scan.points[i]
                if nodeAt(p[1], p[2]) then
                    local known = false
                    for _, hit in ipairs(scan.hits) do
                        if math.abs(hit[1] - p[1]) <= FINE_REACH and math.abs(hit[2] - p[2]) <= FINE_REACH then
                            known = true
                            break
                        end
                    end
                    if not known then scan.hits[#scan.hits + 1] = { p[1], p[2] } end
                end
            end
        end)
        if not ok then return stop() end
        scan.i = scan.i + PER_FRAME
        return
    end

    -- Fine pass, one blip a frame: the centre of the points that show its tooltip. Run twice, the second centred on
    -- the first result: a coarse hit near the blip's edge clips the first grid.
    local hit = scan.hits[scan.h]
    if not hit then return stop() end
    local sx, sy, n = 0, 0, 0
    local ok = withSoftCursor(function()
        for ox = -FINE_REACH, FINE_REACH, FINE_STEP do
            for oy = -FINE_REACH, FINE_REACH, FINE_STEP do
                if nodeAt(hit[1] + ox, hit[2] + oy) then sx, sy, n = sx + hit[1] + ox, sy + hit[2] + oy, n + 1 end
            end
        end
    end)
    if not ok then return stop() end
    if n > 0 and not hit.refined then
        hit[1], hit[2], hit.refined = sx / n, sy / n, true
        return
    end
    scan.h = scan.h + 1
    if n > 0 then
        local mapID, x, y = self:ToZone(sx / n, sy / n)
        if mapID then addon.LeyShare:OnMinimapNode(mapID, x, y) end
    end
end

-- Coarse grid centred on the minimap, clipped to its round shape unless an addon made it square.
local function coarsePoints()
    local w, h = Minimap:GetSize()
    local cx, cy, r = w / 2, h / 2, math.min(w, h) / 2
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local points, n = {}, math.floor(r / COARSE_STEP)
    for i = -n, n do
        for j = -n, n do
            local ox, oy = i * COARSE_STEP, j * COARSE_STEP
            if square or ox * ox + oy * oy <= r * r then points[#points + 1] = { cx + ox, cy + oy } end
        end
    end
    return points
end

-- Every CHECK_SECONDS: start a scan when the player has moved, zoomed, changed zone, or stood still a while.
function LeyScan:Check()
    if scan or not frame or not enabled() or not scanning() or blocked() then return end
    if IsInInstance() then return end
    local mapID, x, y = playerPos()
    local zw, zh
    if mapID then zw, zh = addon.LeyShare:ZoneSizeYards(mapID) end
    if not zw then return end
    local zoom, now = Minimap:GetZoom(), GetTime()
    if last and last.mapID == mapID and last.zoom == zoom and now - last.at < IDLE_SECONDS
            and math.sqrt(((last.x - x) * zw) ^ 2 + ((last.y - y) * zh) ^ 2) < MOVE_YARDS then
        return
    end
    last = { mapID = mapID, x = x, y = y, zoom = zoom, at = now }
    scan = { mapID = mapID, points = coarsePoints(), i = 1, hits = {}, h = 1 }
    frame:Show()
end

---------------------------------------------------------------------------
-- Pointer watching (a controller, or no scan APIs). The tooltip appears as the pointer reaches the blip's edge, so
-- readings are kept while it stays up and the centre of their box is recorded when it goes.
---------------------------------------------------------------------------

-- Where the pointer is on the minimap (minimap units from its bottom left): the mouse, or the controller's SoftCursor.
local function pointerOnMinimap()
    local s, left, bottom = Minimap:GetEffectiveScale(), Minimap:GetLeft(), Minimap:GetBottom()
    if not left then return nil end
    if Minimap:IsMouseOver() then
        local cx, cy = GetCursorPosition()
        return cx / s - left, cy / s - bottom
    end
    local cursor = SoftCursor
    if cursor and cursor:IsShown() then
        local cx, cy = cursor:GetCenter()
        if not cx then return nil end
        local f = cursor:GetEffectiveScale() / s
        local lx, ly = cx * f - left, cy * f - bottom
        local w, h = Minimap:GetSize()
        if lx >= 0 and ly >= 0 and lx <= w and ly <= h then return lx, ly end
    end
end

-- The minimap's own tooltip data, or failing that GameTooltip's lines (the pointer is on the minimap).
local function hoverShowsNode()
    local data = C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_TooltipInfo.GetMinimapMouseover()
    if data and data.lines and #data.lines > 0 then return hasNode(data) end
    if not GameTooltip:IsShown() then return false end
    for i = 1, GameTooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i]
        if line and isNodeText(line:GetText()) then return true end
    end
    return false
end

local function finishSample()
    if not sample then return end
    local s = sample
    sample = nil
    local zw, zh = addon.LeyShare:ZoneSizeYards(s.mapID)
    if not zw or (s.x1 - s.x0) * zw > MAX_SAMPLE_YARDS or (s.y1 - s.y0) * zh > MAX_SAMPLE_YARDS then return end
    addon.LeyShare:OnMinimapNode(s.mapID, (s.x0 + s.x1) / 2, (s.y0 + s.y1) / 2)
end

-- Every HOVER_SECONDS, when not scanning.
function LeyScan:Watch()
    if scanning() or not enabled() then return finishSample() end
    local lx, ly = pointerOnMinimap()
    local ok, node = pcall(hoverShowsNode)           -- tooltip text can be secret in combat
    if not (lx and ok and node) then return finishSample() end
    local mapID, x, y = self:ToZone(lx, ly)
    if not mapID then return end
    if sample and sample.mapID ~= mapID then finishSample() end
    if not sample then
        sample = { mapID = mapID, x0 = x, x1 = x, y0 = y, y1 = y }
    else
        sample.x0, sample.x1 = math.min(sample.x0, x), math.max(sample.x1, x)
        sample.y0, sample.y1 = math.min(sample.y0, y), math.max(sample.y1, y)
    end
end

-- At login (once): the scan frame and the two tickers. Each does nothing while sharing is off or SLLCM is loaded.
function LeyScan:Start()
    if frame or not Minimap then return end
    frame = CreateFrame("Frame")
    frame:Hide()
    frame:SetScript("OnUpdate", function() LeyScan:Update() end)
    C_Timer.NewTicker(CHECK_SECONDS, function() LeyScan:Check() end)
    C_Timer.NewTicker(HOVER_SECONDS, function() LeyScan:Watch() end)
end

-- Tests only: forget the scan, the last scan's place and any hover sample (and the frame, so Start runs again).
function LeyScan:ResetForTests()
    frame, scan, last, sample = nil, nil, nil, nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() LeyScan:Start() end)
