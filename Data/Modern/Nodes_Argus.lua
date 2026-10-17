-- Nodes_Argus.lua (Modern) -- hand-maintained. First converted from the 1.x addon's data (2026-09); edited here since 2026-10-16.
-- Modern's nodes for this part of the world, in containers by uiMapID (`<group>.map<id>`, `.interior` for
-- indoor ones, `_art<N>` for a Zidormi phase side). Flight masters are TAXI_<TaxiNodes id> and instances
-- INSTANCE_<NAME> with their journal id: the client names those. `area = <AreaTable id>` names a node by area.
-- Adding, moving or removing a node changes Geometry.lua: run /mzr dumpgeometry in Retail afterwards.

local addonName, addon = ...
if addon.RULESET ~= "modern" then return end   -- one addon for both games: this data is Modern's (Constants.lua)

addon.Nodes = addon.Nodes or {}

addon.Nodes.Argus = {
    { id = "TAXI_1976", container = "argus_krokuun.map830", mapID = 830, x = 0.6216, y = 0.4901 }, -- Destiny Point
    { id = "TAXI_1928", container = "argus_krokuun.map830", mapID = 830, x = 0.5527, y = 0.6737 }, -- Krokul Hovel
    { id = "TAXI_1944", container = "argus_krokuun.map830", mapID = 830, x = 0.6205, y = 0.8634 }, -- The Vindicaar (Krokuun)
    { id = "TAXI_1967", container = "argus_krokuun.map830", mapID = 830, x = 0.3991, y = 0.6349 }, -- Shattered Fields
    { id = "TAXI_1981", container = "argus_eredath.map882", mapID = 882, x = 0.3003, y = 0.4972 }, -- Shadowguard Incursion
    { id = "TAXI_1982", container = "argus_eredath.map882", mapID = 882, x = 0.5275, y = 0.7568 }, -- Triumvirate's End
    { id = "TAXI_1991", container = "argus_eredath.map882", mapID = 882, x = 0.4368, y = 0.1458 }, -- Prophet's Reflection
    { id = "TAXI_1978", container = "argus_eredath.map882", mapID = 882, x = 0.6287, y = 0.3983 }, -- Conservatory of the Arcane
    { id = "INSTANCE_SEAT_OF_THE_TRIUMVIRATE", container = "argus_eredath.map882", mapID = 882, x = 0.2100, y = 0.5700, kind = "instance", journal = 945 }, -- Seat of the Triumvirate
    { id = "TAXI_1977", container = "argus_eredath.map882", mapID = 882, x = 0.5157, y = 0.8609 }, -- The Vindicaar (Eredath)
    { id = "TAXI_2003", container = "argus_eredath.map882", mapID = 882, x = 0.4698, y = 0.5572 }, -- City Center
    { id = "VINDICAAR_ARGUS", container = "argus_vindicaar.map883", mapID = 883, x = 0.5826, y = 0.8101, area = 8915 }, -- The Vindicaar (Argus)
    { id = "INSTANCE_ANTORUS_THE_BURNING_THRONE", container = "argus_antoran_wastes.map885", mapID = 885, x = 0.5500, y = 0.6200, kind = "instance", journal = 946 }, -- Antorus, the Burning Throne
    { id = "TAXI_1994", container = "argus_antoran_wastes.map885", mapID = 885, x = 0.7547, y = 0.3690 }, -- The Vindicaar (Antoran Wastes)
    { id = "TAXI_1988", container = "argus_antoran_wastes.map885", mapID = 885, x = 0.7276, y = 0.5067 }, -- Hope's Landing
    { id = "TAXI_1993", container = "argus_antoran_wastes.map885", mapID = 885, x = 0.7040, y = 0.2542 }, -- The Veiled Den
}
