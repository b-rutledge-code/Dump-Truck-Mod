--[[
    DumpTruckGravelMod - Vehicle Zone Distribution
    
    This file adds the dump truck to various vehicle spawn zones in the game.
    The spawn rates are matched to the base game's pickup truck spawn rates
    to maintain balance while ensuring dump trucks can be found in appropriate areas.
    
    Spawn Rates:
    - McCoy Logging: 10% (industrial area)
    - Parking Stalls: 5% (general parking lots)
    - Medium Areas: 5% (medium density zones)
    - Junkyards: 5% (scrapyards and junkyards)
    - Traffic Jams: 5% (roadblocks and traffic zones)
    - Farms: 14% (agricultural areas)
    - Trades: 20% (construction and trade areas)
]]

if VehicleZoneDistribution then -- Check if table exists
    local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
    local VEHICLE_NAME = DumpTruckConstants.VEHICLE_SCRIPT_NAME

    -- Add dump trucks to industrial areas
    VehicleZoneDistribution.mccoy = VehicleZoneDistribution.mccoy or {}
    VehicleZoneDistribution.mccoy.vehicles = VehicleZoneDistribution.mccoy.vehicles or {}
    VehicleZoneDistribution.mccoy.vehicles[VEHICLE_NAME] = {index = -1, spawnChance = 10}

    -- Parking stall (5%)
    VehicleZoneDistribution.parkingstall = VehicleZoneDistribution.parkingstall or {}
    VehicleZoneDistribution.parkingstall.vehicles = VehicleZoneDistribution.parkingstall.vehicles or {}
    VehicleZoneDistribution.parkingstall.vehicles[VEHICLE_NAME] = {index = -1, spawnChance = 5}

    -- Medium areas (5%)
    VehicleZoneDistribution.medium = VehicleZoneDistribution.medium or {}
    VehicleZoneDistribution.medium.vehicles = VehicleZoneDistribution.medium.vehicles or {}
    VehicleZoneDistribution.medium.vehicles[VEHICLE_NAME] = {index = -1, spawnChance = 5}

    -- Junkyard (5%)
    VehicleZoneDistribution.junkyard = VehicleZoneDistribution.junkyard or {}
    VehicleZoneDistribution.junkyard.vehicles = VehicleZoneDistribution.junkyard.vehicles or {}
    VehicleZoneDistribution.junkyard.vehicles[VEHICLE_NAME] = {index = -1, spawnChance = 5}

    -- Traffic jam (5%)
    if trafficjamVehicles then
        trafficjamVehicles[VEHICLE_NAME] = {index = -1, spawnChance = 5}
    end

    -- Farm (14%)
    VehicleZoneDistribution.farm = VehicleZoneDistribution.farm or {}
    VehicleZoneDistribution.farm.vehicles = VehicleZoneDistribution.farm.vehicles or {}
    VehicleZoneDistribution.farm.vehicles[VEHICLE_NAME] = {index = -1, spawnChance = 14}

    -- Trades (20%)
    VehicleZoneDistribution.trades = VehicleZoneDistribution.trades or {}
    VehicleZoneDistribution.trades.vehicles = VehicleZoneDistribution.trades.vehicles or {}
    VehicleZoneDistribution.trades.vehicles[VEHICLE_NAME] = {index = -1, spawnChance = 20}
end
