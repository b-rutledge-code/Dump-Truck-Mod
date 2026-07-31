local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

BAG_WEIGHT = 2.0

DumpTruck_part = {}
DumpTruck_part.Create = {}
DumpTruck_part.Init = {}
DumpTruck_part.Update = {}

function DumpTruck_part.Create.TruckBedDumpTruck(vehicle, part)
    local invItem = VehicleUtils.createPartInventoryItem(part)

    local modData = vehicle:getModData()
    if modData.initialized == nil then
        modData.initialized = true
        modData.dumpingGravelActive = false

        if not part then return end

        local truckbedcontainer = part:getItemContainer()
        if not truckbedcontainer then
            return
        end

        local vehicleID = vehicle:getID()
        if not vehicleID then
            return
        end

        -- Always add a shovel
        local shovel = truckbedcontainer:AddItem("Base.Shovel2")
        if shovel and isServer() then
            sendAddItemToContainer(truckbedcontainer, shovel)
        end

        -- 50% chance to have gravel, otherwise empty sacks
        if ZombRand(2) == 0 then
            local totalWeight = truckbedcontainer:getContentsWeight()
            local capacity = truckbedcontainer:getCapacity()
            local maxItems = math.floor((capacity - totalWeight) / BAG_WEIGHT)
            local fillPercentage = (80 + ZombRand(21)) / 100.0
            local numBags = math.floor(maxItems * fillPercentage)

            for i = 1, numBags do
                local gravelBag = truckbedcontainer:AddItem("Base.Gravelbag")
                if gravelBag then
                    gravelBag:setUseDelta(1.0)
                    if isServer() then
                        sendAddItemToContainer(truckbedcontainer, gravelBag)
                    end
                end
            end
        else
            local emptySacks = truckbedcontainer:AddItems("Base.EmptySandbag", 50)
            if emptySacks and isServer() then
                sendAddItemsToContainer(truckbedcontainer, emptySacks)
            end
        end

        -- Distro-style: rolls + weighted items (item, chance, item, chance, ...)
        local function addToPartContainerWeighted(partId, rolls, weightedItems)
            local p = vehicle:getPartById(partId)
            if not p then return end
            local cont = p:getItemContainer()
            if not cont or cont:getCapacity() <= 0 then return end
            local totalChance = 0
            for i = 2, #weightedItems, 2 do
                totalChance = totalChance + weightedItems[i]
            end
            if totalChance <= 0 then return end
            for _ = 1, rolls do
                local r = ZombRand(totalChance)
                for i = 1, #weightedItems - 1, 2 do
                    r = r - weightedItems[i + 1]
                    if r < 0 then
                        local item = cont:AddItem(weightedItems[i])
                        if item and isServer() then
                            sendAddItemToContainer(cont, item)
                        end
                        break
                    end
                end
            end
        end

        addToPartContainerWeighted("GloveBox", 2, {
            "Base.Map", 12, "Base.Pen", 15, "Base.Paper", 12, "Base.Book", 5,
            "Base.Newspaper", 8, "Base.Cigarettes", 10, "Base.Lighter", 6, "Base.KeyRing", 4,
        })

        addToPartContainerWeighted("SeatFrontLeft", 2, {
            "Base.Magazine", 15, "Base.Map", 12, "Base.CandyPackage", 10,
            "Base.WaterBottleFull", 8, "Base.Newspaper", 8, "Base.Book", 5,
        })

        addToPartContainerWeighted("SeatFrontRight", 2, {
            "Base.Gloves_LeatherGloves", 25, "Base.Hat_HardHat", 20,
            "Base.Magazine", 15, "Base.CandyPackage", 10, "Base.WaterBottleFull", 8,
        })
    end
end

function DumpTruck_part.Init.TruckBedDumpTruck(vehicle, part)
    part = vehicle:getPartById("TruckBed")
end

function DumpTruck_part.Update.TruckBedDumpTruck(vehicle, part)
end
