local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

DumpTruck = {}
DumpTruck.debugMode = false

-- Utility function for debug printing
function DumpTruck.debugPrint(...)
    if DumpTruck.debugMode then
        print("[DEBUG]", ...)
    end
end

-- HELPERS

-- Check if a tile is poured gravel
function DumpTruck.isPouredGravel(tile)
    if not tile then return false end
    local floor = tile:getFloor()
    return floor and floor:getModData().pouredFloor == DumpTruckConstants.POURED_FLOOR_TYPE
end

-- Check if square is valid for gravel
function DumpTruck.isSquareValidForGravel(sq)
    if not sq then
        DumpTruck.debugPrint("Square is nil.")
        return false
    end
    if CFarmingSystem and CFarmingSystem.instance:getLuaObjectOnSquare(sq) then
        DumpTruck.debugPrint(string.format("Farming system object on square (%d, %d, %d).", sq:getX(), sq:getY(), sq:getZ()))
        return false
    end
    if sq:getProperties() and sq:getProperties():Is(IsoFlagType.water) then
        DumpTruck.debugPrint(string.format("Square (%d, %d, %d) is water.", sq:getX(), sq:getY(), sq:getZ()))
        return false
    end
    if DumpTruck.isPouredGravel(sq) then
        DumpTruck.debugPrint(string.format("Square (%d, %d, %d) already has poured gravel.", sq:getX(), sq:getY(), sq:getZ()))
        return false
    end
    return true
end

function DumpTruck.getPrimaryAxis(fx, fy)
    -- Calculate the angle for debugging
    local angle = math.deg(math.atan2(-fy, fx))
    if angle < 0 then angle = angle + 360 end
    DumpTruck.debugPrint(string.format("Movement angle: %.2f degrees", angle))
    
    -- Original logic
    if math.abs(fx) > math.abs(fy) * (1 + .2) then
        return DumpTruckConstants.AXIS.X
    else
        return DumpTruckConstants.AXIS.Y
    end
end

-- get vehicle vector 
function DumpTruck.getVector(vehicle)
    local dir = vehicle:getDir()
    local fx = dir:dx()
    local fy = dir:dy()
    DumpTruck.debugPrint(string.format("Vehicle Vector: fx=%.3f, fy=%.3f.", fx, fy))
    return fx, fy
end

function DumpTruck.getVectorFromPlayer(vehicle)
    -- Get the driver of the vehicle
    local driver = vehicle:getDriver()
    if driver == nil then
        DumpTruck.debugPrint("No driver found.")
        return nil, nil
    end

    -- Get the driver's forward direction as a vector
    local vector = Vector2.new()
    driver:getForwardDirection(vector)

    DumpTruck.debugPrint(string.format("Player Direction: x=%.3f, y=%.3f.", vector:getX(), vector:getY()))
    return vector:getX(), vector:getY()
end

-- BLENDING


function DumpTruck.getBlendNaturalSprite(sq)
    if not sq then return nil end
    local floor = sq:getFloor()
    if floor then
        local spriteName = floor:getSprite():getName()
        if spriteName and spriteName:find("^blends_natural_01_") then
            return spriteName
        end
    end
    return nil
end

function DumpTruck.removeOppositeEdgeBlends(square)
    if not square then 
        DumpTruck.debugPrint("removeOppositeEdgeBlends: Square is nil")
        return 
    end
    
    DumpTruck.debugPrint(string.format("removeOppositeEdgeBlends: Checking square at (%d, %d)", square:getX(), square:getY()))
    
    -- Check each direction
    local adjacentChecks = {
        {square = square:getN(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.SOUTH, dir = "North"},
        {square = square:getS(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.NORTH, dir = "South"},
        {square = square:getE(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.WEST, dir = "East"},
        {square = square:getW(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.EAST, dir = "West"}
    }
    
    for _, check in ipairs(adjacentChecks) do
        if check and check.square then
            DumpTruck.debugPrint(string.format("Checking %s adjacent square at (%d, %d)", check.dir, check.square:getX(), check.square:getY()))
            local objects = check.square:getObjects()
            DumpTruck.debugPrint(string.format("Found %d objects on square", objects:size()))
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if obj then
                    local spriteName = obj:getSpriteName()

                    if spriteName then
                        DumpTruck.debugPrint(string.format("Checking sprite: %s", spriteName))

                        -- Extract the base number from the sprite name
                        if spriteName:find("^blends_natural_01_") then
                            local baseNumber = tonumber(spriteName:match("blends_natural_01_(%d+)"))
                            if baseNumber then
                                local baseRow = math.floor(baseNumber / 16)
                                local rowStartTile = baseRow * 16
                                
                                -- Check if the sprite matches any of the opposite sprites we want to remove
                                local shouldRemove = false
                                for _, oppositeOffset in ipairs(check.oppositeSprites) do
                                    local oppositeSprite = rowStartTile + oppositeOffset
                                    if baseNumber == oppositeSprite then
                                        shouldRemove = true
                                        break
                                    end
                                end
                                
                                if shouldRemove then
                                    DumpTruck.debugPrint(string.format("Removing opposite blend sprite from square (%d, %d)", check.square:getX(), check.square:getY()))
                                    check.square:RemoveTileObject(obj)
                                    check.square:RecalcProperties()
                                    check.square:DirtySlice()
                                    if isClient() then
                                        check.square:transmitFloor()
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function DumpTruck.getBlendOverlayFromOffset(direction, terrainBlock)
    if not terrainBlock or type(terrainBlock) ~= "string" or not terrainBlock:find("^blends_natural_01_") then
        DumpTruck.debugPrint("Invalid terrainBlock. Must be a blends_natural_01_ tile.")
        return nil
    end
    
    -- Extract the base number from the sprite name
    local baseNumber = tonumber(terrainBlock:match("blends_natural_01_(%d+)"))
    if not baseNumber then
        DumpTruck.debugPrint("Could not extract base number from terrain block")
        return nil
    end
    
    local baseRow = math.floor(baseNumber / 16)
    local rowStartTile = baseRow * 16
    
    local offsets = DumpTruckConstants.DIRECTION_OFFSETS[direction]
    if not offsets then return nil end
    
    -- Randomly choose between the two variations
    local offset = offsets[ZombRand(1, 3)] -- ZombRand(1,3) returns either 1 or 2
    
    -- Calculate final overlay tile ID using the base number
    local overlayTile = rowStartTile + offset
    DumpTruck.debugPrint(string.format("Using blend overlay %d for direction %s", overlayTile, direction))
    
    return "blends_natural_01_" .. overlayTile
end

function DumpTruck.placeTileOverlay(mainTile, offsetX, offsetY, cz, sprite)
    local cell = getCell()
    -- For direct square placement, mainTile will be the square itself
    local targetSquare = cell:getGridSquare(mainTile:getX() + offsetX, mainTile:getY() + offsetY, cz)
   
    if not targetSquare then
        DumpTruck.debugPrint("Failed to get grid square")
        return
    end
    
    if not DumpTruck.isSquareValidForGravel(targetSquare) then
        DumpTruck.debugPrint(string.format("Square at (%d, %d) is not valid for gravel", targetSquare:getX(), targetSquare:getY()))
        return
    end

    -- Check for existing overlay -- Do I need this?
    local existingObjects = targetSquare:getObjects()
    for i = 0, existingObjects:size() - 1 do
        local obj = existingObjects:get(i)
        if obj:getSpriteName() == sprite then
            DumpTruck.debugPrint(string.format("Overlay already exists on square (%d, %d, %d).", targetSquare:getX(), targetSquare:getY(), targetSquare:getZ()))
            return
        end
    end

    DumpTruck.removeOppositeEdgeBlends(targetSquare)

    -- Set floor metadata
    local floor = targetSquare:getFloor()
    if floor then
        floor:getModData().gravelOverlay = true
        floor:getModData().pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
    end

    -- Add the overlay
    local overlay = IsoObject.new(cell, targetSquare, sprite)
    targetSquare:AddTileObject(overlay)
    targetSquare:RecalcProperties()
    targetSquare:DirtySlice()
    DumpTruck.debugPrint(string.format("Placed overlay on square (%d, %d, %d).", targetSquare:getX(), targetSquare:getY(), targetSquare:getZ()))
end


function DumpTruck.smoothRoad(currentSquares, fx, fy)
    if #currentSquares ~= 2 then
        DumpTruck.debugPrint("Error: Expected exactly two tiles in the current set.")
        return
    end

    local currTile1, currTile2 = currentSquares[1], currentSquares[2]
    DumpTruck.debugPrint(string.format("Smoothing road for tiles: (%d,%d) and (%d,%d)", currTile1:getX(), currTile1:getY(), currTile2:getX(), currTile2:getY()))

    local cz = currTile1:getZ()

    if DumpTruck.getPrimaryAxis(fx, fy) == DumpTruckConstants.AXIS.X then
        DumpTruck.debugPrint("Smoothing East/West")
        if fx > 0 then
            local westTile1HasGravel = DumpTruck.isPouredGravel(currTile1:getW())
            local westTile2HasGravel = DumpTruck.isPouredGravel(currTile2:getW())
            DumpTruck.debugPrint(string.format("West tiles gravel status: %s, %s", tostring(westTile1HasGravel), tostring(westTile2HasGravel)))

            if westTile1HasGravel and not westTile2HasGravel then
                DumpTruck.debugPrint("Top tile has west gravel, bottom doesn't")
                DumpTruck.placeTileOverlay(currTile2, -1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.EAST)
                DumpTruck.placeTileOverlay(currTile1, 0, -1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.WEST)
            elseif not westTile1HasGravel and westTile2HasGravel then
                DumpTruck.debugPrint("Bottom tile has west gravel, top doesn't")
                DumpTruck.placeTileOverlay(currTile1, -1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.SOUTH)
                DumpTruck.placeTileOverlay(currTile2, 0, 1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.NORTH)
            else
                DumpTruck.debugPrint("No fillers needed. Both west tiles are consistent.")
                -- Add terrain blending for aligned E/W road
                local northSq = currTile1:getN()
                local southSq = currTile2:getS()
                
                local northTerrain = DumpTruck.getBlendNaturalSprite(northSq)
                local southTerrain = DumpTruck.getBlendNaturalSprite(southSq)

                if northTerrain then
                    local northBlend = DumpTruck.getBlendOverlayFromOffset("NORTH", northTerrain)
                    if northBlend then
                        local obj = IsoObject.new(getCell(), currTile1, northBlend)
                        currTile1:AddTileObject(obj)
                    end
                end

                if southTerrain then
                    local southBlend = DumpTruck.getBlendOverlayFromOffset("SOUTH", southTerrain)
                    if southBlend then
                        local obj = IsoObject.new(getCell(), currTile2, southBlend)
                        currTile2:AddTileObject(obj)
                    end
                end
            end
        else
            local eastTile1HasGravel = DumpTruck.isPouredGravel(currTile1:getE())
            local eastTile2HasGravel = DumpTruck.isPouredGravel(currTile2:getE())
            DumpTruck.debugPrint(string.format("East tiles gravel status: %s, %s", tostring(eastTile1HasGravel), tostring(eastTile2HasGravel)))

            if eastTile1HasGravel and not eastTile2HasGravel then
                DumpTruck.debugPrint("Top tile has east gravel, bottom doesn't")
                DumpTruck.placeTileOverlay(currTile2, 1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.NORTH)
                DumpTruck.placeTileOverlay(currTile1, 0, -1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.SOUTH)
            elseif not eastTile1HasGravel and eastTile2HasGravel then
                DumpTruck.debugPrint("Bottom tile has east gravel, top doesn't")
                DumpTruck.placeTileOverlay(currTile1, 1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.WEST)
                DumpTruck.placeTileOverlay(currTile2, 0, 1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.EAST)
            else
                DumpTruck.debugPrint("No fillers needed. Both east tiles are consistent.")
                -- Add terrain blending for aligned E/W road
                local northSq = currTile1:getN()
                local southSq = currTile2:getS()
                
                local northTerrain = DumpTruck.getBlendNaturalSprite(northSq)
                local southTerrain = DumpTruck.getBlendNaturalSprite(southSq)

                if northTerrain then
                    local northBlend = DumpTruck.getBlendOverlayFromOffset("NORTH", northTerrain)
                    if northBlend then
                        local obj = IsoObject.new(getCell(), currTile1, northBlend)
                        currTile1:AddTileObject(obj)
                    end
                end

                if southTerrain then
                    local southBlend = DumpTruck.getBlendOverlayFromOffset("SOUTH", southTerrain)
                    if southBlend then
                        local obj = IsoObject.new(getCell(), currTile2, southBlend)
                        currTile2:AddTileObject(obj)
                    end
                end
            end
        end
    else
        DumpTruck.debugPrint("Smoothing North/South")
        if fy > 0 then
            local northTile1HasGravel = DumpTruck.isPouredGravel(currTile1:getN())
            local northTile2HasGravel = DumpTruck.isPouredGravel(currTile2:getN())
            DumpTruck.debugPrint(string.format("North tiles gravel status: %s, %s", tostring(northTile1HasGravel), tostring(northTile2HasGravel)))

            if northTile1HasGravel and not northTile2HasGravel then
                DumpTruck.debugPrint("Left tile has north gravel, right doesn't")
                DumpTruck.placeTileOverlay(currTile2, 0, -1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.WEST)
                DumpTruck.placeTileOverlay(currTile1, -1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.EAST)
            elseif not northTile1HasGravel and northTile2HasGravel then
                DumpTruck.debugPrint("Right tile has north gravel, left doesn't")
                DumpTruck.placeTileOverlay(currTile1, 0, -1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.SOUTH)
                DumpTruck.placeTileOverlay(currTile2, 1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.NORTH)
            else
                DumpTruck.debugPrint("No fillers needed. Both north tiles are consistent.")
                -- Add terrain blending for aligned N/S road
                local westSq = currTile1:getW()
                local eastSq = currTile2:getE()
                
                local westTerrain = DumpTruck.getBlendNaturalSprite(westSq)
                local eastTerrain = DumpTruck.getBlendNaturalSprite(eastSq)

                if westTerrain then
                    local westBlend = DumpTruck.getBlendOverlayFromOffset("WEST", westTerrain)
                    if westBlend then
                        local obj = IsoObject.new(getCell(), currTile1, westBlend)
                        currTile1:AddTileObject(obj)
                    end
                end

                if eastTerrain then
                    local eastBlend = DumpTruck.getBlendOverlayFromOffset("EAST", eastTerrain)
                    if eastBlend then
                        local obj = IsoObject.new(getCell(), currTile2, eastBlend)
                        currTile2:AddTileObject(obj)
                    end
                end
            end
        else
            local southTile1HasGravel = DumpTruck.isPouredGravel(currTile1:getS())
            local southTile2HasGravel = DumpTruck.isPouredGravel(currTile2:getS())
            DumpTruck.debugPrint(string.format("South tiles gravel status: %s, %s", tostring(southTile1HasGravel), tostring(southTile2HasGravel)))

            if southTile1HasGravel and not southTile2HasGravel then
                DumpTruck.debugPrint("Left tile has south gravel, right doesn't")
                DumpTruck.placeTileOverlay(currTile2, 0, 1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.NORTH)
                DumpTruck.placeTileOverlay(currTile1, -1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.SOUTH)
            elseif not southTile1HasGravel and southTile2HasGravel then
                DumpTruck.debugPrint("Right tile has south gravel, left doesn't")
                DumpTruck.placeTileOverlay(currTile1, 0, 1, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.EAST)
                DumpTruck.placeTileOverlay(currTile2, 1, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES.WEST)
            else
                DumpTruck.debugPrint("No fillers needed. Both south tiles are consistent.")
                -- Add terrain blending for aligned N/S road
                local westSq = currTile1:getW()
                local eastSq = currTile2:getE()
                
                local westTerrain = DumpTruck.getBlendNaturalSprite(westSq)
                local eastTerrain = DumpTruck.getBlendNaturalSprite(eastSq)

                if westTerrain then
                    local westBlend = DumpTruck.getBlendOverlayFromOffset("WEST", westTerrain)
                    if westBlend then
                        local obj = IsoObject.new(getCell(), currTile1, westBlend)
                        currTile1:AddTileObject(obj)
                    end
                end

                if eastTerrain then
                    local eastBlend = DumpTruck.getBlendOverlayFromOffset("EAST", eastTerrain)
                    if eastBlend then
                        local obj = IsoObject.new(getCell(), currTile2, eastBlend)
                        currTile2:AddTileObject(obj)
                    end
                end
            end
        end
    end
end


-- GRAVEL

function DumpTruck.placeGravelFloorOnTile(sprite, sq)
    DumpTruck.removeOppositeEdgeBlends(sq)
    
    local newFloor = sq:addFloor(sprite)
    
    local modData = newFloor:getModData()
    modData.pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
    modData.pourable = true
    modData.removable = true
    
    -- Disable erosion on this square (single player implementation)
    sq:disableErosion()
    
    sq:RecalcProperties()
    sq:DirtySlice()
    if isClient() then
        sq:transmitFloor()
    end
    DumpTruck.debugPrint(string.format("Placed gravel on square (%d, %d, %d).", sq:getX(), sq:getY(), sq:getZ()))
end

function DumpTruck.consumeGravelFromTruckBed(vehicle)
    if DumpTruck.debugMode then
        return true
    end

    local truckBed = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if not truckBed or not truckBed:getItemContainer() then
        DumpTruck.debugPrint("No truck bed or no container found.")
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
                DumpTruck.debugPrint(string.format("Consumed gravel from bag. Remaining uses: %d.", newCount))
                if newCount <= 0 then
                    DumpTruck.debugPrint("Bag is empty. Replacing with an EmptySandbag.")
                    container:Remove(item)
                    container:AddItem("Base.EmptySandbag")
                end
                container:setDrawDirty(true)
                return true
            end
        end
    end

    DumpTruck.debugPrint("No gravel bag found or all bags are empty.")
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
    DumpTruck.debugPrint(string.format("Total gravel uses available: %d.", totalUses))
    return totalUses
end

-- ROAD BUILDING

function DumpTruck.getBackSquares(fx, fy, cx, cy, cz, width, length)
    DumpTruck.debugPrint(string.format("Vehicle Position: cx=%.3f, cy=%.3f, cz=%d.", cx, cy, cz))

    local halfWidth = width / 2
    local backDistance = length / 2

    -- Floor the position first
    local flooredX = math.floor(cx)
    local flooredY = math.floor(cy)

    local backSquares = {}
    -- Check if more east/west or north/south
    if DumpTruck.getPrimaryAxis(fx, fy) == DumpTruckConstants.AXIS.X then
        -- Facing East/West
        local offsetX = (fx > 0) and -backDistance or backDistance
        DumpTruck.debugPrint(string.format("Direction: East/West. OffsetX=%d.", offsetX))
        for i = -halfWidth, halfWidth - 1 do
            local tileX = flooredX + offsetX
            local tileY = flooredY + i
            local square = getCell():getGridSquare(tileX, tileY, cz)
            if square then
                table.insert(backSquares, square)
            end
        end
    else
        -- North/South
        local offsetY = (fy > 0) and -backDistance or backDistance
        DumpTruck.debugPrint(string.format("Direction: North/South. OffsetY=%d.", offsetY))
        for i = -halfWidth, halfWidth - 1 do
            local tileX = flooredX + i
            local tileY = flooredY + offsetY
            local square = getCell():getGridSquare(tileX, tileY, cz)
            if square then
                table.insert(backSquares, square)
            end
        end
    end
    return backSquares
end

local oldX, oldY = 0, 0
-- Modify tryPourGravelUnderTruck to handle transitions
function DumpTruck.tryPourGravelUnderTruck(vehicle)
    if not vehicle or vehicle:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then return end

    local data = vehicle:getModData()
    if not data.dumpingGravelActive then return end  -- Only proceed if dumping is active

    local cx, cy, cz = vehicle:getX(), vehicle:getY(), vehicle:getZ()
    cz = 0 -- Assume ground level for simplicity

    if math.floor(cx) == oldX and math.floor(cy) == oldY then return end
    oldX, oldY = math.floor(cx), math.floor(cy)

    local fx, fy = DumpTruck.getVectorFromPlayer(vehicle)

    local script = vehicle:getScript()
    local extents = script:getExtents()
    local width = math.floor(extents:x() + 0.5)
    local length = math.floor(extents:z() + 0.5)
    
    local currentSquares = DumpTruck.getBackSquares(fx, fy, cx, cy, cz, width, length)
    
    -- First check if all tiles are valid
    for _, square in ipairs(currentSquares) do
        if not square or not DumpTruck.isSquareValidForGravel(square) then
            return -- If any tile is invalid, don't place any gravel
        end
    end

    -- If we got here, all tiles are valid, so place gravel on them
    for _, sq in ipairs(currentSquares) do
        if DumpTruck.getGravelCount(vehicle) <= 0 then
            data.dumpingGravelActive = false
            return
        end
        DumpTruck.placeGravelFloorOnTile(DumpTruckConstants.GRAVEL_SPRITE, sq)
        DumpTruck.consumeGravelFromTruckBed(vehicle)
    end

    -- Check and place blend tiles if there are previous tiles
    DumpTruck.smoothRoad(currentSquares, fx, fy)
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

-- Toggle gravel dumping based on key press
function DumpTruck.toggleGravelDumping(key)
    if key == DumpTruckConstants.DUMP_KEY then
        local playerObj = getSpecificPlayer(0)
        if not playerObj then return end
        local vehicle = playerObj:getVehicle()
        if vehicle and vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
            local data = vehicle:getModData()
            data.dumpingGravelActive = not data.dumpingGravelActive
            
            -- Set speed limit based on dumping state
            if data.dumpingGravelActive then
                vehicle:setMaxSpeed(DumpTruckConstants.MAX_DUMP_SPEED)
            else
                vehicle:setMaxSpeed(DumpTruckConstants.DEFAULT_MAX_SPEED)
            end
        end
    end
end
-- Event bindings
Events.OnKeyPressed.Add(DumpTruck.toggleGravelDumping)






