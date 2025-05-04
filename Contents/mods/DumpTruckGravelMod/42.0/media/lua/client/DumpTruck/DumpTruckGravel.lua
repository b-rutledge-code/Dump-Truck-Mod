local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

DumpTruck = {}
DumpTruck.debugMode = true

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

local oldDirection = nil
local startX, startY = nil, nil  -- Initialize to nil so we know it's not set yet
local directionStabilityCount = 0
local DIRECTION_STABILITY_THRESHOLD = 3  -- Number of cycles direction must be stable
local hasUpdatedStartPoint = false

function DumpTruck.getBackSquares(fx, fy, cx, cy, cz, width, length)
    DumpTruck.debugPrint(string.format("Vehicle Position: cx=%.3f, cy=%.3f, cz=%d.", cx, cy, cz))

    local currentDirection = DumpTruck.getDirection(fx, fy)
    DumpTruck.debugPrint(string.format("Current direction: %s", currentDirection))

    -- Initialize start point if not set
    if startX == nil or startY == nil then
        startX = cx
        startY = cy
        hasUpdatedStartPoint = false
        DumpTruck.debugPrint(string.format("Initializing start point to (%d, %d)", startX, startY))
    end

    -- Check if direction has changed
    if currentDirection ~= oldDirection then
        directionStabilityCount = 0
        oldDirection = currentDirection
        -- Update start point immediately when direction changes
        startX = cx
        startY = cy
        hasUpdatedStartPoint = false
        DumpTruck.debugPrint(string.format("Direction changed to %s, updating start point to (%d, %d)", currentDirection, startX, startY))
    else
        directionStabilityCount = directionStabilityCount + 1
        DumpTruck.debugPrint(string.format("Direction stable for %d cycles", directionStabilityCount))
        -- Update start point every few cycles when direction is stable
        if directionStabilityCount >= 3 then
            startX = cx
            startY = cy
            hasUpdatedStartPoint = false
            directionStabilityCount = 0
            DumpTruck.debugPrint(string.format("Updating start point to (%d, %d)", startX, startY))
        end
    end

    local halfWidth = width / 2

    -- Use current vehicle position as end point
    local endX = cx
    local endY = cy

    -- Get points along the thick line
    local points = DumpTruck.drawThickLineCircle(startX, startY, endX, endY, halfWidth)

    -- Convert points to squares
    local backSquares = {}
    for _, point in ipairs(points) do
        local square = getCell():getGridSquare(point.x, point.y, cz)
        if square then
            DumpTruck.debugPrint(string.format("Placing tile at (%d, %d)", point.x, point.y))
            table.insert(backSquares, square)
        end
    end

    hasUpdatedStartPoint = true
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
    
    -- Place gravel on valid squares, skipping ones that already have gravel
    for _, sq in ipairs(currentSquares) do
        if sq and DumpTruck.isSquareValidForGravel(sq) then
            if DumpTruck.getGravelCount(vehicle) <= 0 then
                data.dumpingGravelActive = false
                return
            end
            DumpTruck.placeGravelFloorOnTile(DumpTruckConstants.GRAVEL_SPRITE, sq)
            DumpTruck.consumeGravelFromTruckBed(vehicle)
        end
    end
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

function DumpTruck.drawLine(x0, y0, x1, y1)
    -- Convert to integers for consistent behavior
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
    
    DumpTruck.debugPrint(string.format("drawLine: start=(%d, %d), end=(%d, %d)", x0, y0, x1, y1))
    
    -- Early validation
    if x0 == x1 and y0 == y1 then
        DumpTruck.debugPrint("Zero-length line detected, returning single point")
        return {{x = x0, y = y0}}
    end
    
    local points = {}
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy
    
    -- Calculate maximum possible points to prevent infinite loops
    local maxPoints = dx + dy + 1
    local iterations = 0
    
    while true do
        iterations = iterations + 1
        if iterations > maxPoints then
            DumpTruck.debugPrint("Too many iterations, breaking")
            break
        end
        
        table.insert(points, {x = x0, y = y0})
        
        if x0 == x1 and y0 == y1 then
            break
        end
        
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x0 = x0 + sx
        end
        if e2 < dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
    
    DumpTruck.debugPrint(string.format("drawLine complete: %d points", #points))
    return points
end

function DumpTruck.drawThickLineCircle(x0, y0, x1, y1, thickness)
    -- Convert to integers for consistent behavior
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
    thickness = math.floor(thickness)
    
    DumpTruck.debugPrint(string.format("drawThickLineCircle: start=(%d, %d), end=(%d, %d), thickness=%d", x0, y0, x1, y1, thickness))
    
    -- Early validation
    if thickness <= 0 then
        DumpTruck.debugPrint("Invalid thickness, returning single point")
        return {{x = x0, y = y0}}
    end
    
    if x0 == x1 and y0 == y1 then
        DumpTruck.debugPrint("Zero-length line detected, returning single point")
        return {{x = x0, y = y0}}
    end
    
    -- First get the base line points
    local baseLine = DumpTruck.drawLine(x0, y0, x1, y1)
    if #baseLine == 0 then
        DumpTruck.debugPrint("No base line points generated")
        return {{x = x0, y = y0}}
    end
    
    local radius = math.ceil(thickness / 2)
    local thickPoints = {}
    local seen = {}
    
    -- Optimize circle generation by only checking points within the square bounds
    for i, point in ipairs(baseLine) do
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- Use squared distance for better performance
                if dx*dx + dy*dy <= radius*radius then
                    local newX = point.x + dx
                    local newY = point.y + dy
                    local key = newX .. "," .. newY
                    
                    if not seen[key] then
                        seen[key] = true
                        table.insert(thickPoints, {x = newX, y = newY})
                    end
                end
            end
        end
    end
    
    DumpTruck.debugPrint(string.format("Total thick points: %d", #thickPoints))
    return thickPoints
end

function DumpTruck.getDirection(fx, fy)
    local angle = math.atan2(fx, -fy)  -- This will give us 0 degrees at North
    local degrees = math.deg(angle)
    if degrees < 0 then degrees = degrees + 360 end
    
    -- Convert to 8 directions with 0 degrees at North
    local directions = {
        [0] = "N",    -- 0 degrees (North)
        [45] = "NE",  -- 45 degrees
        [90] = "E",   -- 90 degrees
        [135] = "SE", -- 135 degrees
        [180] = "S",  -- 180 degrees
        [225] = "SW", -- 225 degrees
        [270] = "W",  -- 270 degrees
        [315] = "NW"  -- 315 degrees
    }
    
    -- Find the closest direction
    local closest = 0
    local minDiff = 360
    for dir, _ in pairs(directions) do
        local diff = math.abs(degrees - dir)
        if diff < minDiff then
            minDiff = diff
            closest = dir
        end
    end
    
    return directions[closest]
end






