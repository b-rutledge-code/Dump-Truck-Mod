local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

BAG_WEIGHT = 2.0

DumpTruck_part = {}
DumpTruck_part.Create = {}
DumpTruck_part.Init = {}
DumpTruck_part.Update = {}

local BED_ANGLE_RAISED = -40
local BED_TRAVEL_SECONDS = 1.2
local POSE_STEPS = {}
for step = 0, 40 do
    POSE_STEPS[step + 1] = step
end

local poseByVehicle = {}

local function getFullBedUses(part)
    local container = part:getItemContainer()
    if not container then return 0 end
    -- Pour count for one full bag. The bag can report a smaller max than the pours it still holds.
    local usesPerBag = 1
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and DumpTruckConstants.POURABLE_BY_BAG[item:getFullType()] then
            local n = item:getMaxUses()
            local current = item:getCurrentUses()
            if current > n then n = current end
            if n > usesPerBag then usesPerBag = n end
        end
    end
    return math.floor(container:getCapacity() / BAG_WEIGHT) * usesPerBag
end

local function getPourableUsesFromPart(part)
    local container = part:getItemContainer()
    if not container then return 0 end
    local total = 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and DumpTruckConstants.POURABLE_BY_BAG[item:getFullType()] then
            total = total + item:getCurrentUses()
        end
    end
    return total
end

local function gravelLevelFor(part)
    if part:getInventoryItem() == nil then return nil end
    local remaining = getPourableUsesFromPart(part)
    if remaining <= 0 then return nil end
    local full = getFullBedUses(part)
    if full <= 0 then return "Gravel1_4" end
    local frac = remaining / full
    if frac > 0.75 then
        return "GravelFull"
    elseif frac > 0.5 then
        return "Gravel3_4"
    elseif frac > 0.25 then
        return "Gravel1_2"
    end
    return "Gravel1_4"
end

local function stepForAngle(angle)
    local mag = math.abs(angle)
    local best = POSE_STEPS[1]
    local bestDist = math.abs(mag - best)
    for i = 2, #POSE_STEPS do
        local step = POSE_STEPS[i]
        local dist = math.abs(mag - step)
        if dist < bestDist then
            best = step
            bestDist = dist
        end
    end
    return best
end

local function poseFor(vehicle)
    local pose = poseByVehicle[vehicle]
    if not pose then
        pose = { angle = 0, target = 0, bedId = nil, gravelId = nil }
        poseByVehicle[vehicle] = pose
    end
    return pose
end

local function applyShown(vehicle, pose, force)
    local part = vehicle:getPartById("TruckBed")
    if not part then return end
    local step = stepForAngle(pose.angle)
    local level = gravelLevelFor(part)
    local bedId = "Bed_" .. step
    local gravelId = level and (level .. "_" .. step) or nil
    if not force and pose.bedId == bedId and pose.gravelId == gravelId then return end
    if pose.bedId ~= bedId then
        if pose.bedId then part:setModelVisible(pose.bedId, false) end
        part:setModelVisible(bedId, true)
        pose.bedId = bedId
    end
    if pose.gravelId ~= gravelId then
        if pose.gravelId then part:setModelVisible(pose.gravelId, false) end
        if gravelId then part:setModelVisible(gravelId, true) end
        pose.gravelId = gravelId
    end
end

local function showGravel(part, force)
    local vehicle = part:getVehicle()
    if not vehicle then return end
    applyShown(vehicle, poseFor(vehicle), force)
end

function DumpTruck_part.UpdateGravelLoads()
    local cell = getCell()
    if not cell then return end
    local vehicles = cell:getVehicles()
    local iterator = vehicles:iterator()
    while iterator:hasNext() do
        local vehicle = iterator:next()
        if vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
            local part = vehicle:getPartById(DumpTruckConstants.PART_NAME)
            if part then
                showGravel(part, false)
            end
        end
    end
end

function DumpTruck_part.SetBedRaised(vehicle, raised, instant)
    if not vehicle then return end
    local pose = poseFor(vehicle)
    local target = raised and BED_ANGLE_RAISED or 0
    pose.target = target
    if instant then
        pose.angle = target
        applyShown(vehicle, pose, true)
    end
end

function DumpTruck_part.UpdateBedPose(dt)
    if not dt or dt <= 0 then return end
    local rate = math.abs(BED_ANGLE_RAISED) / BED_TRAVEL_SECONDS
    for vehicle, pose in pairs(poseByVehicle) do
        if pose.angle ~= pose.target then
            if pose.target < pose.angle then
                pose.angle = math.max(pose.target, pose.angle - rate * dt)
            else
                pose.angle = math.min(pose.target, pose.angle + rate * dt)
            end
        end
        applyShown(vehicle, pose, false)
    end
end

function DumpTruck_part.Create.TruckBedDumpTruck(vehicle, part)
    local invItem = VehicleUtils.createPartInventoryItem(part)
    DumpTruck_part.SetBedRaised(vehicle, false, true)

    local modData = vehicle:getModData()
    if modData.initialized == nil then
        modData.initialized = true

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
                if gravelBag and isServer() then
                    sendAddItemToContainer(truckbedcontainer, gravelBag)
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

    showGravel(part, true)
end

function DumpTruck_part.Init.TruckBedDumpTruck(vehicle, part)
    part = vehicle:getPartById("TruckBed")
    DumpTruck_part.SetBedRaised(vehicle, false, true)
end

function DumpTruck_part.Update.TruckBedDumpTruck(vehicle, part)
    showGravel(part, false)
end
