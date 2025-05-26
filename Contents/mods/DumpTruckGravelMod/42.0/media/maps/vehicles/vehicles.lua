require "Vehicles/vehicles_distributions"

local function initVehicles()
    -- This function is called when the map is loaded
    -- The distribution file we created will be loaded automatically
end

Events.OnLoadMap.Add(initVehicles) 