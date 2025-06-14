local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

DumpTruck = {}
DumpTruck.debugMode = true

-- Constants
local DIRECTION_STABILITY_THRESHOLD = 2  -- Number of consistent direction checks needed
local directionHistory = {}  -- Will store {direction, x, y} entries
local stableDirection = nil  -- Our current stable direction
local startX, startY = nil, nil  -- Initialize to nil so we know it's not set yet
local hasUpdatedStartPoint = false

-- Data structure to track the current line of gravel
local currentLine = {
    squares = {}  -- Will store {square, originalSprite} entries
}

-- Function to clear the current line data
function DumpTruck.clearCurrentLine()
    currentLine.squares = {}
end

-- Function to add a square to the current line
function DumpTruck.addToCurrentLine(square, originalSprite)
    table.insert(currentLine.squares, {
        square = square,
        originalSprite = originalSprite
    })

end

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

-- Check if a tile is a full gravel floor (not a blend)
function DumpTruck.isFullGravelFloor(tile)
    if not tile then return false end
    local floor = tile:getFloor()
    return floor and 
           floor:getSprite():getName() == DumpTruckConstants.GRAVEL_SPRITE and
           floor:getModData().pouredFloor == DumpTruckConstants.POURED_FLOOR_TYPE
end

-- Check if square is valid for gravel
function DumpTruck.isSquareValidForGravel(sq)
    if not sq then
        DumpTruck.debugPrint("Square is nil.")
        return false
    end
    if CFarmingSystem and CFarmingSystem.instance:getLuaObjectOnSquare(sq) then
        return false
    end
    if sq:getProperties() and sq:getProperties():Is(IsoFlagType.water) then
        return false
    end
    if DumpTruck.isPouredGravel(sq) then
        return false
    end
    return true
end


-- get vehicle vector 
-- function DumpTruck.getVector(vehicle)
--     local dir = vehicle:getDir()
--     local fx = dir:dx()
--     local fy = dir:dy()
--     DumpTruck.debugPrint(string.format("Vehicle Vector: fx=%.3f, fy=%.3f.", fx, fy))
--     return fx, fy
-- end

function DumpTruck.getVectorFromPlayer(vehicle)
    -- Get the driver of the vehicle
    local driver = vehicle:getDriver()
    if driver == nil then
        return nil, nil
    end

    -- Get the driver's forward direction as a vector
    local vector = Vector2.new()
    driver:getForwardDirection(vector)

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
        return 
    end
    
    DumpTruck.debugPrint(string.format("removeOppositeEdgeBlends: Checking square (%d,%d)", square:getX(), square:getY()))
    
    -- Check each direction
    local adjacentChecks = {
        {square = square:getN(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.SOUTH, dir = "North"},
        {square = square:getS(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.NORTH, dir = "South"},
        {square = square:getE(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.WEST, dir = "East"},
        {square = square:getW(), oppositeSprites = DumpTruckConstants.DIRECTION_OFFSETS.EAST, dir = "West"}
    }
    
    for _, check in ipairs(adjacentChecks) do
        if check and check.square then
            DumpTruck.debugPrint(string.format("removeOppositeEdgeBlends: Checking %s tile at (%d,%d)", 
                check.dir, check.square:getX(), check.square:getY()))
            local objects = check.square:getObjects()
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if obj then
                    local spriteName = obj:getSpriteName()

                    if spriteName then
                        -- Extract the base number from the sprite name
                        if spriteName:find("^blends_natural_01_") then
                            local baseNumber = tonumber(spriteName:match("blends_natural_01_(%d+)"))
                            if baseNumber then
                                local baseRow = math.floor(baseNumber / 16)
                                local rowStartTile = baseRow * 16
                                
                                DumpTruck.debugPrint(string.format("removeOppositeEdgeBlends: Found blend sprite %s (baseNumber=%d, rowStartTile=%d)", 
                                    spriteName, baseNumber, rowStartTile))
                                
                                -- Check if the sprite matches any of the opposite sprites we want to remove
                                local shouldRemove = false
                                for _, oppositeOffset in ipairs(check.oppositeSprites) do
                                    local oppositeSprite = rowStartTile + oppositeOffset
                                    DumpTruck.debugPrint(string.format("removeOppositeEdgeBlends: Comparing baseNumber %d with oppositeSprite %d (rowStartTile %d + offset %d)", 
                                        baseNumber, oppositeSprite, rowStartTile, oppositeOffset))
                                    if baseNumber == oppositeSprite then
                                        shouldRemove = true
                                        DumpTruck.debugPrint(string.format("removeOppositeEdgeBlends: Match found! Removing sprite %s", spriteName))
                                        break
                                    end
                                end
                                
                                if shouldRemove then
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
        return nil
    end
    
    -- Extract the base number from the sprite name
    local baseNumber = tonumber(terrainBlock:match("blends_natural_01_(%d+)"))
    if not baseNumber then
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
    
    return "blends_natural_01_" .. overlayTile
end

function DumpTruck.placeTileOverlay(targetSquare, sprite)
    if not targetSquare then
        DumpTruck.debugPrint(string.format("placeTileOverlay: Target square is nil at (%d,%d)", 
            targetSquare:getX(), targetSquare:getY()))
        return
    end
    
    -- Only check for valid gravel placement if this is not a blend tile
    if not sprite:find("blends_natural_01") then
        if not DumpTruck.isSquareValidForGravel(targetSquare) then
            DumpTruck.debugPrint(string.format("placeTileOverlay: Square not valid for gravel at (%d,%d)", 
                targetSquare:getX(), targetSquare:getY()))
            return
        end
    end

    -- Check for existing overlay
    local existingObjects = targetSquare:getObjects()
    for i = 0, existingObjects:size() - 1 do
        local obj = existingObjects:get(i)
        if obj:getSpriteName() == sprite then
            DumpTruck.debugPrint(string.format("placeTileOverlay: Tile already exists at (%d,%d)", 
                targetSquare:getX(), targetSquare:getY()))
            return
        end
    end

    DumpTruck.debugPrint(string.format("placeTileOverlay: Placing tile %s at (%d,%d)", 
        sprite, targetSquare:getX(), targetSquare:getY()))



    -- Set floor metadata
    local floor = targetSquare:getFloor()
    if floor then
        if sprite:find("blends_natural_01") then
            floor:getModData().isEdgeBlend = true
        else
            floor:getModData().pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
            floor:getModData().isGapFiller = true
        end
    end

    -- Add the overlay
    local overlay = IsoObject.new(getCell(), targetSquare, sprite)
    targetSquare:AddTileObject(overlay)
    targetSquare:RecalcProperties()
    targetSquare:DirtySlice()

    DumpTruck.removeOppositeEdgeBlends(targetSquare)
    
    -- Log successful placement
    DumpTruck.debugPrint(string.format("placeTileOverlay: Successfully placed tile %s at (%d,%d)", 
        sprite, targetSquare:getX(), targetSquare:getY()))
end


--[[
    smoothRoad: Adds blend tiles to smooth the transition between gravel and other terrain
    Input:
        currentSquares: array of IsoGridSquare - The current row of gravel tiles
        fx: number - Forward vector X component (direction of travel)
        fy: number - Forward vector Y component (direction of travel)
    Output: None (modifies tiles directly)
]]
function DumpTruck.addEdgeBlends(leftTile, rightTile)
    if not leftTile or not rightTile then 
        DumpTruck.debugPrint("addEdgeBlends: Invalid input tiles")
        return 
    end
    
    DumpTruck.debugPrint(string.format("addEdgeBlends: Checking tiles - left(%d,%d) right(%d,%d)", 
        leftTile:getX(), leftTile:getY(), rightTile:getX(), rightTile:getY()))
    
    local secondaryDir
    if leftTile:getX() == rightTile:getX() then
        -- For east-west roads, determine which direction to use based on Y coordinates
        if leftTile:getY() > rightTile:getY() then
            -- Going west: left tile is south, right tile is north
            secondaryDir = {"SOUTH", "NORTH"}
            DumpTruck.debugPrint("addEdgeBlends: Going west - left tile is south, right tile is north")
        else
            -- Going east: left tile is north, right tile is south
            secondaryDir = {"NORTH", "SOUTH"}
            DumpTruck.debugPrint("addEdgeBlends: Going east - left tile is north, right tile is south")
        end
    else
        -- For north-south roads, determine which direction to use based on X coordinates
        if leftTile:getX() < rightTile:getX() then
            -- Going south: left tile is west, right tile is east
            secondaryDir = {"WEST", "EAST"}
            DumpTruck.debugPrint("addEdgeBlends: Going south - left tile is west, right tile is east")
        else
            -- Going north: left tile is east, right tile is west
            secondaryDir = {"EAST", "WEST"}
            DumpTruck.debugPrint("addEdgeBlends: Going north - left tile is east, right tile is west")
        end
    end
    
    -- Get the adjacent tiles for edge blending
    local leftSideTile, rightSideTile
    if secondaryDir[1] == "NORTH" then
        leftSideTile = leftTile:getN()
    elseif secondaryDir[1] == "SOUTH" then
        leftSideTile = leftTile:getS()
    elseif secondaryDir[1] == "EAST" then
        leftSideTile = leftTile:getE()
    elseif secondaryDir[1] == "WEST" then
        leftSideTile = leftTile:getW()
    end
    
    if secondaryDir[2] == "NORTH" then
        rightSideTile = rightTile:getN()
    elseif secondaryDir[2] == "SOUTH" then
        rightSideTile = rightTile:getS()
    elseif secondaryDir[2] == "EAST" then
        rightSideTile = rightTile:getE()
    elseif secondaryDir[2] == "WEST" then
        rightSideTile = rightTile:getW()
    end
    
    DumpTruck.debugPrint(string.format("addEdgeBlends: Adjacent tiles - leftSide(%d,%d) rightSide(%d,%d)", 
        leftSideTile and leftSideTile:getX() or -1, leftSideTile and leftSideTile:getY() or -1,
        rightSideTile and rightSideTile:getX() or -1, rightSideTile and rightSideTile:getY() or -1))
    
    -- Add terrain blends for outer edges
    for i, tile in ipairs({leftTile, rightTile}) do
        local sideTile = i == 1 and leftSideTile or rightSideTile
        local sideDir = i == 1 and secondaryDir[1] or secondaryDir[2]
        
        DumpTruck.debugPrint(string.format("addEdgeBlends: Processing %s edge - tile(%d,%d) sideTile(%d,%d) direction %s", 
            i == 1 and "left" or "right",
            tile:getX(), tile:getY(),
            sideTile and sideTile:getX() or -1, sideTile and sideTile:getY() or -1,
            sideDir))
        
        if sideTile then
            local terrain = DumpTruck.getBlendNaturalSprite(sideTile)
            DumpTruck.debugPrint(string.format("addEdgeBlends: Found terrain sprite: %s", terrain or "none"))
            
            if terrain then
                local blend = DumpTruck.getBlendOverlayFromOffset(sideDir, terrain)
                DumpTruck.debugPrint(string.format("addEdgeBlends: Generated blend sprite: %s", blend or "none"))
                
                if blend then
                    DumpTruck.placeTileOverlay(tile, blend)
                end
            end
        else
            DumpTruck.debugPrint(string.format("addEdgeBlends: No side tile found for %s edge", i == 1 and "left" or "right"))
        end
    end
end

-- Check if a grass tile adjacent to a gravel tile forms a corner pattern
function DumpTruck.checkForCornerPattern(gravelTile)
    if not gravelTile or not DumpTruck.isFullGravelFloor(gravelTile) then
        DumpTruck.debugPrint("checkForCornerPattern: Invalid gravel tile input")
        return nil, nil
    end

    -- Verify mapping table is loaded
    if not DumpTruckConstants.ADJACENT_TO_BLEND_MAPPING then
        DumpTruck.debugPrint("ERROR: ADJACENT_TO_BLEND_MAPPING is not loaded!")
        return nil, nil
    end

    -- Check each adjacent tile
    local adjacentChecks = {
        {tile = gravelTile:getN(), dir = "NORTH", opposite = "SOUTH"},
        {tile = gravelTile:getS(), dir = "SOUTH", opposite = "NORTH"},
        {tile = gravelTile:getE(), dir = "EAST", opposite = "WEST"},
        {tile = gravelTile:getW(), dir = "WEST", opposite = "EAST"}
    }

    for _, check in ipairs(adjacentChecks) do
        local adjacentTile = check.tile
        if adjacentTile and not DumpTruck.isPouredGravel(adjacentTile) then
            -- Found a non-gravel tile, check its other adjacent tiles
            local otherAdjacentChecks = {
                {tile = adjacentTile:getN(), dir = "NORTH"},
                {tile = adjacentTile:getS(), dir = "SOUTH"},
                {tile = adjacentTile:getE(), dir = "EAST"},
                {tile = adjacentTile:getW(), dir = "WEST"}
            }

            local gravelCount = 0
            local gravelDirections = {}

            -- First add the direction FROM the grass tile TO the original gravel tile
            -- This is the opposite of how we found the grass tile
            table.insert(gravelDirections, check.opposite)
            DumpTruck.debugPrint(string.format("Added gravel direction %s (from grass to original gravel)", check.opposite))

            -- Then check other adjacent tiles from the grass tile's perspective
            for _, otherCheck in ipairs(otherAdjacentChecks) do
                -- Skip the direction that points back to our original gravel tile
                if otherCheck.dir ~= check.opposite then
                    if otherCheck.tile and DumpTruck.isFullGravelFloor(otherCheck.tile) then
                        gravelCount = gravelCount + 1
                        table.insert(gravelDirections, otherCheck.dir)
                        DumpTruck.debugPrint(string.format("Found gravel tile in direction %s (from grass)", otherCheck.dir))
                    end
                end
            end

            -- If we found exactly one other gravel floor tile, we have a corner pattern
            if gravelCount == 1 then
                DumpTruck.debugPrint(string.format("Total gravel directions: %s, %s", gravelDirections[1], gravelDirections[2]))
                
                -- Look up the appropriate blend tile in our mapping
                DumpTruck.debugPrint("Starting mapping lookup...")
                for i, mapping in ipairs(DumpTruckConstants.ADJACENT_TO_BLEND_MAPPING) do
                    DumpTruck.debugPrint(string.format("Checking mapping entry %d", i))
                    if not mapping then
                        DumpTruck.debugPrint("ERROR: mapping entry is nil!")
                        return nil, nil
                    end
                    if not mapping.adjacent_directions then
                        DumpTruck.debugPrint("ERROR: mapping.adjacent_directions is nil!")
                        return nil, nil
                    end
                    local directions = mapping.adjacent_directions
                    -- Only print debug info after we know directions exists
                    DumpTruck.debugPrint(string.format("Checking mapping: %s, %s -> %s", 
                        directions[1], directions[2], mapping.blend_direction))
                    
                    -- Check if our gravel directions match this mapping (order doesn't matter)
                    if (gravelDirections[1] == directions[1] and gravelDirections[2] == directions[2]) or
                       (gravelDirections[1] == directions[2] and gravelDirections[2] == directions[1]) then
                        local blendTile = DumpTruckConstants.GRAVEL_BLEND_TILES[mapping.blend_direction]
                        if not blendTile then
                            DumpTruck.debugPrint(string.format("ERROR: No blend tile found for direction %s", mapping.blend_direction))
                            return nil, nil
                        end
                        DumpTruck.debugPrint(string.format("Found corner pattern at (%d,%d): gravel tiles to %s and %s, using blend tile %s", 
                            adjacentTile:getX(), adjacentTile:getY(), gravelDirections[1], gravelDirections[2], blendTile))
                        return adjacentTile, blendTile
                    end
                end
                DumpTruck.debugPrint("No matching mapping found for directions")
            end
        end
    end

    return nil, nil
end

function DumpTruck.fillGaps(leftTile, rightTile)
    local adjacentTile1, blendTile1 = DumpTruck.checkForCornerPattern(leftTile)
    local adjacentTile2, blendTile2 = DumpTruck.checkForCornerPattern(rightTile)

    if adjacentTile1 and blendTile1 then
        DumpTruck.debugPrint(string.format("fillGaps: Found corner pattern at (%d,%d) for left tile, using blend tile %s", 
            adjacentTile1:getX(), adjacentTile1:getY(), blendTile1))
        DumpTruck.placeTileOverlay(adjacentTile1, blendTile1)
    end

    if adjacentTile2 and blendTile2 then
        DumpTruck.debugPrint(string.format("fillGaps: Found corner pattern at (%d,%d) for right tile, using blend tile %s", 
            adjacentTile2:getX(), adjacentTile2:getY(), blendTile2))
        DumpTruck.placeTileOverlay(adjacentTile2, blendTile2)
    end
end

function DumpTruck.smoothRoad(currentSquares, fx, fy)
    if #currentSquares < 2 then
        DumpTruck.debugPrint("Error: Need at least 2 tiles to smooth.")
        return
    end

    local cz = currentSquares[1]:getZ()
    
    -- Only check the outer edges of the road
    local leftTile = currentSquares[1]
    local rightTile = currentSquares[#currentSquares]
    
    -- Fill gaps and add edge blends
    DumpTruck.addEdgeBlends(leftTile, rightTile)
    DumpTruck.fillGaps(leftTile, rightTile)
end


-- GRAVEL

function DumpTruck.placeGravelFloorOnTile(sprite, sq)
    -- Store the original floor sprite before replacing it
    local originalSprite = nil
    local originalFloor = sq:getFloor()
    if originalFloor then
        originalSprite = originalFloor:getSprite():getName()
    end
    
    -- Add to our current line tracking before placing new floor
    DumpTruck.addToCurrentLine(sq, originalSprite)
    
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

    -- Log successful placement
    DumpTruck.debugPrint(string.format("placeGravelFloorOnTile: Successfully placed gravel floor at (%d,%d)", 
        sq:getX(), sq:getY()))
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
    getBackSquares2: Gets the squares behind the truck for gravel placement
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
function DumpTruck.getBackSquares2(fx, fy, cx, cy, cz, width, length)
    
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
    cz = 0 -- Assume ground level for simplicity

    if math.floor(cx) == oldX and math.floor(cy) == oldY then return end
    oldX, oldY = math.floor(cx), math.floor(cy)

    local fx, fy = DumpTruck.getVectorFromPlayer(vehicle)

    local script = vehicle:getScript()
    local extents = script:getExtents()
    local width = math.floor(extents:x() + 0.5)
    local length = math.floor(extents:z() + 0.5)
    
    local currentSquares = DumpTruck.getBackSquares2(fx, fy, cx, cy, cz, 3, length)
    
    -- Debug print current squares
    DumpTruck.debugPrint("tryPourGravelUnderTruck: Current squares to process:")
    for i, sq in ipairs(currentSquares) do
        DumpTruck.debugPrint(string.format("  Square %d: (%d,%d)", i, sq:getX(), sq:getY()))
    end
    
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
            startX, startY = nil, nil  -- Reset start point
            DumpTruck.clearCurrentLine()
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







