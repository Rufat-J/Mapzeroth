-- Sharing ley line sightings with Skyborne Ley Line & Convergence Marker (LeyShare.lua): the wire format both addons
-- speak, phase reading, and the nearest-ley-line pick going to a node seen up in the player's phase.

useTestDistances()
addon.World:Build()

local LS = addon.LeyShare

-- A Skyborne Alliance character in Arathi, sharing on, on a client with the channel joined as /5.
local now, clock = 1800000000, 1000
function GetServerTime() return now end
function GetTime() return clock end
function UnitRace() return "Skyborne", "Skyborne", 99 end
function UnitFactionGroup() return "Alliance" end
function strsplit(sep, text, limit)
    local out, start = {}, 1
    while true do
        if limit and #out == limit - 1 then out[#out + 1] = text:sub(start) break end
        local i = text:find(sep, start, true)
        if not i then out[#out + 1] = text:sub(start) break end
        out[#out + 1] = text:sub(start, i - 1)
        start = i + 1
    end
    return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local loaded = {}
C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] or false end }
local mapNow = 1417
C_Map = {
    GetMapInfo = function(id) return { name = "map " .. id } end,
    GetBestMapForUnit = function() return mapNow end,
    -- 2500 x 1700 yards a map, like useTestDistances; each map its own continent, so maps never meet.
    GetWorldPosFromMapPos = function(id, v) return id, CreateVector2D(v.x * 2500, v.y * 1700) end,
}
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers()
    for _ = 1, 50 do
        local list = timers
        timers = {}
        if #list == 0 then return end
        for _, fn in ipairs(list) do fn() end
    end
end
local sent = {}
C_ChatInfo = { SendAddonMessage = function(prefix, msg, kind, id)
    check(prefix == "SLLCM" and kind == "CHANNEL" and id == 5, "sent on SLLCM's prefix to the channel")
    sent[#sent + 1] = msg
    return 0
end }
function GetChannelName(name) return name == "SLLCMShareA" and 5 or 0 end
MapzerothRebuildDB = {}
addon.Options:Set("shareSightings", true)

local function reset()
    LS:ResetForTests()
    MapzerothRebuildDB.sightings, MapzerothRebuildDB.sharedNodes = nil, nil
    sent, timers = {}, {}
end

check(LS:Networking(), "a Skyborne with sharing on joins in")
UnitRace = function() return "Human", "Human", 1 end
check(not LS:Networking(), "anyone else doesn't")
UnitRace = function() return "Skyborne", "Skyborne", 99 end
addon.Options:Set("shareSightings", false)
check(not LS:Networking(), "nor with sharing off")
addon.Options:Set("shareSightings", true)

-- Phase: the first creature read is used at once; a second kind agreeing confirms it; then a new phase needs two
-- kinds of NPC agreeing; players and pets don't count.
reset()
LS:ReadGUID("Player-1-0ABC")
check(LS:Phase() == nil, "a player's GUID says nothing")
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
local p, tentative = LS:Phase()
check(p == "3104" and tentative, "the first creature gives the phase, tentatively")
check(#sent == 1 and sent[1] == "Q:1:A:3104", "and it asks what's known there (Arathi has ley lines): " .. tostring(sent[1]))
LS:ReadGUID("Creature-0-1-2-3104-5678-0002")
p, tentative = LS:Phase()
check(p == "3104" and not tentative, "a second kind agreeing confirms it")
LS:ReadGUID("Creature-0-1-2-4200-1111-0003")
LS:ReadGUID("Creature-0-1-2-4200-1111-0004")
check(LS:Phase() == "3104", "one kind of NPC elsewhere isn't enough to move a confirmed phase")
LS:ReadGUID("Vehicle-0-1-2-4200-2222-0005")
check(LS:Phase() == "4200", "two kinds are")
clock = clock + 5
LS:ReadGUID("Creature-0-1-2-3104-1234-0006")
LS:ReadGUID("Creature-0-1-2-3104-5678-0007")
runTimers()
check(LS:Phase() == "3104" and #sent == 2, "messages go out 1.25 s apart; asking again for a phase waits 30 s: " .. #sent)

-- Receiving: R, the same node again (newer kept), a stale one, one from the future, the other faction, a bad version.
reset()
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
local function r(x, y, t, fac, v)
    return ("R:%s:%s:3104:1417:%d:%d:%d"):format(v or "1", fac or "A", x, y, t)
end
LS:OnMessage(r(2530, 3000, now - 600))
LS:OnMessage(r(2540, 3010, now - 60))            -- 25 x 17 yards off: the same node
LS:OnMessage(r(4800, 6050, now - 3700))          -- older than an hour
LS:OnMessage(r(4800, 6050, now + 120))           -- two minutes in the future
LS:OnMessage(r(4800, 6050, now, "H"))
LS:OnMessage(r(4800, 6050, now, "A", "2"))
local held = MapzerothRebuildDB.sightings.A[1417]
check(#held == 1 and held[1].t == now - 60, "one sighting kept, the newer of the two: " .. #held)
check(math.abs(held[1].x - 0.254) < 1e-9, "at the newer position")

-- Step two: the pick goes to the node seen up, not the nearer one that wasn't.
local seen, count = LS:SeenAmong({ "LEYLINE_C1417_253_300", "LEYLINE_C1417_480_605" })
check(count == 1 and seen["LEYLINE_C1417_253_300"] == 60, "SeenAmong finds the sighted node and its age")
local J = addon.Journey
local session = J:Build(makeCtx({ faction = "Alliance" }), { id = "YOU_ley", mapID = 1417, x = 0.47, y = 0.60 })
local pick = { name = "Nearest Ley Line", pick = true, group = "leyline",
               nodeID = "LEYLINE_C1417_253_300", nodeIDs = { "LEYLINE_C1417_253_300", "LEYLINE_C1417_480_605" } }
local plan = J:PlanEntry(session, pick)
check(plan and plan.goal == "LEYLINE_C1417_253_300" and plan.seenAge == 60, "the route goes to the one seen: " .. tostring(plan and plan.goal))
local round = J:PlanRoundTrip(session, pick)
check(round and round.goal == "LEYLINE_C1417_253_300" and round.seenAge == 60, "a round trip too")
LS:ReadGUID("Creature-0-1-2-9999-1-1")
LS:ReadGUID("Creature-0-1-2-9999-2-1")
plan = J:PlanEntry(session, pick)
check(plan.goal == "LEYLINE_C1417_480_605" and plan.seenAge == nil, "in another phase, the nearest of them all")

-- Shared nodes: a sighting where our data has no node is kept as one (whatever the phase), and the pick can go there.
reset()
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
check(#LS:SharedPlaces() == 0, "nothing shared yet")
LS:OnMessage(r(2540, 3010, now - 60))             -- at a node we have: not a shared one
check(#LS:SharedPlaces() == 0, "a sighting at a node in our data adds nothing")
LS:OnMessage(r(4500, 5800, now - 120))            -- 0.45, 0.58: no node of ours there
LS:OnMessage(("R:1:A:7777:1417:%d:%d:%d"):format(4510, 5805, now - 30))   -- the same spot, another phase
local places = LS:SharedPlaces()
check(#places == 1 and places[1].id == "SHARED_A_1417_4500_5800" and places[1].name == "map 1417 Ley Line",
    "an unknown spot is kept once, named like a ley line: " .. tostring(places[1] and places[1].id))
local ids = LS:WithShared(pick.nodeIDs)
check(#ids == 3 and ids[3] == "SHARED_A_1417_4500_5800", "the pick's places and the shared one")
session = J:Build(makeCtx({ faction = "Alliance" }), { id = "YOU_ley2", mapID = 1417, x = 0.47, y = 0.60 }, J:ExtrasOf(pick))
plan = J:PlanEntry(session, pick)
check(plan and plan.goal == "SHARED_A_1417_4500_5800" and plan.seenAge == 120,
    "both seen in this phase: the route goes to the nearer, the shared one: " .. tostring(plan and plan.goal))
check(plan.steps[#plan.steps].text:find("map 1417 Ley Line", 1, true), "and the step names it: " .. plan.steps[#plan.steps].text)
local trip
round, trip = J:PlanRoundTrip(session, pick)
check(round and round.goal == "SHARED_A_1417_4500_5800" and trip.placeChosen, "a round trip chooses it too, and keeps to it: " .. tostring(round) .. " " .. tostring(round and round.goal) .. " " .. tostring(trip and trip.placeChosen))
check(#J:ExtrasOf(trip) == 1, "the chosen trip still carries the shared place, for planning again part way")
-- The next release adds that node to the data: the shared one is dropped.
LS:ResetForTests()
addon.World:GetNode("LEYLINE_C1417_480_605").x, addon.World:GetNode("LEYLINE_C1417_480_605").y = 0.4502, 0.5801
check(#LS:SharedPlaces() == 0 and MapzerothRebuildDB.sharedNodes.A[1417] == nil, "a shared node the data now has is dropped")
addon.World:GetNode("LEYLINE_C1417_480_605").x, addon.World:GetNode("LEYLINE_C1417_480_605").y = 0.48, 0.605

-- Q and S: a Q for a phase we hold is answered after a wait, unless someone else's S comes first.
reset()
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
sent = {}
for i = 1, 10 do LS:OnMessage(r(500 + i * 400, 1000, now - i)) end    -- ten nodes 1000 yards apart
LS:OnMessage("Q:1:A:3104")
runTimers()
check(#sent == 2, "ten sightings answer in two messages: " .. #sent)
local _, entries = sent[1]:match("^S:1:A:3104:(.*)$"):gsub(";", ";")
check(sent[1]:find("^S:1:A:3104:1417,") and entries == 8 and sent[2]:find("^S:1:A:3104:[^;]+$"),
    "nine in the first, one in the second: " .. sent[1])
sent = {}
LS:OnMessage("Q:1:A:3104")
LS:OnMessage("S:1:A:3104:1417,2530,3000," .. (now - 5))
runTimers()
check(#sent == 0, "someone else answered first: we stay quiet")
LS:OnMessage("Q:1:A:5555")
runTimers()
check(#sent == 0, "a phase we hold nothing for isn't answered")
check(#MapzerothRebuildDB.sightings.A[1417] == 11, "the S's entry was kept as a new node")

-- Our own find: before the phase is known it waits, and goes out once it is (in the same zone).
reset()
LS:OnConfirmed(1417, 0.48, 0.605, now - 3)
check(#sent == 0, "no phase yet: nothing sent")
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
check(sent[1] == "R:1:A:3104:1417:4800:6050:" .. (now - 3), "sent once the phase is read, with the cast's time: " .. tostring(sent[1]))
runTimers()
check(sent[2] == "Q:1:A:3104", "then the question")
LS:OnConfirmed(1417, 0.2, 0.2, now)
runTimers()
check(sent[3] == "R:1:A:3104:1417:2000:2000:" .. now, "with the phase known, at once")

-- Throttled: the message waits and goes again.
reset()
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
sent = {}
local refuse = 1
local realSend = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(...)
    if refuse > 0 then refuse = refuse - 1 return 8 end
    return realSend(...)
end
LS:OnConfirmed(1417, 0.3, 0.3, now)
check(#sent == 0, "refused by the channel throttle")
runTimers()
check(#sent == 1 and sent[1]:find("^R:"), "sent after the pause")
C_ChatInfo.SendAddonMessage = realSend

-- With SLLCM loaded, Mapzeroth sends nothing and reads SLLCM's sightings instead.
reset()
loaded.SkyborneLeyLineConvergenceMarker = true
check(not LS:Networking() and LS:SllcmLoaded(), "SLLCM loaded: Mapzeroth stays off the channel")
LS:ReadGUID("Creature-0-1-2-3104-1234-0001")
LS:OnConfirmed(1417, 0.3, 0.3, now)
check(#sent == 0, "and sends nothing")
-- SLLCM 0.3.1 keeps them by faction: only this faction's count.
SkyborneMarkerDB = { crowdReports = {
    A = { [1417] = { { phase = "3104", x = 0.48, y = 0.605, t = now - 300 } } },
    H = { [1417] = { { phase = "3104", x = 0.253, y = 0.30, t = now - 30 } } },
} }
seen, count = LS:SeenAmong({ "LEYLINE_C1417_253_300", "LEYLINE_C1417_480_605" })
check(count == 1 and seen["LEYLINE_C1417_480_605"] == 300, "SLLCM's sightings for this faction are what the pick uses")
SkyborneMarkerDB = { crowdReports = { A = {} } }
check(LS:SeenAmong({ "LEYLINE_C1417_253_300", "LEYLINE_C1417_480_605" }) == nil, "none held for this faction: none seen")
-- 0.3.0: one list for both factions, by map.
SkyborneMarkerDB = { crowdReports = { [1417] = { { phase = "3104", x = 0.48, y = 0.605, t = now - 300 } } } }
seen, count = LS:SeenAmong({ "LEYLINE_C1417_253_300", "LEYLINE_C1417_480_605" })
check(count == 1 and seen["LEYLINE_C1417_480_605"] == 300, "SLLCM 0.3.0's single list is still read")
check(not LS:ShouldAsk(), "and Mapzeroth doesn't ask: SLLCM asks its own question")
MapzerothRebuildDB.sharedNodes = nil
SkyborneMarkerDB = { crowdReports = { A = { [1417] = { { phase = "3104", x = 0.45, y = 0.58, t = now - 30 } } } } }
seen, count = LS:SeenAmong(LS:WithShared({ "LEYLINE_C1417_253_300" }))
check(#LS:SharedPlaces() == 1 and count == 1 and seen["SHARED_A_1417_4500_5800"] == 30,
    "a place only SLLCM's sightings know is learned too, and counts as seen")
loaded.SkyborneLeyLineConvergenceMarker = nil

-- The question is asked once per account, of Skyborne only; either answer settles it.
addon.Options:Set("shareSightings", false)
addon.Options:Set("shareAsked", false)
check(LS:ShouldAsk(), "a Skyborne who was never asked is asked")
UnitRace = function() return "Human", "Human", 1 end
check(not LS:ShouldAsk(), "nobody else is")
UnitRace = function() return "Skyborne", "Skyborne", 99 end
addon.SharePrompt:Answer(false)
check(not LS:ShouldAsk() and not addon.Options:Get("shareSightings"), "Leave Off: asked no more, still off")
