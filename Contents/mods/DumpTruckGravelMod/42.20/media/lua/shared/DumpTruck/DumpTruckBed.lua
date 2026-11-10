local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

BAG_WEIGHT = 2.0

DumpTruck_part = {}
DumpTruck_part.Create = {}
DumpTruck_part.Init = {}
DumpTruck_part.Update = {}

local BED_ANGLE_RAISED = -40
local BED_TRAVEL_SECONDS = 1.2
local HINGE_Y = 0.424840
local HINGE_Z = -1.150195
local LIVE_BED = "BedLive"
local LIVE_GRAVEL = {
    GravelFull = "GravelFullLive",
    Gravel3_4 = "Gravel3_4Live",
    Gravel1_2 = "Gravel1_2Live",
    Gravel1_4 = "Gravel1_4Live",
}

local poseByVehicle = {}
local BURY_Y = -100

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

local function writeModelAngle(part, modelId, angle, oy, oz)
    local model = part:getScriptPart():getModelById(modelId)
    if not model then return end
    model:getOffset():set(0, oy, oz)
    model:getRotate():set(angle, 0, 0)
end

local function hingeOffset(angle)
    local theta = math.rad(angle)
    local cosine = math.cos(theta)
    local sine = math.sin(theta)
    local rotatedY = HINGE_Y * cosine - HINGE_Z * sine
    local rotatedZ = HINGE_Y * sine + HINGE_Z * cosine
    return HINGE_Y - rotatedY, HINGE_Z - rotatedZ
end

local function writeLiveAngle(part, angle, activeGravelId)
    local oy, oz = hingeOffset(angle)
    writeModelAngle(part, LIVE_BED, angle, oy, oz)
    for _, modelId in pairs(LIVE_GRAVEL) do
        if modelId == activeGravelId then
            writeModelAngle(part, modelId, angle, oy, oz)
        else
            writeModelAngle(part, modelId, 0, BURY_Y, 0)
        end
    end
end

local function poseFor(vehicle)
    local pose = poseByVehicle[vehicle]
    if not pose then
        pose = { angle = 0, target = 0, bedId = nil, gravelId = nil, liveGravel = false }
        poseByVehicle[vehicle] = pose
    end
    return pose
end

local function onDedicatedServer()
    return isServer() and not isClient()
end

local function hideLiveModels(part)
    part:setModelVisible(LIVE_BED, false)
    for _, modelId in pairs(LIVE_GRAVEL) do
        part:setModelVisible(modelId, false)
    end
end

local function showLiveModels(part)
    part:setModelVisible(LIVE_BED, true)
    for _, modelId in pairs(LIVE_GRAVEL) do
        part:setModelVisible(modelId, true)
    end
end

local function showRestModels(part, pose, level, force)
    local bedId = "Bed_0"
    local gravelId = level and (level .. "_0") or nil
    if not force and pose.bedId == bedId and pose.gravelId == gravelId then return end
    if pose.bedId and pose.bedId ~= bedId then
        part:setModelVisible(pose.bedId, false)
    end
    part:setModelVisible(bedId, true)
    pose.bedId = bedId
    if pose.gravelId and pose.gravelId ~= gravelId then
        part:setModelVisible(pose.gravelId, false)
    end
    if gravelId then
        part:setModelVisible(gravelId, true)
    end
    pose.gravelId = gravelId
end

local function releaseLive(vehicle, pose)
    local part = vehicle:getPartById("TruckBed")
    if not part then return end
    hideLiveModels(part)
    pose.liveGravel = false
    pose.bedId = nil
    pose.gravelId = nil
    showRestModels(part, pose, gravelLevelFor(part), true)
end

local function releaseOtherLiveTrucks(keep)
    for vehicle, pose in pairs(poseByVehicle) do
        if vehicle ~= keep and pose.liveGravel and pose.angle == 0 and pose.target == 0 then
            releaseLive(vehicle, pose)
        end
    end
end

local function otherTruckMoving(keep)
    for vehicle, pose in pairs(poseByVehicle) do
        if vehicle ~= keep and (pose.angle ~= 0 or pose.target ~= 0) then
            return true
        end
    end
    return false
end

local function applyShown(vehicle, pose, force)
    if onDedicatedServer() then return end
    local part = vehicle:getPartById("TruckBed")
    if not part then return end
    local moving = pose.angle ~= 0 or pose.target ~= 0
    local level = gravelLevelFor(part)
    if moving then
        releaseOtherLiveTrucks(vehicle)
        local gravelId = level and LIVE_GRAVEL[level] or nil
        writeLiveAngle(part, pose.angle, gravelId)
        if not force and pose.liveGravel then
            pose.gravelId = gravelId
            pose.bedId = LIVE_BED
            return
        end
        if pose.bedId and pose.bedId ~= LIVE_BED then
            part:setModelVisible(pose.bedId, false)
        end
        if pose.gravelId and not pose.liveGravel then
            part:setModelVisible(pose.gravelId, false)
        end
        showLiveModels(part)
        pose.liveGravel = true
        pose.bedId = LIVE_BED
        pose.gravelId = gravelId
        return
    end

    if pose.liveGravel then
        if not otherTruckMoving(vehicle) then
            local gravelId = level and LIVE_GRAVEL[level] or nil
            writeLiveAngle(part, 0, gravelId)
            pose.bedId = LIVE_BED
            pose.gravelId = gravelId
        end
        return
    end

    showRestModels(part, pose, level, force)
end

local function showGravel(part, force)
    if onDedicatedServer() then return end
    local vehicle = part:getVehicle()
    if not vehicle then return end
    local pose = poseByVehicle[vehicle]
    if not pose then return end
    applyShown(vehicle, pose, force)
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
    end
    applyShown(vehicle, pose, instant)
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
    local dumping = DumpTruck and DumpTruck.dumpingActive and getPlayer() and getPlayer():getVehicle() == vehicle
    DumpTruck_part.SetBedRaised(vehicle, dumping and true or false, true)
end

function DumpTruck_part.Update.TruckBedDumpTruck(vehicle, part)
end
