local addonName, addon = ...

-- Sharing a place in chat: a shift-click on a row in the picker puts
--   [Mapzeroth] Name - Zone (x, y) [Map Pin Location]
-- into the chat box (the one open, else it opens one), for the player to send. The last part is the game's own map pin
-- link, the one the map's "share pin" sends: whoever clicks it gets that spot as their map waypoint. A map the game
-- won't put a pin on (an interior) gets the text alone. Nothing is sent by us: the player sees it and presses Enter.

local ChatShare = {}
addon.ChatShare = ChatShare

local L = addon.L

-- The node of an entry to share: its only one, or (a "nearest" pick, a city's entrances) the one nearest the player in
-- a straight line, else the first. Nil when the entry has none of ours (a header, the waypoint, a tour).
function ChatShare:NodeOf(entry)
    if not (entry and entry.nodeIDs and not entry.header and not entry.action) then return nil end
    local World, best, bestDistance = addon.World, nil, nil
    local here = #entry.nodeIDs > 1 and addon:GetPlayerStart() or nil
    for _, id in ipairs(entry.nodeIDs) do
        local node = World:GetNode(id)
        if node and node.mapID and node.x and node.y then
            if not here then return node end
            local d = addon.TravelGraph.DistanceProvider(here, node)
            if not best or (d and (not bestDistance or d < bestDistance)) then best, bestDistance = node, d end
        end
    end
    return best
end

-- Whether an entry has a place to share (cheap: for the tooltip's hint, without measuring anything).
function ChatShare:CanShare(entry)
    if not (entry and entry.nodeIDs and not entry.header and not entry.action) then return false end
    for _, id in ipairs(entry.nodeIDs) do
        if addon.World:GetNode(id) then return true end
    end
    return false
end

-- The game's map pin link for a spot, or nil where it can't hold one.
local function pinLink(mapID, x, y)
    local map = C_Map
    if not (map and map.CanSetUserWaypointOnMap) then return nil end
    local ok, can = pcall(map.CanSetUserWaypointOnMap, mapID)
    if not (ok and can) then return nil end
    return ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5),
        MAP_PIN_HYPERLINK or "Map Pin Location")
end

-- The line to put in chat for an entry, or nil when there is nothing to share. The name is the node's own (the trainer
-- it chose, not "Nearest Mage Trainer"), falling back to the entry's.
function ChatShare:Text(entry)
    local node = self:NodeOf(entry)
    if not node then return nil end
    local name = addon:GetNodeName(node.id)
    if not name or name == node.id then name = entry.name end
    local text = L["CHAT_SHARE_LINE"]:format(name, addon:GetZoneName(node.mapID) or "?", node.x * 100, node.y * 100)
    local pin = pinLink(node.mapID, node.x, node.y)
    return pin and (text .. " " .. pin) or text
end

-- Puts the entry's line into chat. Returns true when there was something to put there.
function ChatShare:Share(entry)
    local text = self:Text(entry)
    if not text then return false end
    local util = ChatFrameUtil
    local insert = (util and util.InsertLink) or ChatEdit_InsertLink
    if insert and insert(text) then return true end        -- a chat box was open: added where the cursor is
    local open = (util and util.OpenChat) or ChatFrame_OpenChat
    if open then open(text) end
    return open ~= nil
end
