local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

DumpTruck = {}
DumpTruck.debugMode = true


-- Utility function for debug printing
function DumpTruck.debugPrint(...)
    if DumpTruck.debugMode then
        print("[DEBUG]", ...)
    end
end

-- Initialize overlay metadata (gap fillers and edge blends only)
-- Store on square, not floor, since overlays are independent objects
function DumpTruck.initializeOverlayMetadata(square, tileType, sprite, object)
    if not square then return end
    
    local modData = square:getModData()
    modData.tileType = tileType
    modData.sprite = sprite
    modData.object = object
    
    -- DEBUG CODE DELETE ME
    local x, y = square:getX(), square:getY()
    DumpTruck.debugPrint("***initializeOverlayMetadata START***")
    DumpTruck.debugPrint("(X,Y) = (" .. tostring(x) .. "," .. tostring(y) .. ")")
    DumpTruck.debugPrint("TT = " .. tostring(tileType))
    DumpTruck.debugPrint("SP = " .. tostring(sprite))
    DumpTruck.debugPrint("OBJ = " .. tostring(object))
    DumpTruck.debugPrint("***initializeOverlayMetadata END***")
end

-- Find overlay object when modData.object is nil (e.g., after save/load)
-- Only loops through objects if metadata indicates an overlay exists
function DumpTruck.findOverlayObject(square, sprite)
    if not square or not sprite then return nil end
    
    -- Only loop if we know there's an overlay here (metadata tells us)
    local objects = square:getObjects()
    if not objects then return nil end
    
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj and obj:getSprite() and obj:getSprite():getName() == sprite then
            return obj
        end
    end
    return nil
end

-- Reset overlay metadata to clean state
-- Store on square, not floor, since overlays are independent objects
function DumpTruck.resetOverlayMetadata(square)
    if not square then return end
    
    local modData = square:getModData()
    
    -- TODO: REMOVE THIS DEBUG CODE - Get square coords and log metadata before clearing
    local x, y = square:getX(), square:getY()
    if modData.tileType ~= nil then
        DumpTruck.debugPrint("***resetOverlayMetadata START***")
        DumpTruck.debugPrint("(X,Y) = (" .. tostring(x) .. "," .. tostring(y) .. ")")
        DumpTruck.debugPrint("***resetOverlayMetadata END***")
    end
    
    
    modData.tileType = nil
    modData.sprite = nil
    modData.object = nil
end

-- HELPERS

-- Check if a tile is poured gravel
function DumpTruck.isPouredGravel(square)
    if not square then return false end

    
    -- Check if it's a full gravel floor
    local isGravel = DumpTruck.isFullGravelFloor(square)
    
    -- Check if it has a gap filler overlay (metadata stored on square, not floor)
    local modData = square:getModData()
    local hasGapFillerOverlay = modData.tileType == DumpTruckConstants.TILE_TYPES.GAP_FILLER
    
    local result = isGravel or hasGapFillerOverlay
    
    DumpTruck.debugPrint("***isPouredGravel START***")
    DumpTruck.debugPrint("(X,Y) = (" .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. ")")
    DumpTruck.debugPrint("isGravel = " .. tostring(isGravel))
    DumpTruck.debugPrint("hasGapFillerOverlay = " .. tostring(hasGapFillerOverlay))
    DumpTruck.debugPrint("result = " .. tostring(result))
    DumpTruck.debugPrint("***isPouredGravel END***")
    return result
end

-- Check if a tile is a full gravel floor (not a blend)
function DumpTruck.isFullGravelFloor(tile)
    if not tile then return false end
    local floor = tile:getFloor()
    if not floor then return false end
    
    -- Check sprite directly for gravel (no metadata needed)
    local spriteName = floor:getSprite():getName()
    local isGravelSprite = spriteName == DumpTruckConstants.GRAVEL_SPRITE
    
    DumpTruck.debugPrint("isFullGravelFloor tile at (" .. tostring(tile:getX()) .. "," .. tostring(tile:getY()) .. ") sprite=" .. spriteName .. " isGravel=" .. tostring(isGravelSprite))
    return isGravelSprite
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
        -- Allow gap fillers to be upgraded to full gravel tiles
        local modData = sq:getModData()
        if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
            return true  -- Allow gap filler upgrade
        end
        return false  -- Reject full gravel tiles
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
    if not sq then 
        return nil 
    end
    
    local floor = sq:getFloor()
    if not floor then
        return nil
    end
    
    local spriteName = floor:getSprite():getName()
    
    if spriteName and spriteName:find("^" .. DumpTruckConstants.EDGE_BLEND_SPRITES .. "_") then
        return spriteName
    end
    
    return nil
end


function DumpTruck.removeOverlayObject(square, edgeBlendObject)
    print("[DUMPTRUCK] removeOverlay (" .. square:getX() .. "," .. square:getY() .. ")")
    
    -- Direct removal using stored object reference
    square:RemoveTileObject(edgeBlendObject)
    
    -- Clear edge blend metadata (stored on square, not floor)
    DumpTruck.resetOverlayMetadata(square)
    
    square:RecalcProperties()
    square:DirtySlice()
    if isClient() then
        square:transmitFloor()
    end
end



function DumpTruck.removeOppositeEdgeBlends(square)
    if not square then 
        return 
    end
    
    DumpTruck.debugPrint("***removeOppositeEdgeBlends START***")
    DumpTruck.debugPrint("(X,Y) = (" .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. ")")
    
    -- Check each direction
    local adjacentChecks = {
        {square = square:getN(), oppositeSprites = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.SOUTH, dir = "North"},
        {square = square:getS(), oppositeSprites = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.NORTH, dir = "South"},
        {square = square:getE(), oppositeSprites = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.WEST, dir = "East"},
        {square = square:getW(), oppositeSprites = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.EAST, dir = "West"}
    }
    
    for _, check in ipairs(adjacentChecks) do
        if check and check.square then
            DumpTruck.debugPrint("***CHECK DIRECTION START***")
            DumpTruck.debugPrint("dir = " .. check.dir)
            DumpTruck.debugPrint("adjSquare (X,Y) = (" .. tostring(check.square:getX()) .. "," .. tostring(check.square:getY()) .. ")")
            
            -- Check if this square has edge blend metadata (stored on square, not floor)
            local modData = check.square:getModData()

            if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND then
                local edgeBlendObject = modData.object
                local edgeBlendSprite = modData.sprite
                if edgeBlendObject and edgeBlendSprite then
                    -- Extract the base number from the stored sprite name
                    local baseNumber = tonumber(edgeBlendSprite:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
                    if baseNumber then
                        local baseRow = math.floor(baseNumber / 16)
                        local rowStartTile = baseRow * 16
                        
                        DumpTruck.debugPrint("***FOUND EDGE BLEND START***")
                        DumpTruck.debugPrint("sprite = " .. tostring(edgeBlendSprite))
                        DumpTruck.debugPrint("baseNumber = " .. tostring(baseNumber))
                        DumpTruck.debugPrint("rowStartTile = " .. tostring(rowStartTile))
                        
                        -- Check if the sprite matches any of the opposite sprites we want to remove
                        local shouldRemove = false
                        for _, oppositeOffset in ipairs(check.oppositeSprites) do
                            local oppositeSprite = rowStartTile + oppositeOffset
                            DumpTruck.debugPrint("***COMPARING START***")
                            DumpTruck.debugPrint("baseNumber = " .. tostring(baseNumber))
                            DumpTruck.debugPrint("oppositeSprite = " .. tostring(oppositeSprite))
                            DumpTruck.debugPrint("oppositeOffset = " .. tostring(oppositeOffset))
                            DumpTruck.debugPrint("***COMPARING END***")
                            if baseNumber == oppositeSprite then
                                shouldRemove = true
                                DumpTruck.debugPrint("***MATCH FOUND - REMOVING***")
                                DumpTruck.debugPrint("sprite = " .. tostring(edgeBlendSprite))
                                DumpTruck.debugPrint("***MATCH FOUND END***")
                                break
                            end
                        end
                        
                        DumpTruck.debugPrint("***FOUND EDGE BLEND END***")
                        if shouldRemove then
                            DumpTruck.removeOverlayObject(check.square, edgeBlendObject)
                        end
                    end
                end
            end
            DumpTruck.debugPrint("***CHECK DIRECTION END***")
        end
    end
    DumpTruck.debugPrint("***removeOppositeEdgeBlends END***")
end

--[[
    removeEdgeBlendsBetweenPourableSquares: Removes edge blends between pourable squares
    Input:
        pourableSquare: IsoGridSquare - The pourable square to check around
    Output: None (modifies tiles directly)
    
    Summary: This function checks all adjacent squares to the given pourable square.
    If any adjacent square is also pourable (gravel), it removes any edge blends
    that exist between them on either side of the connection.
]]
function DumpTruck.removeEdgeBlendsBetweenPourableSquares(pourableSquare)
    if not pourableSquare or not DumpTruck.isPouredGravel(pourableSquare) then
        DumpTruck.debugPrint("removeEdgeBlendsBetweenPourableSquares: Invalid or non-pourable square input")
        return
    end
    
    DumpTruck.debugPrint(string.format("removeEdgeBlendsBetweenPourableSquares: Checking pourable square (%d,%d)", 
        pourableSquare:getX(), pourableSquare:getY()))
    
    -- Check all four adjacent directions
    local adjacentChecks = {
        {square = pourableSquare:getN(), dir = "NORTH"},
        {square = pourableSquare:getS(), dir = "SOUTH"},
        {square = pourableSquare:getE(), dir = "EAST"},
        {square = pourableSquare:getW(), dir = "WEST"}
    }
    
    for _, check in ipairs(adjacentChecks) do
        if check.square and DumpTruck.isPouredGravel(check.square) then
            DumpTruck.debugPrint(string.format("removeEdgeBlendsBetweenPourableSquares: Found adjacent pourable square at (%d,%d) in direction %s", 
                check.square:getX(), check.square:getY(), check.dir))
            
            -- Check both squares for edge blends that point toward each other
            -- We need to check for edge blends on both sides of the connection
            
            -- Check the original square for edge blends pointing toward the adjacent square (metadata stored on square, not floor)
            local modData = pourableSquare:getModData()
            local floorSprite = ""
            local floor = pourableSquare:getFloor()
            if floor then
                floorSprite = floor:getSprite() and floor:getSprite():getName() or "nil"
            end
            
            local x = tostring(pourableSquare:getX())
            local y = tostring(pourableSquare:getY())
            DumpTruck.debugPrint("***METADATA CHECK START***")
            DumpTruck.debugPrint("(X,Y) = (" .. x .. "," .. y .. ")")
            DumpTruck.debugPrint("FS = " .. tostring(floorSprite))
            DumpTruck.debugPrint("TT = " .. tostring(modData.tileType))
            DumpTruck.debugPrint("SP = " .. tostring(modData.sprite))
            DumpTruck.debugPrint("OBJ = " .. tostring(modData.object))
            DumpTruck.debugPrint("***METADATA CHECK END***")
            
            if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND then
                local edgeBlendObject = modData.object
                local edgeBlendSprite = modData.sprite
                
                if edgeBlendObject and edgeBlendSprite then
                    -- Extract the base number from the stored sprite name
                    local baseNumber = tonumber(edgeBlendSprite:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
                    if baseNumber then
                        local baseRow = math.floor(baseNumber / 16)
                        local rowStartTile = baseRow * 16
                        
                        -- Check if this edge blend points toward the adjacent pourable square
                        local directionOffsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS[check.dir]
                        if directionOffsets then
                            local shouldRemove = false
                            for _, directionOffset in ipairs(directionOffsets) do
                                local targetSprite = rowStartTile + directionOffset
                                if baseNumber == targetSprite then
                                    shouldRemove = true
                                    DumpTruck.debugPrint(string.format("removeEdgeBlendsBetweenPourableSquares: Removing edge blend %s from original square (%d,%d)", 
                                        edgeBlendSprite, pourableSquare:getX(), pourableSquare:getY()))
                                    break
                                end
                            end
                            
                            if shouldRemove then
                                DumpTruck.removeOverlayObject(pourableSquare, edgeBlendObject)
                            end
                        end
                    end
                end
            end
            
            -- Check the adjacent square for edge blends pointing toward the original square (metadata stored on square, not floor)
            local adjacentModData = check.square:getModData()
            if adjacentModData and adjacentModData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND then
                local edgeBlendObject = adjacentModData.object
                local edgeBlendSprite = adjacentModData.sprite
                
                if edgeBlendObject and edgeBlendSprite then
                    -- Extract the base number from the stored sprite name
                    local baseNumber = tonumber(edgeBlendSprite:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
                    if baseNumber then
                        local baseRow = math.floor(baseNumber / 16)
                        local rowStartTile = baseRow * 16
                        
                        -- Get the opposite direction for checking
                        local oppositeDir = nil
                        if check.dir == "NORTH" then oppositeDir = "SOUTH"
                        elseif check.dir == "SOUTH" then oppositeDir = "NORTH"
                        elseif check.dir == "EAST" then oppositeDir = "WEST"
                        elseif check.dir == "WEST" then oppositeDir = "EAST"
                        end
                        
                        -- Check if this edge blend points toward the original pourable square
                        local oppositeOffsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS[oppositeDir]
                        if oppositeOffsets then
                            local shouldRemove = false
                            for _, oppositeOffset in ipairs(oppositeOffsets) do
                                local oppositeSprite = rowStartTile + oppositeOffset
                                if baseNumber == oppositeSprite then
                                    shouldRemove = true
                                    DumpTruck.debugPrint(string.format("removeEdgeBlendsBetweenPourableSquares: Removing edge blend %s from adjacent square (%d,%d)", 
                                        edgeBlendSprite, check.square:getX(), check.square:getY()))
                                    break
                                end
                            end
                            
                            if shouldRemove then
                                DumpTruck.removeOverlayObject(check.square, edgeBlendObject)
                            end
                        end
                    end
                end
            end
        end
    end
end

--[[
    getEdgeBlendSprite: Generates the appropriate edge blend sprite based on direction and terrain
    Input:
        direction: string - The direction to blend ("NORTH", "SOUTH", "EAST", "WEST")
        terrainBlock: string - The base terrain sprite name
    Output: string - The edge blend sprite name, or nil if no edge blend is available
    
    Summary: This function takes a direction and terrain sprite, then calculates the appropriate
    edge blend sprite to use for blending gravel edges with terrain. It uses offset calculations 
    based on the direction to determine which edge blend variant should be applied.
]]
function DumpTruck.getEdgeBlendSprite(direction, terrainBlock)
    DumpTruck.debugPrint(string.format("getEdgeBlendSprite: Called with direction='%s', terrainBlock='%s'", 
        direction or "nil", terrainBlock or "nil"))
    
    if not terrainBlock or type(terrainBlock) ~= "string" or not terrainBlock:find("^" .. DumpTruckConstants.EDGE_BLEND_SPRITES .. "_") then
        DumpTruck.debugPrint(string.format("getEdgeBlendSprite: Invalid terrainBlock '%s' - not matching pattern '%s_'", 
            terrainBlock or "nil", DumpTruckConstants.EDGE_BLEND_SPRITES))
        return nil
    end
    
    -- Extract the base number from the sprite name
    local baseNumber = tonumber(terrainBlock:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
    if not baseNumber then
        DumpTruck.debugPrint(string.format("getEdgeBlendSprite: Could not extract base number from '%s'", terrainBlock))
        return nil
    end
    
    local baseRow = math.floor(baseNumber / 16)
    local rowStartTile = baseRow * 16
    
    DumpTruck.debugPrint(string.format("getEdgeBlendSprite: baseNumber=%d, baseRow=%d, rowStartTile=%d", 
        baseNumber, baseRow, rowStartTile))
    
    local offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS[direction]
    if not offsets then 
        DumpTruck.debugPrint(string.format("getEdgeBlendSprite: No offsets found for direction '%s'", direction))
        return nil 
    end
    
    -- Randomly choose between the two variations
    local offset = offsets[ZombRand(1, 3)] -- ZombRand(1,3) returns either 1 or 2
    
    -- Calculate final overlay tile ID using the base number
    local overlayTile = rowStartTile + offset
    
    local result = DumpTruckConstants.EDGE_BLEND_SPRITES .. "_" .. overlayTile
    DumpTruck.debugPrint(string.format("getEdgeBlendSprite: Generated sprite '%s' (offset=%d)", result, offset))
    
    return result
end

function DumpTruck.placeTileOverlay(targetSquare, sprite)
    if not targetSquare then
        DumpTruck.debugPrint(string.format("placeTileOverlay: Target square is nil at (%d,%d)", 
            targetSquare:getX(), targetSquare:getY()))
        return false
    end
  
    -- Check if this overlay already exists on this square (metadata stored on square, not floor)
    local modData = targetSquare:getModData()
    if modData and modData.sprite == sprite then
        DumpTruck.debugPrint(string.format("placeTileOverlay: Overlay %s already exists at (%d,%d), skipping placement", 
            sprite, targetSquare:getX(), targetSquare:getY()))
        return false
    end
    
    -- If placing an edge blend and there's already a different edge blend, remove the old one first
    if sprite:find(DumpTruckConstants.EDGE_BLEND_SPRITES) then
        if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND and modData.object and modData.sprite ~= sprite then
            DumpTruck.debugPrint("placeTileOverlay: Removing old edge blend " .. tostring(modData.sprite) .. " before placing " .. sprite)
            targetSquare:RemoveTileObject(modData.object)
            DumpTruck.resetOverlayMetadata(targetSquare)
        end
    end
  
    DumpTruck.debugPrint(string.format("placeTileOverlay: Placing tile %s at (%d,%d)", 
        sprite, targetSquare:getX(), targetSquare:getY()))

    -- Add the overlay
    local overlay = IsoObject.new(getCell(), targetSquare, sprite)
    targetSquare:AddTileObject(overlay)

    -- Set square metadata using unified system (overlays are independent of floor)
    if sprite:find(DumpTruckConstants.GAP_FILLER_SPRITES) then
        DumpTruck.initializeOverlayMetadata(targetSquare, DumpTruckConstants.TILE_TYPES.GAP_FILLER, sprite, overlay)
    elseif sprite:find(DumpTruckConstants.EDGE_BLEND_SPRITES) then
        DumpTruck.initializeOverlayMetadata(targetSquare, DumpTruckConstants.TILE_TYPES.EDGE_BLEND, sprite, overlay)
    else
        DumpTruck.debugPrint(string.format("placeTileOverlay: Invalid sprite: %s", sprite))
        return false    
    end
    targetSquare:RecalcProperties()
    targetSquare:DirtySlice()

    DumpTruck.removeOppositeEdgeBlends(targetSquare)
    
    -- Log successful placement
    DumpTruck.debugPrint(string.format("placeTileOverlay: Successfully placed tile %s at (%d,%d)", 
        sprite, targetSquare:getX(), targetSquare:getY()))
    
    return true
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
            -- Check if the adjacent side tile already has poured gravel
            if DumpTruck.isPouredGravel(sideTile) then
                DumpTruck.debugPrint(string.format("addEdgeBlends: Skipping - side tile has gravel at (%d,%d)", 
                    sideTile:getX(), sideTile:getY()))
            else
                local terrain = DumpTruck.getBlendNaturalSprite(sideTile)
                DumpTruck.debugPrint(string.format("addEdgeBlends: Found terrain sprite: %s", terrain or "none"))
                
                if terrain then
                    local blend = DumpTruck.getEdgeBlendSprite(sideDir, terrain)
                    DumpTruck.debugPrint(string.format("addEdgeBlends: Generated blend sprite: %s", blend or "none"))
                    
                    if blend then
                        DumpTruck.debugPrint(string.format("addEdgeBlends: Placing edge blend - side tile is clear at (%d,%d)", 
                            sideTile:getX(), sideTile:getY()))
                        DumpTruck.placeTileOverlay(tile, blend)
                    end
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

    DumpTruck.debugPrint("checkForCornerPattern at (" .. tostring(gravelTile:getX()) .. "," .. tostring(gravelTile:getY()) .. ")")

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
            DumpTruck.debugPrint(string.format("checkForCornerPattern: Found non-gravel tile at (%d,%d) in direction %s", 
                adjacentTile:getX(), adjacentTile:getY(), check.dir))
            
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
                DumpTruck.debugPrint(string.format("checkForCornerPattern: Found potential corner pattern at (%d,%d) - gravelCount=%d", 
                    adjacentTile:getX(), adjacentTile:getY(), gravelCount))
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
                        local blendTile = DumpTruckConstants.GAP_FILLER_TILES[mapping.blend_direction]
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
            else
                DumpTruck.debugPrint(string.format("checkForCornerPattern: Not a corner pattern at (%d,%d) - gravelCount=%d (need exactly 1)", 
                    adjacentTile:getX(), adjacentTile:getY(), gravelCount))
            end
        end
    end

    DumpTruck.debugPrint("checkForCornerPattern: No corner pattern found")
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
    DumpTruck.fillGaps(leftTile, rightTile)
    
    DumpTruck.addEdgeBlends(leftTile, rightTile)
    
    -- Clean up edge blends between pourable squares (after addEdgeBlends)
    for _, square in ipairs(currentSquares) do
        DumpTruck.removeEdgeBlendsBetweenPourableSquares(square)
    end
end


-- GRAVEL

function DumpTruck.placeGravelFloorOnTile(sprite, sq)
    -- Check if this is upgrading a gap filler to full gravel (metadata stored on square, not floor)
    local modData = sq:getModData()
    local isGapFillerUpgrade = false
    if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        isGapFillerUpgrade = true
        
        -- Clean up gap filler data before upgrading
        local gapFillerObject = modData.object
        if gapFillerObject then
            DumpTruck.removeOverlayObject(sq, gapFillerObject)
            DumpTruck.debugPrint(string.format("placeGravelFloorOnTile: Removed gap filler object at (%d,%d)", 
                sq:getX(), sq:getY()))
        end
    end

    local newFloor = sq:addFloor(sprite)
    
    -- Disable erosion on this square (single player implementation)
    sq:disableErosion()
    
    
    DumpTruck.removeOppositeEdgeBlends(sq)

    
    sq:RecalcProperties()
    sq:DirtySlice()
    if isClient() then
        sq:transmitFloor()
    end

    -- Log successful placement
    if isGapFillerUpgrade then
        DumpTruck.debugPrint(string.format("placeGravelFloorOnTile: Successfully upgraded gap filler to full gravel at (%d,%d)", 
            sq:getX(), sq:getY()))
    else
        DumpTruck.debugPrint(string.format("placeGravelFloorOnTile: Successfully placed gravel floor at (%d,%d)", 
            sq:getX(), sq:getY()))
    end
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
        DumpTruck.debugPrint(string.format("[DEBUG] Current square %d - x: %d, y: %d", 
            tostring(i), tostring(sq:getX()), tostring(sq:getY())))
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







