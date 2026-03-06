--[[
    DumpTruckGravelMod - Vehicle Zone Distribution
    
    This file adds the dump truck to various vehicle spawn zones in the game.
    Uses OnGameBoot event so VehicleZoneDistribution exists when we modify it.
    
    Spawn Rates:
    - McCoy Logging: 10% (industrial area)
    - Parking Stalls: 1% (general parking lots)
    - Medium Areas: 1% (medium density zones)
    - Junkyards: 5% (scrapyards and junkyards)
    - Farms: 7% (agricultural areas)
    - Trades: 20% (construction and trade areas)
]]

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local function initVehicleZoneDistribution()
    if not VehicleZoneDistribution then
        print("[DumpTruck] ERROR: VehicleZoneDistribution not available")
        return
    end
    
    local VEHICLE_NAME = DumpTruckConstants.VEHICLE_SCRIPT_NAME
    
    -- Helper to add vehicle to zone
    local function addToZone(zoneName, spawnChance)
        VehicleZoneDistribution[zoneName] = VehicleZoneDistribution[zoneName] or {}
        VehicleZoneDistribution[zoneName].vehicles = VehicleZoneDistribution[zoneName].vehicles or {}
        VehicleZoneDistribution[zoneName].vehicles[VEHICLE_NAME] = {index = -1, spawnChance = spawnChance}
    end
    
    -- Add dump trucks to zones
    addToZone("mccoy", 10)        -- McCoy Logging (industrial)
    addToZone("parkingstall", 1) -- General parking lots
    addToZone("medium", 1)       -- Medium density zones
    addToZone("junkyard", 5)     -- Scrapyards
    addToZone("farm", 7)         -- Agricultural areas
    addToZone("trades", 20)      -- Construction sites
    
    print("[DumpTruck] Vehicle zone distribution initialized for " .. VEHICLE_NAME)
end

-- Hook into OnGameBoot - fires after VehicleZoneDistribution is created
Events.OnGameBoot.Add(initVehicleZoneDistribution)
