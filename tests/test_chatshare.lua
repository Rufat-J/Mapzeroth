-- Sharing a place in chat (ChatShare.lua): the line, the map pin link, which of several places, and where it goes.
useTestDistances()
addon.World:Build()

local CS = addon.ChatShare
local saved = { C_Map = C_Map, util = ChatFrameUtil, insert = ChatEdit_InsertLink, open = ChatFrame_OpenChat, pin = MAP_PIN_HYPERLINK }

local pinMaps = { [1411] = true }
local player = { 1411, 0.43, 0.70 }           -- in Durotar, by the trainer at 42.5, 69.0
C_Map = setmetatable({
    GetMapInfo = function(id) return { name = id == 1411 and "Durotar" or ("map " .. id) } end,
    CanSetUserWaypointOnMap = function(id) return pinMaps[id] == true end,
    GetBestMapForUnit = function() return player[1] end,
    GetPlayerMapPosition = function() return { GetXY = function() return player[2], player[3] end } end,
}, { __index = saved.C_Map })
MAP_PIN_HYPERLINK = "|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location"

local one = { name = "Mage Trainer", nodeIDs = { "TRAINER_MAGE_5880" } }
local text = CS:Text(one)
local name = addon:GetNodeName("TRAINER_MAGE_5880")
check(text == ("[Mapzeroth] %s - Durotar (56.2, 75.0) |cffffff00|Hworldmap:1411:5620:7500|h[%s]|h|r"):format(name, MAP_PIN_HYPERLINK),
    "name, zone, coordinates and the game's map pin link: " .. tostring(text))

-- A "nearest" pick shares the one nearest the player, by its own name.
local nearest = { name = "Nearest Mage Trainer", pick = true, nodeIDs = { "TRAINER_MAGE_5880", "TRAINER_MAGE_5884" } }
check(CS:NodeOf(nearest).id == "TRAINER_MAGE_5884", "of two, the nearer one")
check(CS:Text(nearest):find("(42.5, 69.0)", 1, true), "and its spot: " .. CS:Text(nearest))
player = { 1411, 0.56, 0.74 }
check(CS:NodeOf(nearest).id == "TRAINER_MAGE_5880", "standing elsewhere, the other")

-- A map the game won't put a pin on: the text alone.
pinMaps[1411] = nil
check(CS:Text(one) == ("[Mapzeroth] %s - Durotar (56.2, 75.0)"):format(name), "no pin where the map can't hold one: " .. CS:Text(one))
pinMaps[1411] = true

-- Nothing to share: headers, actions (the paste box, TomTom), places that aren't nodes of ours (the waypoint).
check(CS:Text({ header = true, id = "x", nodeIDs = { "TRAINER_MAGE_5880" } }) == nil, "a heading shares nothing")
check(CS:Text({ action = "paste" }) == nil, "an action shares nothing")
check(CS:Text({ name = "Your waypoint", nodeIDs = { "WAYPOINT_1411_1_1" } }) == nil and not CS:CanShare({ nodeIDs = { "WAYPOINT_1411_1_1" } }),
    "nor a place that isn't a node of ours")
check(CS:CanShare(nearest), "a pick can be shared")

-- Into chat: an open chat box takes it at the cursor; with none open, one opens with it.
local inserted, opened
ChatFrameUtil = nil
ChatEdit_InsertLink = function(t) inserted = t; return true end
ChatFrame_OpenChat = function(t) opened = t end
check(CS:Share(one) and inserted == text and opened == nil, "a chat box open: added to it")
inserted = nil
ChatEdit_InsertLink = function() return false end
check(CS:Share(one) and opened == text, "none open: one opens with the line in it")
-- A client with ChatFrameUtil uses it.
opened = nil
ChatFrameUtil = { InsertLink = function(t) inserted = t; return true end }
check(CS:Share(one) and inserted == text and opened == nil, "ChatFrameUtil's InsertLink when the client has it")
check(not CS:Share({ header = true }), "nothing to share: nothing happens")

C_Map, ChatFrameUtil, ChatEdit_InsertLink, ChatFrame_OpenChat, MAP_PIN_HYPERLINK = saved.C_Map, saved.util, saved.insert, saved.open, saved.pin
