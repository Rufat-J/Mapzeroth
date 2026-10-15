local addonName, addon = ...

-- On the flight master's map, a ring round the flight point the route being followed flies to, so the player can see
-- which one to click. It only draws: it never clicks, hovers or changes the game's map, and sits on the game's own
-- node button (the classic TaxiFrame's TaxiButton<slot>) or pin (retail's FlightMapFrame), whichever window is open.

local TaxiMark = {}
addon.TaxiMark = TaxiMark

local SIZE_FACTOR = 2.2          -- the ring's size, as a multiple of the node button's
local MIN_SIZE, MAX_SIZE = 26, 52
local RETRY = 0.1                -- seconds: the retail map adds its pins as it shows, maybe after our event

local mark
local shown = 0                  -- counts windows opened and closed, so a late placing for a closed one does nothing

-- The open window's node with this id: its slot, and whether it can be flown to from here.
local function nodeInfo(nodes, nodeID)
    local reachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable or 1
    for _, node in ipairs(nodes) do
        if node.nodeID and "TAXI_" .. node.nodeID == nodeID then return node.slotIndex, node.state == reachable end
    end
end

-- Where the player is: the open window's Current node, as "TAXI_<id>".
local function currentNode(nodes)
    local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0
    for _, node in ipairs(nodes) do
        if node.state == current and node.nodeID then return "TAXI_" .. node.nodeID end
    end
end

-- The game's button or pin for a node, in whichever flight window is open.
function TaxiMark.Anchor(slot, nodeID)
    local flightMap = _G.FlightMapFrame
    if flightMap and flightMap:IsShown() and flightMap.EnumeratePinsByTemplate then
        local ok, pins = pcall(flightMap.EnumeratePinsByTemplate, flightMap, "FlightMap_FlightPointPinTemplate")
        if ok and pins then
            for pin in pins do
                local data = pin.taxiNodeData
                if data and (data.slotIndex == slot or data.nodeID == nodeID) and pin:IsShown() then return pin end
            end
        end
    end
    local button = _G["TaxiButton" .. slot]
    if button and button:IsShown() then return button end
end

-- The flight point to mark, as { slot, nodeID }, or nil: the route's next flight from here, if it can be flown.
function TaxiMark.Target(nodes)
    local target = addon.Navigation:FlightTarget(currentNode(nodes))
    if not target then return nil end
    local slot, reachable = nodeInfo(nodes, target)
    if not (slot and reachable) then return nil end
    return slot, tonumber(target:match("^TAXI_(%d+)$"))
end

local function place(slot, nodeID)
    local anchor = TaxiMark.Anchor(slot, nodeID)
    if not anchor then return false end
    mark = mark or addon.Theme:TaxiMark(anchor:GetParent())
    mark:SetParent(anchor:GetParent())
    mark:SetFrameStrata(anchor:GetFrameStrata())
    mark:SetFrameLevel(anchor:GetFrameLevel() + 5)
    local w, h = anchor:GetSize()
    local size = math.max(MIN_SIZE, math.min(MAX_SIZE, math.max(w or 0, h or 0) * SIZE_FACTOR))
    mark:SetSize(size, size)
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", anchor, "CENTER")
    mark:Show()
    return true
end

-- TAXIMAP_OPENED: mark the route's next flight, once the window has drawn its nodes.
function TaxiMark:OnOpened()
    self:Hide()
    local nodes = addon.FlightKnowledge:WindowNodes()
    if not (nodes and addon.Navigation:IsActive()) then return end
    local slot, nodeID = TaxiMark.Target(nodes)
    if not slot then return end
    local window = shown
    C_Timer.After(0, function()
        if window ~= shown or place(slot, nodeID) then return end
        C_Timer.After(RETRY, function()
            if window == shown then place(slot, nodeID) end
        end)
    end)
end

-- The ring, or nil before the first one (for tests).
function TaxiMark.Mark() return mark end

-- TAXIMAP_CLOSED.
function TaxiMark:Hide()
    shown = shown + 1
    if mark then
        mark:Hide()
        mark:ClearAllPoints()
    end
end
