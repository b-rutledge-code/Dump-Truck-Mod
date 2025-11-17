local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

BAG_WEIGHT = 2.0

DumpTruck_part = {}
DumpTruck_part.Create = {}
DumpTruck_part.Init = {}
DumpTruck_part.Update = {}

function DumpTruck_part.Create.TruckBedDumpTruck(vehicle, part)
    if not vehicle then
        error("Vehicle is nil in TruckBedDumpTruck create logic")
    end
    
    -- Create the part inventory item (CRITICAL - without this the part doesn't exist!)
    local invItem = VehicleUtils.createPartInventoryItem(part)

    local modData = vehicle:getModData()
    if modData.initialized == nil then
        modData.initialized = true
        modData.dumpingGravelActive = false

        -- Check if part exists
        if not part then return end

        -- Retrieve container and set initial load if applicable
        local truckbedcontainer = part:getItemContainer()
        if not truckbedcontainer then
            return
        end

        -- Unique vehicle ID logic
        local vehicleID = vehicle:getID()
        if not vehicleID then
            return
        end

        -- Random gravel load
        -- Always add a shovel
        local _shovel = truckbedcontainer:AddItem("Base.Shovel2")
        
        -- 50% chance to have gravel
        if ZombRand(2) == 0 then
            local totalWeight = truckbedcontainer:getContentsWeight()
            local capacity = truckbedcontainer:getCapacity()
            local maxItems = math.floor((capacity - totalWeight) / BAG_WEIGHT)
            
            -- If truck gets gravel, it's 80-100% full (realistic load)
            local fillPercentage = (80 + ZombRand(21)) / 100.0  -- 0.8 to 1.0
            local numBags = math.floor(maxItems * fillPercentage)
            
            for i = 1, numBags do
                local gravelBag = truckbedcontainer:AddItem("Base.Gravelbag")
                gravelBag:setUseDelta(1.0) -- Set to full capacity
            end
        end

    end

end


function DumpTruck_part.Init.TruckBedDumpTruck(vehicle, part)
    part = vehicle:getPartById("TruckBed")
    -- dumping

end

function DumpTruck_part.Update.TruckBedDumpTruck(vehicle, part)
    if isServer() then
        --local part = vehicle:getPartById("TruckBed")
        --local truckbedcontainer = part:getItemContainer()
        --part:setContainerCapacity(550)
        return
        
    end  
end
    