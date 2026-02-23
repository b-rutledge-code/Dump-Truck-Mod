local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")
local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local DumpTruck = {}

-- GRAVEL

function DumpTruck.placeGravelFloorOnSquare(sprite, sq)
    if not sprite or not sq then
        return
    end
    
    -- If upgrading a gap filler, remove the attached triangle overlay first
    local existingFloor = sq:getFloor()
    local floorModData = existingFloor and existingFloor:getModData()
    if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        existingFloor:RemoveAttachedAnims()
        -- NOTE: Intentionally NOT calling resetOverlayMetadata or transmitUpdatedSpriteToClients here
        -- The floor is about to be replaced by addFloor() below, which wipes everything anyway
    end
    
    -- Save original floor sprite so it can be restored when shoveled
    local originalFloor = sq:getFloor()
    local shovelledSprites = nil
    if originalFloor and originalFloor:getSprite() then
        shovelledSprites = {}
        -- Save the main sprite only
        table.insert(shovelledSprites, originalFloor:getSprite():getName())
    end
    
    local newFloor = sq:addFloor(sprite)
    -- Set modData on the new floor so it can be restored when shoveled
    if newFloor and shovelledSprites and #shovelledSprites > 0 then
        local floorModData = newFloor:getModData()
        floorModData.shovelledSprites = shovelledSprites
        floorModData.pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
        floorModData.shovelled = nil  -- Clear shovelled flag (matches vanilla behavior)
        newFloor:transmitModData()  -- Sync to other clients
    end
    
    -- Disable erosion on this square
    sq:disableErosion()
    -- Tell clients to set doNothing on their copy (erosion state does not sync with floor change)
    if isServer() then
        sendServerCommand("DumpTruckGravelMod", "disableErosionAt", { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
    end

    DumpTruckOverlays.removeOppositeEdgeBlends(sq)

    
    sq:RecalcProperties()
    sq:DirtySlice()
    if sq.transmitFloor then sq:transmitFloor() end
end

function DumpTruck.consumeGravelFromTruckBed(vehicle)
    if DumpTruck.debugMode then
        return true
    end

    local truckBed = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if not truckBed or not truckBed:getItemContainer() then
        return false
    end

    local container = truckBed:getItemContainer()
    local items = container:getItems()

    for i = 0, items:size() - 1 do
        local item = items:get(i)

        if item:getFullType() == DumpTruckConstants.BAG_TYPE then
            local currentUses = item:getCurrentUses()
            if currentUses > 0 then
                local newCount = currentUses - 1
                item:setCurrentUses(newCount)
                if newCount <= 0 then
                    container:Remove(item)
                    container:AddItem("Base.EmptySandbag")
                end
                container:setDrawDirty(true)
                return true
            end
        end
    end

    return false
end

function DumpTruck.getGravelCount(vehicle)
    if DumpTruck.debugMode then
        return 100
    end

    local totalUses = 0
    local truckBed = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if not truckBed or not truckBed:getItemContainer() then
        return totalUses
    end
    local items = truckBed:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == DumpTruckConstants.BAG_TYPE then
            local currentUses = item:getCurrentUses()
            totalUses = totalUses + currentUses
        end
    end
    return totalUses
end

-- ROAD BUILDING


--[[
    getBackSquares: Gets the squares behind the truck for gravel placement
    Input:
        fx: number - Forward vector X component
        fy: number - Forward vector Y component
        cx: number - Current X position
        cy: number - Current Y position
        cz: number - Z level (usually 0)
        width: number - Width of gravel road in tiles
        length: number - Length of truck in tiles
    Output: array of IsoGridSquare - The squares where gravel should be placed
]]
function DumpTruck.getBackSquares(fx, fy, cx, cy, cz, width, length)
    
    -- Calculate offset backwards along forward vector
    local offsetDistance = (length/2)  -- Half truck length plus 1 tile
    local offsetX = -fx * offsetDistance  -- Negative forward vector
    local offsetY = -fy * offsetDistance
    
    -- Apply offset to center point
    local centerX = cx + math.floor(offsetX + 0.5)  -- Round to nearest integer
    local centerY = cy + math.floor(offsetY + 0.5)
    
    -- Calculate perpendicular vector (90 degrees) for road width
    -- For a vector (x,y) in Zomboid's inverted Y coordinate system
    -- We use (-y,x) because Y is inverted, so this gives us a vector to the right of the truck
    local perpX = -fy   -- In inverted Y, this gives us right
    local perpY = fx
    
    -- Find the dominant axis and snap to it
    -- This ensures we get a clean cardinal direction
    if math.abs(perpX) > math.abs(perpY) then
        -- Snap to East/West
        perpX = perpX > 0 and 1 or -1
        perpY = 0
    else
        -- Snap to North/South
        perpX = 0
        perpY = perpY > 0 and 1 or -1
    end
    
    -- Generate points based on width
    local points = {}
    for i = 0, width - 1 do
        table.insert(points, {
            x = centerX + (perpX * i),
            y = centerY + (perpY * i),
            z = cz
        })
    end
    
    -- Convert points to squares
    local squares = {}
    for _, point in ipairs(points) do
        local square = getCell():getGridSquare(point.x, point.y, point.z)
        if square then
            table.insert(squares, square)
        end
    end
    
    return squares
end

local oldX, oldY = 0, 0
-- Modify tryPourGravelUnderTruck to handle transitions
function DumpTruck.tryPourGravelUnderTruck(vehicle)
    if not vehicle or vehicle:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then return end

    local data = vehicle:getModData()
    if not data.dumpingGravelActive then return end  -- Only proceed if dumping is active

    local cx, cy, cz = vehicle:getX(), vehicle:getY(), vehicle:getZ()
    DumpTruckCore.debugPrint("Vehicle coordinates: cx=" .. cx .. ", cy=" .. cy .. ", cz=" .. cz)
    cz = 0 -- Assume ground level for simplicity

    -- Get forward vector first (returns nil if no driver)
    local fx, fy = DumpTruckCore.getVectorFromPlayer(vehicle)
    if not fx or not fy then
        -- No driver - can't pour gravel (need direction), but keep dump state active
        -- Passenger can activate dump and wait for driver
        return
    end
    
    -- Calculate perpendicular vector (90 degrees to forward)
    local perpX = -fy
    local perpY = fx
    
    -- Apply threshold only in perpendicular direction (sideways drift)
    local threshold = 0.3
    local adjustedX = cx + (perpX * threshold)
    local adjustedY = cy + (perpY * threshold)
    local tileX = math.floor(adjustedX)
    local tileY = math.floor(adjustedY)
    
    if tileX == oldX and tileY == oldY then return end
    oldX, oldY = tileX, tileY

    local script = vehicle:getScript()
    local extents = script:getExtents()
    local vehicleWidth = math.floor(extents:x() + 0.5)
    local length = math.floor(extents:z() + 0.5)
    
    -- Determine road width based on vehicle width and user preference
    local modData = vehicle:getModData()
    local wideMode = modData.wideRoadMode or false
    local roadWidth = vehicleWidth
    if wideMode and vehicleWidth < 3 then
        roadWidth = vehicleWidth + 1
    end
    
    local currentSquares = DumpTruck.getBackSquares(fx, fy, cx, cy, cz, roadWidth, length)
    
    -- Debug print current squares
    DumpTruckCore.debugPrint("tryPourGravelUnderTruck: Current squares to process:")
    for i, sq in ipairs(currentSquares) do
        DumpTruckCore.debugPrint(string.format("[DEBUG] Current square %d - x: %d, y: %d", 
            tostring(i), tostring(sq:getX()), tostring(sq:getY())))
    end
    
    -- Track if any gravel was placed this update
    local gravelPlaced = false
    
    -- Check gravel count BEFORE the loop (only check once per update cycle)
    if DumpTruck.getGravelCount(vehicle) <= 0 then
        DumpTruck.stopDumping(vehicle)
        return
    end
    
    local DumpTruckPourEffect = require("DumpTruck/DumpTruckPourEffect")

    -- Place gravel on valid squares, skipping ones that already have gravel
    for _, sq in ipairs(currentSquares) do
        if sq and DumpTruckCore.isSquareValidForGravel(sq) then
            DumpTruckCore.debugPrint("PLACED gravel at square: x=" .. sq:getX() .. ", y=" .. sq:getY())
            DumpTruckPourEffect.schedulePlaceAndEffect(sq, vehicle)
            gravelPlaced = true
            
            -- Check again after consuming (in case we just ran out)
            if DumpTruck.getGravelCount(vehicle) <= 0 then
                DumpTruck.stopDumping(vehicle)
                return
            end
        else
            if sq then
                DumpTruckCore.debugPrint("SKIPPED square (not valid): x=" .. sq:getX() .. ", y=" .. sq:getY())
            end
        end
    end
    DumpTruckOverlays.smoothRoad(currentSquares, fx, fy)
end

-- Update function for player actions
local elapsedTime = 0
function DumpTruck.onPlayerUpdateFunc(player)
    if player then
        local vehicle = player:getVehicle()
        if vehicle and vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
            local deltaTime = GameTime:getInstance():getRealworldSecondsSinceLastUpdate()
            elapsedTime = elapsedTime + deltaTime  -- Safe addition
            if elapsedTime < DumpTruckConstants.UPDATE_INTERVAL then
                return
            end
            elapsedTime = 0

            DumpTruck.tryPourGravelUnderTruck(vehicle)
        end
    end
end
Events.OnPlayerUpdate.Add(DumpTruck.onPlayerUpdateFunc)

-- Stop dumping sounds
function DumpTruck.stopDumpingSounds(vehicle, soundID)
    
    -- Stop loop if playing
    if soundID and soundID ~= 0 then
        local emitter = vehicle:getEmitter()
        if emitter then
            emitter:stopSound(soundID)
        end
    end
    
    -- Only play stop sounds if we have a valid soundID (meaning dumping was actually active)
    if soundID and soundID ~= 0 then
        vehicle:playSound("HydraulicLiftDown")
        vehicle:playSound("GravelDumpEnd")
    end
    
    -- Clear from modData
    local data = vehicle:getModData()
    data.gravelLoopSoundID = nil
end

-- Start dumping
function DumpTruck.startDumping(vehicle)
    local data = vehicle:getModData()
    data.dumpingGravelActive = true
    
    -- Start dumping sounds
    vehicle:playSound("HydraulicLiftRaised")
    vehicle:playSound("GravelDumpStart")
    local emitter = vehicle:getEmitter()
    data.gravelLoopSoundID = emitter:playSound("GravelDumpLoop")
end

-- Stop dumping
function DumpTruck.stopDumping(vehicle)
    local data = vehicle:getModData()
    
    -- Only stop if actually dumping (prevents repeated calls)
    if not data.dumpingGravelActive then
        return
    end
    
    data.dumpingGravelActive = false
    
    -- Stop dumping sounds
    DumpTruck.stopDumpingSounds(vehicle, data.gravelLoopSoundID)
end


-- Recreate overlay sprites from floor modData when squares load (handles persistence)
-- Uses AttachExistingAnim to reattach sprite to floor
-- MP: when server places gravel it sends disableErosionAt; clients run disableErosion() on their copy so erosion (trees/grass) does not run there
Events.OnServerCommand.Add(function(module, command, args)
    if module == "DumpTruckGravelMod" and command == "disableErosionAt" and args and args.x and args.y and args.z then
        local cell = getCell()
        if cell then
            local sq = cell:getGridSquare(args.x, args.y, args.z)
            if sq then sq:disableErosion() end
        end
    end
end)

Events.LoadGridsquare.Add(function(square)
    local floor = square:getFloor()
    if not floor then return end
    
    local floorModData = floor:getModData()
    if floorModData and floorModData.overlaySprite then
        -- Only attach if floor doesn't already have attached anims (avoid duplicates)
        if not floor:hasAttachedAnimSprites() then
            local sprite = getSprite(floorModData.overlaySprite)
            if sprite then
                floor:AttachExistingAnim(sprite, 0, 0, false, 0, false, 0.0)
            end
        end
    end
end)


return DumpTruck