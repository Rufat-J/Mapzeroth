local addonName, addon = ...
-- AzerothGPS recorded walking paths. A path is user-verified; no terrain geometry is guessed.
local Roads = {}
addon.Roads = Roads
local function db()
    MapzerothRebuildDB = MapzerothRebuildDB or {}
    MapzerothRebuildDB.azerothRoads = MapzerothRebuildDB.azerothRoads or {}
    return MapzerothRebuildDB.azerothRoads
end
local function position()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return { mapID = map, x = x, y = y }
end
local function say(msg) print("AzerothGPS Roads: " .. msg) end
function Roads:Add(name)
    name = name and name:lower()
    if not name or name == "" then say("Usage: /agps road add RouteName"); return end
    local p = position()
    if not p then say("Position unavailable here."); return end
    local routes = db()
    local route = routes[name]
    if route and route.mapID ~= p.mapID then say("This route belongs to another map."); return end
    if not route then route = { mapID = p.mapID, points = {} }; routes[name] = route end
    route.points[#route.points + 1] = { mapID = p.mapID, x = p.x, y = p.y }
    say(("%s: waypoint %d saved (%.1f, %.1f)."):format(name, #route.points, p.x * 100, p.y * 100))
end
function Roads:Start(name)
    name = name and name:lower()
    local route = name and db()[name]
    if not route or #route.points == 0 then say("Route not found. Use /agps road add RouteName."); return end
    local p = position()
    if not p or p.mapID ~= route.mapID then say("You must be on the route's map."); return end
    self.active = { name = name, route = route, index = 1 }
    say("Following " .. name .. " (" .. #route.points .. " waypoints). Start normal destination navigation too.")
end
function Roads:Stop()
    self.active = nil
    say("Road guidance stopped.")
end
function Roads:Clear(name)
    name = name and name:lower()
    if not name or not db()[name] then say("Route not found."); return end
    if self.active and self.active.name == name then self.active = nil end
    db()[name] = nil
    say("Deleted route " .. name)
end
function Roads:List()
    local any = false
    for name, route in pairs(db()) do
        say(name .. " (" .. #route.points .. " waypoints)")
        any = true
    end
    if not any then say("No recorded roads yet.") end
end
function Roads:Target(sample, distanceProvider)
    local active = self.active
    if not active or not sample or sample.mapID ~= active.route.mapID then return nil end
    local points = active.route.points
    while active.index <= #points do
        local target = points[active.index]
        local d = distanceProvider(sample, target)
        if not d then return nil end
        if d > 25 then return target, d end
        active.index = active.index + 1
    end
    self.active = nil
    say("Last road waypoint reached; resuming normal GPS guidance.")
    return nil
end
function Roads:Command(rest)
    local cmd, name = (rest or ""):match("^(%S+)%s*(%S*)")
    if cmd == "add" then self:Add(name)
    elseif cmd == "start" then self:Start(name)
    elseif cmd == "stop" then self:Stop()
    elseif cmd == "clear" then self:Clear(name)
    elseif cmd == "list" then self:List()
    else say("Commands: /agps road add|start|clear RouteName, /agps road list|stop") end
end
