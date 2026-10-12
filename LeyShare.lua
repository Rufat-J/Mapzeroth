local addonName, addon = ...

-- Ley line and elemental convergence sightings, shared with Skyborne Ley Line & Convergence Marker (SLLCM, the
-- player's other addon) on its hidden channel. When a Skyborne character's racial confirms a node, where it is and
-- the phase (shard) the player is in go out to everyone on the channel; what others send is kept for an hour, and
-- the "Nearest Ley Line" / "Nearest Elemental Convergence" picks go to a node seen in the player's phase when there
-- is one (Journey:PlanEntry asks SeenAmong).
--
-- SLLCM's Comm.lua is the reference; both addons must stay wire-compatible (protocol version "1"):
--   R:1:fac:phase:mapID:x:y:t          one sighting (x, y = map position x 10000, 0-9999; t = GetServerTime())
--   Q:1:fac:phase                      "what do you have for this phase?"
--   S:1:fac:phase:mapID,x,y,t;...      reply to Q, at most MAX_PER_REPLY entries a message
-- fac is A or H; phase is the zoneUID of creature GUIDs (digits).
--
-- Rules: off until the player says yes (Options "shareSightings", asked once per account by UI/SharePrompt.lua);
-- Skyborne characters only; and when SLLCM itself is loaded, Mapzeroth sends nothing and joins nothing, reading
-- SLLCM's sightings instead (its SavedVariables table, live), so no sighting goes out twice. Nothing here prints.

local LeyShare = {}
addon.LeyShare = LeyShare

local PREFIX = "SLLCM"
local CHANNEL_BASE = "SLLCMShare"    -- + A / H
local VERSION = "1"
local TTL = 60 * 60                  -- a sighting is dropped this many seconds after it was made
local FUTURE = 60                    -- a sighting stamped further ahead than this is refused
local SAME_YARDS = 60                -- two sightings closer than this (same phase, same map) are the same node
local REPLY_MINE = { 1, 3 }          -- seconds to wait before answering a Q, holding a sighting of our own for its phase
local REPLY_OTHERS = { 4, 12 }       -- and holding only others' (so the one who saw it usually answers first)
local MAX_PER_REPLY = 9              -- entries per S message, keeps it under 255 bytes
-- Forever's channel allowance is about 10 at once, then ~0.8 a second, and retrying while refused keeps it refusing.
local SEND_GAP = 1.25
local THROTTLE_PAUSE = 5
local CONFIRMATIONS = 2              -- NPC kinds agreeing before a confirmed phase is replaced
local SCAN_SECONDS = 60              -- re-read nameplates this often (the shard can change while standing still)
local RESTORE_SECONDS = 300          -- a phase saved at logout or /reload is picked up again only this soon after
local REJOIN_SECONDS = 60
local SETTLE_SECONDS, SETTLE_MAX = 3, 30
-- The racials, and the buff each gives: 15 minutes standing on a node, 15-30 s anywhere else.
local RACIALS = { [1259705] = true, [1259686] = true }   -- Read Ley Line (Alliance), Skysight (Horde)
local BUFFS = { 1259691, 1270893 }                        -- Energized (Alliance), Elemental Blessing (Horde)
local MIN_BUFF = 60
local CHECK_TRIES, CHECK_GAP = 4, 0.5

local phase              -- the current phase (zoneUID as a string), nil until learned
local phaseMap           -- the map it was read on
local tentativeNpc       -- read from one NPC kind only: any other reading replaces it
local candidates = {}    -- candidates[phase] = { [npcID] = true, n = count }
local waiting            -- an own sighting made before the phase was known
local pending            -- a racial whose buff couldn't be read (combat): checked when combat ends
local asked = {}         -- asked[phase] = true: our own Q for it has gone out (once a session)
local joinedAt           -- GetTime() of first joining the channel this session: no Q after TTL seconds on it
local answering = {}     -- answering[phase] = a token while an answer to a Q for it waits (an S for it cancels)
local queue, sending = {}, false
local me = {}            -- our own name as senders show it (the server echoes our messages back)
local nodeMaps           -- mapID -> true where our faction has nodes (built once)
local worldCache = {}    -- node id -> { x, y, continent }
local joinStarted, scanning

-- nil for a secret value (encounters, combat) or a failed read.
local function clean(v)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function isLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return fn and fn(name) and true or false
end

-- SLLCM does the sharing itself when it is loaded.
function LeyShare:SllcmLoaded()
    for _, folder in ipairs(addon.SLLCM_FOLDERS) do
        if isLoaded(folder) then return true end
    end
    return false
end

local function skyborne()
    return addon.LeyLineSpell ~= nil and UnitRace ~= nil and select(2, UnitRace("player")) == "Skyborne"
end

local function factionTag()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

local function channelName()
    return CHANNEL_BASE .. factionTag()
end

-- Whether this character joins the channel, sends and receives.
function LeyShare:Networking()
    return addon.Options:Get("shareSightings") and skyborne() and not self:SllcmLoaded()
end

-- Whether sightings mean anything here: a Skyborne, sharing through us or through SLLCM.
local function tracking()
    return skyborne() and (LeyShare:Networking() or LeyShare:SllcmLoaded())
end

local function playerMap()
    return C_Map.GetBestMapForUnit("player")
end

---------------------------------------------------------------------------
-- Storage: MapzerothRebuildDB.sightings[fac][mapID] = { { phase, x, y, t }, ... } (x, y 0-1). By faction, so
-- an Alliance alt's ley lines are never offered to Horde players. With SLLCM loaded its own table is read instead.
---------------------------------------------------------------------------

local function ownReports()
    MapzerothRebuildDB = MapzerothRebuildDB or {}
    local all = MapzerothRebuildDB.sightings
    if type(all) ~= "table" then
        all = {}
        MapzerothRebuildDB.sightings = all
    end
    local tag = factionTag()
    all[tag] = type(all[tag]) == "table" and all[tag] or {}
    return all[tag]
end

-- SLLCM 0.3.1 keeps them the same way, db.crowdReports[fac][mapID]; 0.3.0 had one list for both factions,
-- crowdReports[mapID], which is still read for anyone on that version (the node match keeps the factions apart).
local function reports()
    if LeyShare:SllcmLoaded() then
        local db = SkyborneMarkerDB
        local all = type(db) == "table" and type(db.crowdReports) == "table" and db.crowdReports or {}
        if all.A ~= nil or all.H ~= nil then return type(all[factionTag()]) == "table" and all[factionTag()] or {} end
        return all
    end
    return ownReports()
end

local function prune(list)
    local now = GetServerTime()
    for i = #list, 1, -1 do
        if now - list[i].t > TTL then table.remove(list, i) end
    end
end

-- Drop expired sightings, maps left empty, and the whole table once nothing is held (keeps the saved file small).
local function pruneAll()
    local all = MapzerothRebuildDB and MapzerothRebuildDB.sightings
    if type(all) ~= "table" then return end
    for _, byMap in pairs(all) do
        for mapID, list in pairs(byMap) do
            prune(list)
            if #list == 0 then byMap[mapID] = nil end
        end
    end
    for tag, byMap in pairs(all) do
        if next(byMap) == nil then all[tag] = nil end
    end
    if next(all) == nil then MapzerothRebuildDB.sightings = nil end
end

local function worldPos(mapID, x, y)
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not pos then return nil end
    local wx, wy = pos:GetXY()
    return wx, wy, continent
end

local function yardsApart(ax, ay, ac, bx, by, bc)
    if not (ax and bx) or ac ~= bc then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function near(mapID, x1, y1, x2, y2)
    local ax, ay, ac = worldPos(mapID, x1, y1)
    local bx, by, bc = worldPos(mapID, x2, y2)
    local d = yardsApart(ax, ay, ac, bx, by, bc)
    return d ~= nil and d < SAME_YARDS
end

---------------------------------------------------------------------------
-- Shared nodes: places a sighting confirmed that our data doesn't have yet (a node found since the last release).
-- MapzerothRebuildDB.sharedNodes[fac][mapID] = { { x, y }, ... }, kept whatever the phase, as SLLCM keeps its own.
-- Each is a place the nearest-node pick can go to (SharedPlaces, Journey). One that a release has since added to the
-- data is dropped (pruneShared), so nothing is held twice.
---------------------------------------------------------------------------

local known              -- world positions of our faction's nodes in the data: { { x, y, continent }, ... }
local sharedPruned       -- shared nodes checked against the data this session
local placesCache        -- SharedPlaces' list, until a node is learned

local function nodeKind()
    return factionTag() == "H" and "convergence" or "leyline"
end

local function knownWorld()
    if known then return known end
    local list, kind = {}, nodeKind()
    addon.World:ForEachNode(function(node)
        if node.kind == kind and node.mapID then
            local x, y, c = worldPos(node.mapID, node.x, node.y)
            if x then list[#list + 1] = { x, y, c } end
        end
    end)
    if #list > 0 then known = list end      -- an empty list: the world isn't built yet, so look again next time
    return list
end

local function nearAny(list, x, y, c)
    for _, p in ipairs(list) do
        local d = yardsApart(x, y, c, p[1], p[2], p[3])
        if d and d < SAME_YARDS then return true end
    end
    return false
end

local function sharedStore()
    MapzerothRebuildDB = MapzerothRebuildDB or {}
    local all = MapzerothRebuildDB.sharedNodes
    if type(all) ~= "table" then
        all = {}
        MapzerothRebuildDB.sharedNodes = all
    end
    local tag = factionTag()
    all[tag] = type(all[tag]) == "table" and all[tag] or {}
    return all[tag]
end

-- Drop shared nodes the data now has (once a session, when the data is there to compare with).
local function pruneShared()
    if sharedPruned then return end
    local list = knownWorld()
    if #list == 0 then return end
    sharedPruned = true
    local all = MapzerothRebuildDB and MapzerothRebuildDB.sharedNodes
    if type(all) ~= "table" then return end
    local byMap = all[factionTag()]
    if type(byMap) ~= "table" then return end
    for mapID, nodes in pairs(byMap) do
        for i = #nodes, 1, -1 do
            local x, y, c = worldPos(mapID, nodes[i][1], nodes[i][2])
            if x and nearAny(list, x, y, c) then table.remove(nodes, i) end
        end
        if #nodes == 0 then byMap[mapID] = nil end
    end
    placesCache = nil
end

-- A sighting's place, kept as a shared node unless the data or the shared list has it already.
local function learn(mapID, x, y)
    local wx, wy, wc = worldPos(mapID, x, y)
    if not wx or nearAny(knownWorld(), wx, wy, wc) then return end
    local byMap = sharedStore()
    local nodes = byMap[mapID] or {}
    for _, n in ipairs(nodes) do
        if near(mapID, n[1], n[2], x, y) then return end
    end
    nodes[#nodes + 1] = { x, y }
    byMap[mapID] = nodes
    placesCache = nil
end

-- The shared nodes as places to go: { id, mapID, x, y, name, leave }, ids stable for the same spot.
function LeyShare:SharedPlaces()
    if not skyborne() then return {} end
    pruneShared()
    -- SLLCM's sightings never pass through add(): the places they found are learned here.
    if self:SllcmLoaded() then
        for mapID, list in pairs(reports()) do
            for _, r in ipairs(list) do
                if type(r.x) == "number" and type(r.y) == "number" then learn(mapID, r.x, r.y) end
            end
        end
    end
    if placesCache then return placesCache end
    local places, tag = {}, factionTag()
    local all = MapzerothRebuildDB and MapzerothRebuildDB.sharedNodes
    local kindKey = nodeKind() == "convergence" and "NODE_KIND_CONVERGENCE" or "NODE_KIND_LEYLINE"
    for mapID, nodes in pairs(type(all) == "table" and type(all[tag]) == "table" and all[tag] or {}) do
        for _, n in ipairs(nodes) do
            places[#places + 1] = {
                id = ("SHARED_%s_%d_%d_%d"):format(tag, mapID, math.floor(n[1] * 10000 + 0.5), math.floor(n[2] * 10000 + 0.5)),
                mapID = mapID, x = n[1], y = n[2],
                leave = true,          -- somewhere to leave as well as reach (Journey:Build), for a round trip's way back
                name = addon.L[kindKey]:format(addon:GetZoneName(mapID) or ""),
            }
        end
    end
    table.sort(places, function(a, b) return a.id < b.id end)
    placesCache = places
    return places
end

-- A pick's node ids and the shared nodes' together.
function LeyShare:WithShared(nodeIDs)
    local ids = {}
    for _, id in ipairs(nodeIDs) do ids[#ids + 1] = id end
    for _, place in ipairs(self:SharedPlaces()) do ids[#ids + 1] = place.id end
    return ids
end

-- Keep a sighting (ours or someone else's). Returns true when it was kept.
local function add(p, mapID, x, y, t, mine)
    local now = GetServerTime()
    if not (C_Map.GetMapInfo(mapID) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return false end
    if t > now + FUTURE or now - t > TTL then return false end
    learn(mapID, x, y)
    local all = ownReports()
    local list = all[mapID] or {}
    all[mapID] = list
    prune(list)
    for _, e in ipairs(list) do
        if e.phase == p and near(mapID, e.x, e.y, x, y) then
            if t > e.t then e.x, e.y, e.t = x, y, t end
            if mine then e.mine = true end
            return true
        end
    end
    list[#list + 1] = { phase = p, x = x, y = y, t = t, mine = mine or nil }
    return true
end

-- Only zones with nodes of ours (or a sighting of one) are worth asking about: the channel holds the whole faction.
local function hasNodes(mapID)
    if not mapID then return false end
    if not nodeMaps then
        nodeMaps = {}
        local kind = factionTag() == "H" and "convergence" or "leyline"
        addon.World:ForEachNode(function(node)
            if node.kind == kind and node.mapID then nodeMaps[node.mapID] = true end
        end)
    end
    local list = ownReports()[mapID]
    return nodeMaps[mapID] or (list ~= nil and #list > 0)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function channelIndex()
    local id = GetChannelName(channelName())
    return type(id) == "number" and id > 0 and id or nil
end

local function drain()
    local msg, id = queue[1], channelIndex()
    if not msg or not id or not LeyShare:Networking() then
        sending = false
        return
    end
    local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", id)
    -- Older clients return a boolean, newer ones Enum.SendAddonMessageResult (0 = success).
    if ok and (r == nil or r == true or r == 0) then
        table.remove(queue, 1)
        C_Timer.After(SEND_GAP, drain)
    elseif ok and (r == 3 or r == 8) then          -- AddonMessageThrottle, ChannelThrottle: wait it out
        C_Timer.After(THROTTLE_PAUSE, drain)
    else
        table.remove(queue, 1)
        C_Timer.After(SEND_GAP, drain)
    end
end

local function send(msg)
    if not LeyShare:Networking() then return end
    queue[#queue + 1] = msg
    if not sending then
        sending = true
        drain()
    end
end

local function coord(v)
    return math.floor(v * 10000 + 0.5)
end

-- Ask once a session per phase, and only in the first hour on the channel: every R and S reaches every client
-- whatever its phase, so after that there is nothing from before we joined left to ask for.
local function query()
    if not joinedAt and channelIndex() then joinedAt = GetTime() end
    if not phase or not hasNodes(phaseMap) or asked[phase] then return end
    if not joinedAt or GetTime() - joinedAt > TTL then return end
    asked[phase] = true
    send(("Q:%s:%s:%s"):format(VERSION, factionTag(), phase))
end

local function broadcast(mapID, x, y, t)
    add(phase, mapID, x, y, t, true)
    send(("R:%s:%s:%s:%d:%d:%d:%d"):format(VERSION, factionTag(), phase, mapID, coord(x), coord(y), t))
end

-- An own sighting, position and server time taken at the cast.
function LeyShare:OnConfirmed(mapID, x, y, t)
    if not (skyborne() and self:Networking()) then return end
    if phase then
        broadcast(mapID, x, y, t)
    else
        waiting = { mapID = mapID, x = x, y = y, t = t }
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function sendReply(p)
    local entries = {}
    for mapID, list in pairs(ownReports()) do
        prune(list)
        for _, r in ipairs(list) do
            if r.phase == p then
                entries[#entries + 1] = ("%d,%d,%d,%d"):format(mapID, coord(r.x), coord(r.y), r.t)
            end
        end
    end
    for i = 1, #entries, MAX_PER_REPLY do
        send(("S:%s:%s:%s:%s"):format(VERSION, factionTag(), p,
            table.concat(entries, ";", i, math.min(i + MAX_PER_REPLY - 1, #entries))))
    end
end

local function addFields(p, mapID, x, y, t)
    mapID, x, y, t = tonumber(mapID), tonumber(x), tonumber(y), tonumber(t)
    if mapID and x and y and t then add(p, mapID, x / 10000, y / 10000, t) end
end

-- One message from the channel (sender already known not to be us).
function LeyShare:OnMessage(text)
    local kind, v, fac, p, rest = strsplit(":", text, 5)
    if v ~= VERSION or fac ~= factionTag() or not (p and p:match("^%d+$")) then return end
    if kind == "R" and rest then
        addFields(p, strsplit(":", rest))
    elseif kind == "Q" then
        -- Answer after a random wait, unless someone else answers first: a short one when we saw a node there
        -- ourselves, a longer one when we only heard of it. One wait per phase.
        if answering[p] then return end
        local held, mine = false, false
        for _, list in pairs(ownReports()) do
            for _, r in ipairs(list) do
                if r.phase == p and GetServerTime() - r.t <= TTL then
                    held = true
                    if r.mine then mine = true end
                end
            end
        end
        if not held then return end
        local wait = mine and REPLY_MINE or REPLY_OTHERS
        local token = {}
        answering[p] = token
        C_Timer.After(wait[1] + math.random() * (wait[2] - wait[1]), function()
            if answering[p] ~= token then return end        -- someone else answered (and maybe a new Q came since)
            answering[p] = nil
            sendReply(p)
        end)
    elseif kind == "S" and rest then
        answering[p] = nil
        for entry in rest:gmatch("[^;]+") do addFields(p, strsplit(",", entry)) end
    end
end

---------------------------------------------------------------------------
-- Phase. Creature GUIDs are Creature-0-server-instance-zoneUID-npcID-spawnUID; zoneUID is the shard, the same for
-- everyone in it. The first reading is used straight away; once a second kind of NPC agrees, replacing it takes
-- CONFIRMATIONS kinds of NPC agreeing on a new one.
---------------------------------------------------------------------------

local function setPhase(p, npcID)
    local old = phase
    phase, phaseMap, tentativeNpc = p, playerMap(), npcID
    wipe(candidates)
    if p == old then return end
    if waiting and waiting.mapID == phaseMap then broadcast(waiting.mapID, waiting.x, waiting.y, waiting.t) end
    waiting = nil
    query()
end

-- A GUID seen on a unit. Exposed for tests.
function LeyShare:ReadGUID(guid)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, zone, npc = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    zone, npc = tonumber(zone), tonumber(npc)
    if not zone or zone <= 0 or not npc then return end
    local p = tostring(zone)
    if p == phase then
        if tentativeNpc and npc ~= tentativeNpc then tentativeNpc = nil end    -- another kind agrees
        wipe(candidates)
    elseif not phase or tentativeNpc then
        setPhase(p, npc)
    else
        local c = candidates[p] or { n = 0 }
        candidates[p] = c
        if not c[npc] then c[npc], c.n = true, c.n + 1 end
        if c.n >= CONFIRMATIONS then setPhase(p) end
    end
end

local function readUnit(unit)
    if not tracking() then return end
    local ok, guid = pcall(UnitGUID, unit)
    LeyShare:ReadGUID(ok and clean(guid) or nil)
end

local function scanNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if clean(UnitExists(unit)) then readUnit(unit) end
    end
end

-- The phase, whether it is still tentative, and the map it was read on (for tests and the dev tools).
function LeyShare:Phase()
    return phase, tentativeNpc ~= nil, phaseMap
end

-- Only a real zone change forgets the phase: the events that call this also fire on /reload and at login.
function LeyShare:OnZone()
    if playerMap() ~= phaseMap then
        phase, phaseMap, tentativeNpc, waiting = nil, nil, nil, nil
        wipe(candidates)
    end
    -- After a /reload or a quick relog in the same zone, the saved phase is picked up again, tentatively.
    local db = MapzerothRebuildDB
    local saved = db and db.sightingPhase
    if db then db.sightingPhase = nil end
    if not phase and type(saved) == "table" and saved.mapID == playerMap()
            and GetServerTime() - (saved.at or 0) <= RESTORE_SECONDS then
        phase, phaseMap, tentativeNpc = saved.phase, saved.mapID, -1
    end
end

---------------------------------------------------------------------------
-- Detecting a confirmed node: the racial's buff lasts a minute or more only when cast on one.
---------------------------------------------------------------------------

local function hasNodeBuff(since)
    for _, id in ipairs(BUFFS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
        if aura and aura.duration >= MIN_BUFF and aura.expirationTime - aura.duration >= since then return true end
    end
    return false
end

function LeyShare:OnRacialCast()
    if not self:Networking() then return end
    local mapID = playerMap()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    local castTime, serverTime, tries = GetTime() - 1, GetServerTime(), 0
    local function check()
        tries = tries + 1
        local ok, found = pcall(hasNodeBuff, castTime)
        if ok and found then
            LeyShare:OnConfirmed(mapID, x, y, serverTime)
        elseif ok and tries < CHECK_TRIES and not InCombatLockdown() then
            C_Timer.After(CHECK_GAP, check)
        elseif not ok or InCombatLockdown() then
            -- Auras are secret in combat: look again when it ends.
            pending = { mapID = mapID, x = x, y = y, castTime = castTime, serverTime = serverTime }
        end
    end
    C_Timer.After(0.2, check)
end

local function checkPending()
    local p = pending
    pending = nil
    if not p then return end
    local ok, found = pcall(hasNodeBuff, p.castTime)
    if ok and found then
        LeyShare:OnConfirmed(p.mapID, p.x, p.y, p.serverTime)
    elseif not ok then
        pending = p
    end
end

---------------------------------------------------------------------------
-- Routing (step two): which of a pick's nodes were seen in the player's phase.
---------------------------------------------------------------------------

local function nodeWorld(node)
    local cached = worldCache[node.id]
    if cached == nil then
        local x, y, c = worldPos(node.mapID, node.x, node.y)
        cached = x and { x, y, c } or false
        worldCache[node.id] = cached
    end
    return cached or nil
end

-- { [nodeID] = seconds since it was last seen } for those of `nodeIDs` with a sighting in the player's current phase
-- in the last hour, and how many; nil when there are none (or the phase isn't known).
-- nodeIDs may name shared nodes (WithShared).
function LeyShare:SeenAmong(nodeIDs)
    if not (phase and tracking()) then return nil end
    local shared = {}
    for _, place in ipairs(self:SharedPlaces()) do shared[place.id] = place end
    local now, seen, count = GetServerTime(), {}, 0
    for mapID, list in pairs(reports()) do
        for _, r in ipairs(list) do
            local age = now - (r.t or 0)
            if r.phase == phase and age <= TTL and age >= -FUTURE then
                local rx, ry, rc = worldPos(mapID, r.x, r.y)
                for _, id in ipairs(nodeIDs) do
                    local node = addon.World:GetNode(id) or shared[id]
                    local w = node and node.mapID and nodeWorld(node)
                    local d = w and yardsApart(rx, ry, rc, w[1], w[2], w[3])
                    if d and d < SAME_YARDS and (seen[id] == nil or age < seen[id]) then
                        if seen[id] == nil then count = count + 1 end
                        seen[id] = math.max(0, age)
                    end
                end
            end
        end
    end
    if count == 0 then return nil end
    return seen, count
end

---------------------------------------------------------------------------
-- Channel
---------------------------------------------------------------------------

local function hideFromChat()
    local name = channelName()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.RemoveChannel then
            pcall(frame.RemoveChannel, frame, name)
        elseif frame and ChatFrame_RemoveChannel then
            pcall(ChatFrame_RemoveChannel, frame, name)
        end
    end
end

local function join()
    if not joinedAt and channelIndex() then joinedAt = GetTime() end      -- on it since about now (joining takes a moment)
    if not LeyShare:Networking() or channelIndex() or clean(IsInInstance()) then return end
    pcall(JoinTemporaryChannel, channelName())
    -- The chat frames pick the channel up a moment after joining.
    C_Timer.After(1, hideFromChat)
    C_Timer.After(5, hideFromChat)
    C_Timer.After(2, query)
end

-- Start once, the first time sharing is on for a Skyborne. At login the game's own channels (General, Trade...) come
-- in first: a new channel takes the lowest free number, and taking /1 would send a player's "/1 hello" into ours.
local function start(atLogin)
    if not LeyShare:Networking() then return end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    if joinStarted then
        join()
        return
    end
    joinStarted = true
    local function begin()
        join()
        C_Timer.NewTicker(REJOIN_SECONDS, join)        -- rejoin if kicked, /left, or lost to a client hiccup
    end
    if not atLogin then
        begin()
        return
    end
    local started, changedAt, last = GetTime(), GetTime(), -1
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        local now, count = GetTime(), select("#", GetChannelList())
        if count ~= last then last, changedAt = count, now end
        if now - changedAt >= SETTLE_SECONDS or now - started >= SETTLE_MAX then
            ticker:Cancel()
            begin()
        end
    end)
end

local function startScanning()
    if scanning or not tracking() then return end
    scanning = true
    C_Timer.NewTicker(SCAN_SECONDS, function()
        if tracking() then scanNameplates() end
    end)
end

-- The player turned sharing on or off (the settings page or the first-run question).
function LeyShare:OnSettingChanged(on)
    addon.Options:Store("shareAsked", true)
    if on then
        start(false)
        startScanning()
    else
        wipe(queue)
        if channelIndex() then pcall(LeaveChannelByName, channelName()) end
    end
end

-- Whether to ask the player (once per account): a Skyborne, never asked, and SLLCM not doing it already.
function LeyShare:ShouldAsk()
    return skyborne() and not addon.Options:Get("shareAsked") and not self:SllcmLoaded()
end

-- How much is held, for the dev tools: sightings, how many in the current phase, messages waiting to go, shared nodes.
function LeyShare:Stats()
    local count, here = 0, 0
    for _, list in pairs(reports()) do
        for _, r in ipairs(list) do
            count = count + 1
            if r.phase == phase then here = here + 1 end
        end
    end
    return { networking = self:Networking(), sllcm = self:SllcmLoaded(), channel = channelIndex(), phase = phase,
             tentative = tentativeNpc ~= nil, held = count, here = here, queued = #queue,
             shared = #self:SharedPlaces() }
end

-- Tests only: forget everything held in memory.
function LeyShare:ResetForTests()
    phase, phaseMap, tentativeNpc, waiting, pending, joinedAt, nodeMaps = nil, nil, nil, nil, nil, nil, nil
    wipe(candidates)
    wipe(asked)
    wipe(answering)
    wipe(queue)
    wipe(worldCache)
    sending = false
    known, sharedPruned, placesCache = nil, nil, nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        if not LeyShare:Networking() then return end
        local prefix, text, _, sender = ...
        prefix, text, sender = clean(prefix), clean(text), clean(sender)
        if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
        sender = Ambiguate(sender, "none")
        if not me[sender] then LeyShare:OnMessage(text) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        readUnit((...))
    elseif event == "PLAYER_TARGET_CHANGED" then
        readUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        readUnit("mouseover")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if RACIALS[spellID] then LeyShare:OnRacialCast() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        checkPending()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        LeyShare:OnZone()
    elseif event == "PLAYER_LOGIN" then
        pruneAll()
        -- On Forever, UnitName gives first name and surname apart, and senders show as "First Surname".
        local name, surname = UnitName("player")
        if name then me[name] = true end
        if name and surname and surname ~= "" then me[name .. " " .. surname] = true end
        addon.Options:OnChange(function(key, value)
            if key == "shareSightings" then LeyShare:OnSettingChanged(value) end
        end)
        start(true)
        startScanning()
    elseif event == "PLAYER_LOGOUT" then                -- also /reload
        pruneAll()
        if MapzerothRebuildDB then
            MapzerothRebuildDB.sightingPhase = phase and { phase = phase, mapID = phaseMap, at = GetServerTime() } or nil
        end
    end
end)
