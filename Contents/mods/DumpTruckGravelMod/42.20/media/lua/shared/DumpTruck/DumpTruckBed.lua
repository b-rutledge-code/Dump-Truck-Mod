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
local REST_BED = "Bed_0"
local REST_GRAVEL = {
    GravelFull = "GravelFull_0",
    Gravel3_4 = "Gravel3_4_0",
    Gravel1_2 = "Gravel1_2_0",
    Gravel1_4 = "Gravel1_4_0",
}
local POOL_LISTS = 3
local SETS_PER_LIST = 25
local POOL_SIZE = POOL_LISTS * SETS_PER_LIST
local BURY_Y = -100

local SETS = {}
for listIndex = 1, POOL_LISTS do
    local partId = string.format("BedAngle%02d", listIndex)
    for slot = 1, SETS_PER_LIST do
        local setId = (listIndex - 1) * SETS_PER_LIST + slot
        local suffix = string.format("%02d", slot)
        SETS[setId] = {
            partId = partId,
            bedId = "Bed" .. suffix,
            gravel = {
                GravelFull = "GravelFull" .. suffix,
                Gravel3_4 = "Gravel3_4_" .. suffix,
                Gravel1_2 = "Gravel1_2_" .. suffix,
                Gravel1_4 = "Gravel1_4_" .. suffix,
            },
        }
    end
end

local poseByVehicle = {}
local setOwner = {}

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

local function writeModelAngle(scriptPart, modelId, angle, oy, oz)
    local model = scriptPart:getModelById(modelId)
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

local function onDedicatedServer()
    return isServer() and not isClient()
end

local function poseFor(vehicle)
    local pose = poseByVehicle[vehicle]
    if not pose then
        pose = {
            angle = 0,
            target = 0,
            setId = nil,
            bedShown = false,
            restShown = false,
            gravelKey = nil,
        }
        poseByVehicle[vehicle] = pose
    end
    return pose
end

local function truckBedPart(vehicle)
    return vehicle:getPartById("TruckBed")
end

local function anglePart(vehicle, setId)
    local set = SETS[setId]
    if not set then return nil end
    return vehicle:getPartById(set.partId)
end

local function hideLiveModels(truckBed)
    truckBed:setModelVisible(LIVE_BED, false)
    for _, modelId in pairs(LIVE_GRAVEL) do
        truckBed:setModelVisible(modelId, false)
    end
end

local function hideRestModels(truckBed)
    truckBed:setModelVisible(REST_BED, false)
    for _, modelId in pairs(REST_GRAVEL) do
        truckBed:setModelVisible(modelId, false)
    end
end

-- Shared closed bed at angle 0. Uses the baked Bed_0 / Gravel*_0 pictures so the
-- load does not depend on runtime bury offsets shared across every truck.
local function showRestFlat(truckBed, pose, level, force)
    hideLiveModels(truckBed)
    local gravelId = level and REST_GRAVEL[level] or nil
    if not force and pose.restShown and pose.gravelKey == level then
        return
    end
    truckBed:setModelVisible(REST_BED, true)
    for key, modelId in pairs(REST_GRAVEL) do
        truckBed:setModelVisible(modelId, modelId == gravelId)
    end
    pose.restShown = true
    pose.gravelKey = level
end

local function hideSetModels(vehicle, setId)
    local set = SETS[setId]
    if not set then return end
    local part = vehicle:getPartById(set.partId)
    if not part then return end
    part:setModelVisible(set.bedId, false)
    for _, modelId in pairs(set.gravel) do
        part:setModelVisible(modelId, false)
    end
end

local function writeSetAngle(vehicle, setId, angle, activeGravelKey)
    local set = SETS[setId]
    if not set then return end
    local part = vehicle:getPartById(set.partId)
    if not part then return end
    local scriptPart = part:getScriptPart()
    local oy, oz = hingeOffset(angle)
    writeModelAngle(scriptPart, set.bedId, angle, oy, oz)
    for key, modelId in pairs(set.gravel) do
        if key == activeGravelKey then
            writeModelAngle(scriptPart, modelId, angle, oy, oz)
        else
            writeModelAngle(scriptPart, modelId, 0, BURY_Y, 0)
        end
    end
end

local function showSetModels(vehicle, setId)
    local set = SETS[setId]
    if not set then return end
    local part = vehicle:getPartById(set.partId)
    if not part then return end
    part:setModelVisible(set.bedId, true)
    for _, modelId in pairs(set.gravel) do
        part:setModelVisible(modelId, true)
    end
end

local function clearSetOwner(setId, vehicle)
    if setId and setOwner[setId] == vehicle then
        setOwner[setId] = nil
    end
end

local function releaseSet(vehicle, pose)
    if not pose.setId then return end
    hideSetModels(vehicle, pose.setId)
    clearSetOwner(pose.setId, vehicle)
    pose.setId = nil
    pose.bedShown = false
    pose.restShown = false
    pose.gravelKey = nil
end

local function reclaimIdleSet(exceptVehicle)
    for vehicle, pose in pairs(poseByVehicle) do
        if vehicle ~= exceptVehicle and pose.setId and pose.angle == 0 and pose.target == 0 then
            local setId = pose.setId
            local truckBed = truckBedPart(vehicle)
            releaseSet(vehicle, pose)
            if truckBed then
                showRestFlat(truckBed, pose, gravelLevelFor(truckBed), true)
            end
            return setId
        end
    end
    return nil
end

local function acquireSet(vehicle)
    for setId = 1, POOL_SIZE do
        if not setOwner[setId] then
            setOwner[setId] = vehicle
            return setId
        end
    end
    local reclaimed = reclaimIdleSet(vehicle)
    if reclaimed then
        setOwner[reclaimed] = vehicle
        return reclaimed
    end
    print("[DumpTruck] bed angle pool exhausted (" .. POOL_SIZE .. " dumping trucks)")
    return nil
end

local function publishBedPose(vehicle, pose)
    if not DumpTruck or not DumpTruck.publishBedPose then return end
    DumpTruck.publishBedPose(vehicle, pose.setId, pose.angle, pose.target)
end

local function applyShown(vehicle, pose, force)
    if onDedicatedServer() then return end
    local truckBed = truckBedPart(vehicle)
    if not truckBed then return end
    local level = gravelLevelFor(truckBed)
    local moving = pose.angle ~= 0 or pose.target ~= 0

    if moving and not pose.setId then
        pose.setId = acquireSet(vehicle)
        if pose.setId then
            force = true
            publishBedPose(vehicle, pose)
        end
    end

    if pose.setId then
        local set = SETS[pose.setId]
        if not set then
            releaseSet(vehicle, pose)
            showRestFlat(truckBed, pose, level, true)
            return
        end
        setOwner[pose.setId] = vehicle
        hideLiveModels(truckBed)
        hideRestModels(truckBed)
        pose.restShown = false
        if force or not pose.bedShown or pose.gravelKey ~= level then
            showSetModels(vehicle, pose.setId)
            pose.bedShown = true
        end
        writeSetAngle(vehicle, pose.setId, pose.angle, level)
        pose.gravelKey = level
        return
    end

    showRestFlat(truckBed, pose, level, force)
    pose.bedShown = false
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
    if raised and not pose.setId then
        pose.setId = acquireSet(vehicle)
    end
    applyShown(vehicle, pose, instant and true or false)
    publishBedPose(vehicle, pose)
end

function DumpTruck_part.ApplyRemoteBedPose(vehicle, setId, angle, target)
    if onDedicatedServer() or not vehicle then return end
    local pose = poseFor(vehicle)
    if setId and SETS[setId] then
        local previousOwner = setOwner[setId]
        if previousOwner and previousOwner ~= vehicle then
            local previousPose = poseByVehicle[previousOwner]
            if previousPose and previousPose.setId == setId then
                hideSetModels(previousOwner, setId)
                previousPose.setId = nil
                previousPose.bedShown = false
                previousPose.restShown = false
                previousPose.gravelKey = nil
                local previousBed = truckBedPart(previousOwner)
                if previousBed then
                    showRestFlat(previousBed, previousPose, gravelLevelFor(previousBed), true)
                end
            end
        end
        if pose.setId and pose.setId ~= setId then
            hideSetModels(vehicle, pose.setId)
            clearSetOwner(pose.setId, vehicle)
            pose.bedShown = false
            pose.restShown = false
        end
        pose.setId = setId
        setOwner[setId] = vehicle
    end
    if angle ~= nil then
        pose.angle = angle
    end
    if target ~= nil then
        pose.target = target
    end
    applyShown(vehicle, pose, true)
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
