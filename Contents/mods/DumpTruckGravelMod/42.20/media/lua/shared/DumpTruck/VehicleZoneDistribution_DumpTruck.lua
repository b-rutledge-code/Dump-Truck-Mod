--[[
    DumpTruckGravelMod - Vehicle Zone Distribution
    
    This file adds the dump truck to various vehicle spawn zones in the game.
    Uses OnGameBoot event so VehicleZoneDistribution exists when we modify it.
    
    Zone names verified against reference/general/vehicle-zone-distribution.md
    and game VehicleType (zoneName lowercased in getRandomVehicleType).
    
    Spawn Rates:
    - Trades: 20% (construction and trade areas)
    - McCoy Logging: 20% (industrial / logging — build the road out)
    - Farm: 7% (agricultural areas)
    - Junkyard: 5% (scrapyards and junkyards)
    - Carpenter: 8% (woodworking / heavy equipment)
    - Delivery: 5% (delivery areas — bulk materials)
    - Traffic Jam (w/e/n/s): 4% each (roadblocks, traffic)
    - Parking Stalls: 1% (general parking lots)
    - Medium Areas: 1% (medium density zones)
]]

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local OPTION_ADMIN_ONLY = "DumpTruckGravelMod.AdminOnly"

local function initVehicleZoneDistribution()
    if not VehicleZoneDistribution then
        return
    end

    -- Sandbox option: when Admin only is on, do not add dump truck to spawn tables
    local sandbox = getSandboxOptions()
    if sandbox then
        local opt = sandbox:getOptionByName(OPTION_ADMIN_ONLY)
        if opt and opt:getValue() then
            return
        end
    end

    local VEHICLE_NAME = DumpTruckConstants.VEHICLE_SCRIPT_NAME
    
    -- Helper to add vehicle to zone
    local function addToZone(zoneName, spawnChance)
        VehicleZoneDistribution[zoneName] = VehicleZoneDistribution[zoneName] or {}
        VehicleZoneDistribution[zoneName].vehicles = VehicleZoneDistribution[zoneName].vehicles or {}
        VehicleZoneDistribution[zoneName].vehicles[VEHICLE_NAME] = {index = -1, spawnChance = spawnChance}
    end
    
    -- Add dump trucks to zones (thematic: construction, logging, farm, industrial, delivery, traffic)
    addToZone("trades", 20)       -- Construction sites
    addToZone("mccoy", 20)        -- McCoy Logging (build the road out)
    addToZone("carpenter", 8)    -- Woodworking / heavy equipment
    addToZone("farm", 7)         -- Agricultural areas
    addToZone("junkyard", 5)     -- Scrapyards
    addToZone("delivery", 5)     -- Delivery (bulk materials)
    addToZone("trafficjamw", 4)  -- Traffic jam (west)
    addToZone("trafficjame", 4)  -- Traffic jam (east)
    addToZone("trafficjamn", 4)  -- Traffic jam (north)
    addToZone("trafficjams", 4)  -- Traffic jam (south)
    addToZone("parkingstall", 1) -- General parking lots
    addToZone("medium", 1)       -- Medium density zones
end

-- Hook into OnGameBoot - fires after VehicleZoneDistribution is created
Events.OnGameBoot.Add(initVehicleZoneDistribution)
