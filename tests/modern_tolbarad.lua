-- Tol Barad is no-fly on both maps: from the Peninsula's camp, Baradin Hold is reached on the ground over the crossing
-- onto the island (BORDER_TOL_BARAD_*), never by flying.
-- Run: python tests/harness.py --modern modern_tolbarad

useRetailDistances()
addon.World:Build()
addon.GetNodeName = function(_, id) return id end

local J = addon.Journey
local camp = addon.World:GetNode("TOL_BARAD_HORDE")
local start = { id = "START_TB", mapID = camp.mapID, x = camp.x, y = camp.y }
local plan = J:Plan(J:Build(makeCtx({ faction = "Horde" }), start), "INSTANCE_BARADIN_HOLD")
check(plan ~= nil, "Baradin Hold can be reached from the Horde camp")
local methods, crossed = {}, false
for _, step in ipairs(plan.steps) do
    methods[#methods + 1] = step.method .. ":" .. tostring(step.nodeID or step.to)
    check(step.method ~= "fly", "no flying in Tol Barad: " .. table.concat(methods, " "))
    if step.nodeID == "BORDER_TOL_BARAD_PENINSULA_ISLAND" then crossed = true end   -- the island side is merged into the last walk
end
check(crossed, "the route crosses onto the island: " .. table.concat(methods, " "))
print("Horde camp -> Baradin Hold via " .. table.concat(methods, " "))
