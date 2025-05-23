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
    DumpTruck.debugPrint("Cleared current line data")
end

-- Function to add a square to the current line
function DumpTruck.addToCurrentLine(square, originalSprite)
    table.insert(currentLine.squares, {
        square = square,
        originalSprite = originalSprite
    })
    DumpTruck.debugPrint(string.format("Added square (%d, %d) to current line with original sprite: %s", 
        square:getX(), square:getY(), originalSprite or "nil"))
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

-- Check if square is valid for gravel
function DumpTruck.isSquareValidForGravel(sq)
    if not sq then
        DumpTruck.debugPrint("Square is nil.")
        return false
    end
    if CFarmingSystem and CFarmingSystem.instance:getLuaObjectOnSquare(sq) then
        -- DumpTruck.debugPrint(string.format("Farming system object on square (%d, %d, %d).", sq:getX(), sq:getY(), sq:getZ()))
        return false
    end
    if sq:getProperties() and sq:getProperties():Is(IsoFlagType.water) then
        -- DumpTruck.debugPrint(string.format("Square (%d, %d, %d) is water.", sq:getX(), sq:getY(), sq:getZ()))
        return false
    end
    if DumpTruck.isPouredGravel(sq) then
        DumpTruck.debugPrint(string.format("Square (%d, %d, %d) already has poured gravel.", sq:getX(), sq:getY(), sq:getZ()))
        return false
    end
    return true
end

-- function DumpTruck.getPrimaryAxis(fx, fy)
--     -- Calculate the angle for debugging
--     local angle = math.deg(math.atan2(-fy, fx))
--     if angle < 0 then angle = angle + 360 end
--     DumpTruck.debugPrint(string.format("Movement angle: %.2f degrees", angle))
    
--     -- Original logic
--     if math.abs(fx) > math.abs(fy) * (1 + .2) then
--         return DumpTruckConstants.AXIS.X
--     else
--         return DumpTruckConstants.AXIS.Y
--     end
-- end

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
    DumpTruck.debugPrint("getBlendOverlayFromOffset ENTERED")
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


--[[
    smoothRoad: Adds blend tiles to smooth the transition between gravel and other terrain
    Input:
        currentSquares: array of IsoGridSquare - The current row of gravel tiles
        fx: number - Forward vector X component (direction of travel)
        fy: number - Forward vector Y component (direction of travel)
    Output: None (modifies tiles directly)
]]
function DumpTruck.smoothRoad(currentSquares, fx, fy)
    if #currentSquares < 2 then
        DumpTruck.debugPrint("Error: Need at least 2 tiles to smooth.")
        return
    end

    local cz = currentSquares[1]:getZ()
    
    -- Use forward vector to determine if we're going more horizontally or vertically
    local isEastWest = math.abs(fx) > math.abs(fy)
    
    -- Determine which cardinal direction we're going
    local primaryDir
    if isEastWest then
        primaryDir = fx > 0 and "WEST" or "EAST"  -- If going East (positive X), check West tiles
    else
        primaryDir = fy > 0 and "NORTH" or "SOUTH"  -- If going South (positive Y), check North tiles
    end
    local secondaryDir = isEastWest and {"NORTH", "SOUTH"} or {"EAST", "WEST"}
    
    -- Get the adjacent tiles to check
    local getAdjacentTile = function(tile, dir) return tile["get" .. dir:sub(1,1)](tile) end
    
    -- Only check the outer edges of the road
    local leftTile = currentSquares[1]
    local rightTile = currentSquares[#currentSquares]
    
    -- Check gravel status for outer edges
    local leftAdjacent = getAdjacentTile(leftTile, primaryDir)
    local rightAdjacent = getAdjacentTile(rightTile, primaryDir)
    local leftHasGravel = DumpTruck.isPouredGravel(leftAdjacent)
    local rightHasGravel = DumpTruck.isPouredGravel(rightAdjacent)
    
    DumpTruck.debugPrint(string.format("Left edge: %s adjacent has gravel: %s", primaryDir, tostring(leftHasGravel)))
    DumpTruck.debugPrint(string.format("Right edge: %s adjacent has gravel: %s", primaryDir, tostring(rightHasGravel)))
    
    -- Handle gap filling for left edge
    if leftHasGravel then
        DumpTruck.debugPrint(string.format("Left edge has %s gravel, applying blend", primaryDir))
        DumpTruck.placeTileOverlay(leftTile, 0, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES[primaryDir])
    end
    
    -- Handle gap filling for right edge
    if rightHasGravel then
        DumpTruck.debugPrint(string.format("Right edge has %s gravel, applying blend", primaryDir))
        DumpTruck.placeTileOverlay(rightTile, 0, 0, cz, DumpTruckConstants.GRAVEL_BLEND_TILES[primaryDir])
    end
    
    -- Add terrain blending for the sides
    local leftSideTile = getAdjacentTile(leftTile, secondaryDir[1])
    local rightSideTile = getAdjacentTile(rightTile, secondaryDir[2])
    
    -- Add terrain blends for outer edges
    for i, tile in ipairs({leftTile, rightTile}) do
        local sideTile = i == 1 and leftSideTile or rightSideTile
        local sideDir = i == 1 and secondaryDir[1] or secondaryDir[2]
        DumpTruck.debugPrint(string.format("Checking side tile %d at (%d, %d)", i, sideTile:getX(), sideTile:getY()))
        local terrain = DumpTruck.getBlendNaturalSprite(sideTile)
        if terrain then
            DumpTruck.debugPrint(string.format("About to call getBlendOverlayFromOffset with dir=%s, terrain=%s", sideDir, terrain))
            local blend = DumpTruck.getBlendOverlayFromOffset(sideDir, terrain)
            DumpTruck.debugPrint(string.format("blend is nil: %s", tostring(blend == nil)))
            if blend then
                local obj = IsoObject.new(getCell(), tile, blend)
                if obj then
                    tile:AddTileObject(obj)
                    tile:RecalcProperties()
                    tile:DirtySlice()
                end
            end
        else
            DumpTruck.debugPrint(string.format("No natural terrain found on side %d", i))
        end
    end
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
                -- DumpTruck.debugPrint(string.format("Consumed gravel from bag. Remaining uses: %d.", newCount))
                if newCount <= 0 then
                    -- DumpTruck.debugPrint("Bag is empty. Replacing with an EmptySandbag.")
                    container:Remove(item)
                    container:AddItem("Base.EmptySandbag")
                end
                container:setDrawDirty(true)
                return true
            end
        end
    end

    -- DumpTruck.debugPrint("No gravel bag found or all bags are empty.")
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
    -- DumpTruck.debugPrint(string.format("Total gravel uses available: %d.", totalUses))
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
    DumpTruck.debugPrint(string.format("Input vector: fx=%.3f, fy=%.3f", fx, fy))
    
    -- Calculate offset backwards along forward vector
    local offsetDistance = (length/2)  -- Half truck length plus 1 tile
    local offsetX = -fx * offsetDistance  -- Negative forward vector
    local offsetY = -fy * offsetDistance
    
    -- Apply offset to center point
    local centerX = cx + math.floor(offsetX + 0.5)  -- Round to nearest integer
    local centerY = cy + math.floor(offsetY + 0.5)
    
    DumpTruck.debugPrint(string.format("Original center: (%d, %d), Offset: (%.2f, %.2f), New center: (%d, %d)", 
        cx, cy, offsetX, offsetY, centerX, centerY))
    
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
    
    DumpTruck.debugPrint(string.format("Rounded perp vector: perpX=%d, perpY=%d", perpX, perpY))
    
    -- Generate points based on width
    local points = {}
    for i = 0, width - 1 do
        table.insert(points, {
            x = centerX + (perpX * i),
            y = centerY + (perpY * i),
            z = cz
        })
        DumpTruck.debugPrint(string.format("Point %d: (%d, %d)", i, centerX + (perpX * i), centerY + (perpY * i)))
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

function DumpTruck.getBackSquares(fx, fy, cx, cy, cz, width, length)
    local currentDirection = DumpTruck.getDirection(fx, fy)
    
    -- Initialize start point if not set
    if startX == nil or startY == nil then
        startX = cx
        startY = cy
        hasUpdatedStartPoint = false
        DumpTruck.debugPrint(string.format("Initializing start point to (%d, %d)", startX, startY))
    end

    -- Add new direction check to history
    table.insert(directionHistory, {direction = currentDirection, x = cx, y = cy})
    -- Keep only last N entries
    while #directionHistory > DIRECTION_STABILITY_THRESHOLD do
        table.remove(directionHistory, 1)
    end

    -- Debug log the current history
    DumpTruck.debugPrint(string.format("Current direction history (%d entries):", #directionHistory))
    for i, entry in ipairs(directionHistory) do
        DumpTruck.debugPrint(string.format("  Entry %d: direction=%s, pos=(%d, %d)", 
            i, entry.direction, entry.x, entry.y))
    end
    DumpTruck.debugPrint(string.format("Current stable direction: %s", stableDirection or "nil"))

    -- Only check for direction change if we have enough history
    if #directionHistory == DIRECTION_STABILITY_THRESHOLD then
        -- Check if all N entries in history are the same direction
        local allSameDirection = true
        local firstDirection = directionHistory[1].direction
        for i = 2, DIRECTION_STABILITY_THRESHOLD do
            if directionHistory[i].direction ~= firstDirection then
                allSameDirection = false
                DumpTruck.debugPrint(string.format("Direction mismatch: entry %d is %s, first entry is %s", 
                    i, directionHistory[i].direction, firstDirection))
                break
            end
        end

        -- If all N entries are the same direction and different from stable direction, update
        if allSameDirection and firstDirection ~= stableDirection then
            DumpTruck.debugPrint(string.format("Found new stable direction: %s (was %s)", 
                firstDirection, stableDirection or "nil"))
            stableDirection = firstDirection
            -- Use the position from the first entry in history
            startX = directionHistory[1].x
            startY = directionHistory[1].y
            hasUpdatedStartPoint = false
            -- Clear the current line data when direction changes
            DumpTruck.clearCurrentLine()
            DumpTruck.debugPrint(string.format("New stable direction %s, updating start point to (%d, %d)", 
                stableDirection, startX, startY))
        end
    end

    local halfWidth = width / 2
    local endX = cx
    local endY = cy
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
    
    local currentSquares = DumpTruck.getBackSquares2(fx, fy, cx, cy, cz, 3, length)
    
    -- -- Restore the old line before pouring new gravel
    -- DumpTruck.restoreCurrentLine()
    
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
    
    local halfWidth = math.ceil(thickness / 2)
    local thickPoints = {}
    local seen = {}
    
    -- Calculate direction vector
    local dx = x1 - x0
    local dy = y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
        dx = dx / len
        dy = dy / len
    end
    
    -- Calculate perpendicular vector
    local perpX = -dy
    local perpY = dx
    
    -- For each point in the base line
    for i, point in ipairs(baseLine) do
        -- Add points perpendicular to the line direction
        for w = -halfWidth, halfWidth do
            local newX = point.x + math.floor(perpX * w)
            local newY = point.y + math.floor(perpY * w)
            local key = newX .. "," .. newY
            
            if not seen[key] then
                seen[key] = true
                table.insert(thickPoints, {x = newX, y = newY})
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

-- Function to restore original floor sprites from current line
function DumpTruck.restoreCurrentLine()
    DumpTruck.debugPrint(string.format("Restoring %d squares from current line", #currentLine.squares))
    
    for _, entry in ipairs(currentLine.squares) do
        local sq = entry.square
        if sq then
            -- Remove the current floor (gravel)
            local currentFloor = sq:getFloor()
            if currentFloor then
                sq:RemoveTileObject(currentFloor)
            end
            
            -- Restore original floor if it existed
            if entry.originalSprite then
                local newFloor = sq:addFloor(entry.originalSprite)
                if newFloor then
                    -- Copy any original modData if needed
                    local modData = newFloor:getModData()
                    modData.pourable = true
                    modData.removable = true
                end
            end
            
            sq:RecalcProperties()
            sq:DirtySlice()
            if isClient() then
                sq:transmitFloor()
            end
            DumpTruck.debugPrint(string.format("Restored square (%d, %d) to original sprite: %s", 
                sq:getX(), sq:getY(), entry.originalSprite or "none"))
        end
    end
    
    -- Clear the current line after restoring
    DumpTruck.clearCurrentLine()
end






