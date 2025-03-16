-- Extends vanilla VehicleZoneDistribution to add dump trucks
if VehicleZoneDistribution then -- Check if table exists
    -- Add dump trucks to industrial areas
    VehicleZoneDistribution.mccoy = VehicleZoneDistribution.mccoy or {}
    VehicleZoneDistribution.mccoy.vehicles = VehicleZoneDistribution.mccoy.vehicles or {}
    VehicleZoneDistribution.mccoy.vehicles["Base.DumpTruck"] = {index = -1, spawnChance = 10}

    -- Parking stall (5%)
    VehicleZoneDistribution.parkingstall = VehicleZoneDistribution.parkingstall or {}
    VehicleZoneDistribution.parkingstall.vehicles = VehicleZoneDistribution.parkingstall.vehicles or {}
    VehicleZoneDistribution.parkingstall.vehicles["Base.DumpTruck"] = {index = -1, spawnChance = 5}

    -- Medium areas (5%)
    VehicleZoneDistribution.medium = VehicleZoneDistribution.medium or {}
    VehicleZoneDistribution.medium.vehicles = VehicleZoneDistribution.medium.vehicles or {}
    VehicleZoneDistribution.medium.vehicles["Base.DumpTruck"] = {index = -1, spawnChance = 5}

    -- Junkyard (5%)
    VehicleZoneDistribution.junkyard = VehicleZoneDistribution.junkyard or {}
    VehicleZoneDistribution.junkyard.vehicles = VehicleZoneDistribution.junkyard.vehicles or {}
    VehicleZoneDistribution.junkyard.vehicles["Base.DumpTruck"] = {index = -1, spawnChance = 5}

    -- Traffic jam (5%)
    if trafficjamVehicles then
        trafficjamVehicles["Base.DumpTruck"] = {index = -1, spawnChance = 5}
    end

    -- Farm (14%)
    VehicleZoneDistribution.farm = VehicleZoneDistribution.farm or {}
    VehicleZoneDistribution.farm.vehicles = VehicleZoneDistribution.farm.vehicles or {}
    VehicleZoneDistribution.farm.vehicles["Base.DumpTruck"] = {index = -1, spawnChance = 14}

    -- Trades (20%)
    VehicleZoneDistribution.trades = VehicleZoneDistribution.trades or {}
    VehicleZoneDistribution.trades.vehicles = VehicleZoneDistribution.trades.vehicles or {}
    VehicleZoneDistribution.trades.vehicles["Base.DumpTruck"] = {index = -1, spawnChance = 20}
end 