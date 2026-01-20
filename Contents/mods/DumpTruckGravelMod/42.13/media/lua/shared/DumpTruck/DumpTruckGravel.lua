local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local DumpTruck = {}
DumpTruck.debugMode = false


-- Utility function for debug printing
function DumpTruck.debugPrint(...)
    if DumpTruck.debugMode then
        print("[DEBUG]", ...)
    end
end

-- HELPERS

-- Check if a tile is poured gravel
function DumpTruck.isPouredGravel(square)
    if not square then return false end

    
    -- Check if it's a full gravel floor
    local isGravel = DumpTruck.isFullGravelFloor(square)
    
    -- Check if it's a gap filler (gravel floor with isGapFiller metadata)
    local floor = square:getFloor()
    local isGapFiller = false
    if floor then
        local floorModData = floor:getModData()
        isGapFiller = floorModData and floorModData.isGapFiller
    end
    
    local result = isGravel or isGapFiller
    
    return result
end

-- Check if a tile is a full gravel floor (not a blend)
function DumpTruck.isFullGravelFloor(tile)
    if not tile then return false end
    local floor = tile:getFloor()
    if not floor then return false end
    
    -- Gap fillers should NOT count as full gravel for corner detection
    -- (prevents cascading gap filler placement)
    local floorModData = floor:getModData()
    if floorModData and floorModData.isGapFiller then
        return false
    end
    
    -- Check sprite directly for gravel (no metadata needed)
    local spriteName = floor:getSprite():getName()
    local isGravelSprite = spriteName == DumpTruckConstants.GRAVEL_SPRITE
    
    return isGravelSprite
end

-- Check if square is valid for gravel
function DumpTruck.isSquareValidForGravel(sq)
    if not sq then
        return false
    end
    if CFarmingSystem and CFarmingSystem.instance:getLuaObjectOnSquare(sq) then
        return false
    end
    if sq:getProperties() and sq:getProperties():has("water") then
        return false
    end
    if DumpTruck.isPouredGravel(sq) then
        -- Allow gap fillers to be upgraded to full gravel tiles
        local floor = sq:getFloor()
        if floor then
            local floorModData = floor:getModData()
            if floorModData and floorModData.isGapFiller then
            return true  -- Allow gap filler upgrade
            end
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
        -- Extract the tile number to verify it's a base terrain (0, 5, 6, or 7 within each row)
        local tileNumber = tonumber(spriteName:match("blends_natural_%d+_(%d+)"))
        if tileNumber then
            local withinRow = tileNumber % 16
            -- Only accept base terrain variants (0, 5, 6, 7)
            if withinRow == 0 or withinRow == 5 or withinRow == 6 or withinRow == 7 then
        return spriteName
            end
        end
    end
    
    return nil
end



-- Helper: Check if square has any blends pointing toward a gravel neighbor
local function hasBlendPointingAtGravel(square, adjacentChecks)
    local floor = square:getFloor()
    if not floor then return false end
    
    local modData = floor:getModData()
    if not modData or modData.isGapFiller or not modData.attachedBlends or #modData.attachedBlends == 0 then
        return false
    end
    
    for _, check in ipairs(adjacentChecks) do
        if check.square and DumpTruck.isPouredGravel(check.square) then
            for _, attachedBlend in ipairs(modData.attachedBlends) do
                local baseNumber = tonumber(attachedBlend:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
                if baseNumber then
                    local baseRow = math.floor(baseNumber / 16)
                    local rowStartTile = baseRow * 16
                    
                    for _, offset in ipairs(check.offsets) do
                        if baseNumber == rowStartTile + offset then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--[[
    removeOppositeEdgeBlends: Removes edge blends between this square and gravel neighbors
    Clears edge blends on this square pointing at gravel neighbors
    Clears edge blends on gravel neighbors pointing back at this square
]]
function DumpTruck.removeOppositeEdgeBlends(square)
    if not square then 
        return 
    end
    
    -- Check MY blends pointing at neighbors
    local myChecks = {
        {square = square:getN(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.NORTH},
        {square = square:getS(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.SOUTH},
        {square = square:getE(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.EAST},
        {square = square:getW(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.WEST}
    }
    
    if hasBlendPointingAtGravel(square, myChecks) then
        local myFloor = square:getFloor()
        local myModData = myFloor:getModData()
        myFloor:RemoveAttachedAnims()
        myModData.attachedBlends = {}
        myFloor:transmitModData()
        square:RecalcProperties()
        square:DirtySlice()
    end
    
    -- Check NEIGHBOR blends pointing back at me
    local neighborChecks = {
        {square = square:getN(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.SOUTH},
        {square = square:getS(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.NORTH},
        {square = square:getE(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.WEST},
        {square = square:getW(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.EAST}
    }
    
    for _, check in ipairs(neighborChecks) do
        if check.square and DumpTruck.isPouredGravel(check.square) then
            if hasBlendPointingAtGravel(check.square, {{square = square, offsets = check.offsets}}) then
                local adjFloor = check.square:getFloor()
                local adjModData = adjFloor:getModData()
                adjFloor:RemoveAttachedAnims()
                adjModData.attachedBlends = {}
                adjFloor:transmitModData()
                check.square:RecalcProperties()
                check.square:DirtySlice()
            end
        end
    end
end

--[[
    removeEdgeBlendsBetweenPourableSquares: Legacy function, now calls removeOppositeEdgeBlends
]]
function DumpTruck.removeEdgeBlendsBetweenPourableSquares(pourableSquare)
    DumpTruck.removeOppositeEdgeBlends(pourableSquare)
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
    if not terrainBlock or type(terrainBlock) ~= "string" or not terrainBlock:find("^" .. DumpTruckConstants.EDGE_BLEND_SPRITES .. "_") then
        return nil
    end
    
    -- Extract the base number from the sprite name
    local baseNumber = tonumber(terrainBlock:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
    if not baseNumber then
        return nil
    end
    
    local baseRow = math.floor(baseNumber / 16)
    local rowStartTile = baseRow * 16
    
    local offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS[direction]
    if not offsets then 
        return nil 
    end
    
    -- Randomly choose between the two variations
    local offset = offsets[ZombRand(1, 3)] -- ZombRand(1,3) returns either 1 or 2
    
    -- Calculate final overlay tile ID using the base number
    local overlayTile = rowStartTile + offset
    
    local result = DumpTruckConstants.EDGE_BLEND_SPRITES .. "_" .. overlayTile
    
    return result
end

--[[
    getGapFillerTriangleSprite: Calculates the natural terrain triangle sprite for gap filling
    Input:
        triangleOffset: number - Triangle offset (1-4) from corner pattern mapping
        naturalTerrainSprite: string - Natural terrain sprite (e.g., "blends_natural_01_64")
    Output: string - Natural terrain triangle sprite (e.g., "blends_natural_01_17")
]]
function DumpTruck.getGapFillerTriangleSprite(triangleOffset, naturalTerrainSprite)
    if not triangleOffset or not naturalTerrainSprite or type(naturalTerrainSprite) ~= "string" then
        return nil
    end
    
    -- Extract the base number from the natural terrain sprite (e.g., "blends_natural_01_64" -> 64)
    local baseNumber = tonumber(naturalTerrainSprite:match("blends_natural_%d+_(%d+)"))
    if not baseNumber then
        return nil
    end
    
    -- Calculate the row start tile (normalizes all variants like 64, 69, 70, 71 to row start 64)
    local baseRow = math.floor(baseNumber / 16)
    local rowStartTile = baseRow * 16
    
    -- Calculate final triangle tile in blends_natural_01 tileset
    local triangleTile = rowStartTile + triangleOffset
    
    local result = "blends_natural_01_" .. triangleTile
    
    return result
end

--[[
    placeGapFiller: Places gravel floor with natural terrain triangle overlay
    Input:
        nonGravelSquare: IsoGridSquare - Square that doesn't have gravel (corner gap)
        triangleOffset: number - Triangle offset (1-4) from corner pattern mapping
    Output: boolean - true if successful, false otherwise
]]
function DumpTruck.placeGapFiller(nonGravelSquare, triangleOffset)
    if not nonGravelSquare or not triangleOffset then
        return false
    end
    
    -- Check if already has gravel (don't overwrite)
    if DumpTruck.isPouredGravel(nonGravelSquare) then
        return false
    end
    
    -- Get the natural terrain sprite from the square
    local naturalTerrainSprite = DumpTruck.getBlendNaturalSprite(nonGravelSquare)
    if not naturalTerrainSprite then
        return false
    end
    
    -- Calculate the natural triangle sprite
    local triangleSprite = DumpTruck.getGapFillerTriangleSprite(triangleOffset, naturalTerrainSprite)
    if not triangleSprite then
        return false
    end
    
    -- Save original floor sprite for shoveling restoration
    local originalFloor = nonGravelSquare:getFloor()
    local shovelledSprites = nil
    if originalFloor and originalFloor:getSprite() then
        shovelledSprites = {originalFloor:getSprite():getName()}
    end
    
    -- Place GRAVEL floor (now it's a gravel tile for shoveling)
    local newFloor = nonGravelSquare:addFloor(DumpTruckConstants.GRAVEL_SPRITE)
    if not newFloor then
        DumpTruck.debugPrint("placeGapFiller: Failed to add gravel floor")
        return false
    end
    
    -- Attach the natural terrain triangle to the gravel floor
    local sprite = getSprite(triangleSprite)
    if sprite then
        newFloor:AttachExistingAnim(sprite, 0, 0, false, 0, false, 0.0)
    end
    
    -- Set metadata so it's recognized as gravel and can be shoveled
    local floorModData = newFloor:getModData()
    floorModData.pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
    floorModData.shovelled = nil
    floorModData.isGapFiller = true
    if shovelledSprites then
        floorModData.shovelledSprites = shovelledSprites
    end
    
    -- Disable erosion on this square
    nonGravelSquare:disableErosion()
    
    -- Remove any old edge blend overlays and clear metadata
    DumpTruck.removeOppositeEdgeBlends(nonGravelSquare)
    
    -- Sync to clients
    newFloor:transmitModData()
    
    return true
end

--[[
    placeEdgeBlend: Attaches edge blend sprite to existing gravel floor
    Input:
        gravelSquare: IsoGridSquare - Square with gravel floor
        blendSprite: string - Edge blend sprite to attach (e.g., "blends_natural_01_8")
    Output: boolean - true if successful, false otherwise
]]
function DumpTruck.placeEdgeBlend(gravelSquare, blendSprite)
    if not gravelSquare or not blendSprite then
        return false
    end
    
    -- Must be a gravel square
    if not DumpTruck.isPouredGravel(gravelSquare) then
        return false
    end
    
    -- Get the gravel floor
    local floor = gravelSquare:getFloor()
    if not floor then
        return false
    end
    
    -- Don't place edge blends on gap fillers (they already have natural terrain triangles)
    local floorModData = floor:getModData()
    if floorModData and floorModData.isGapFiller then
        return false
    end
    
    -- Check if this blend is already attached
    if floorModData.attachedBlends then
        for _, existingBlend in ipairs(floorModData.attachedBlends) do
            if existingBlend == blendSprite then
                return false  -- Already attached
            end
        end
    end
    
    -- Attach the blend sprite to the floor
    local sprite = getSprite(blendSprite)
    if sprite then
        floor:AttachExistingAnim(sprite, 0, 0, false, 0, false, 0.0)
    else
        return false
    end
    
    -- Track attached blends in metadata
    if not floorModData.attachedBlends then
        floorModData.attachedBlends = {}
    end
    table.insert(floorModData.attachedBlends, blendSprite)
    
    -- Sync to clients
    floor:transmitModData()
    gravelSquare:RecalcProperties()
    gravelSquare:DirtySlice()
    
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
        return 
    end
    
    local secondaryDir
    if leftTile:getX() == rightTile:getX() then
        -- For east-west roads, determine which direction to use based on Y coordinates
        if leftTile:getY() > rightTile:getY() then
            -- Going west: left tile is south, right tile is north
            secondaryDir = {"SOUTH", "NORTH"}
        else
            -- Going east: left tile is north, right tile is south
            secondaryDir = {"NORTH", "SOUTH"}
        end
    else
        -- For north-south roads, determine which direction to use based on X coordinates
        if leftTile:getX() < rightTile:getX() then
            -- Going south: left tile is west, right tile is east
            secondaryDir = {"WEST", "EAST"}
        else
            -- Going north: left tile is east, right tile is west
            secondaryDir = {"EAST", "WEST"}
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
    
    -- Add terrain blends for outer edges
    for i, tile in ipairs({leftTile, rightTile}) do
        local sideTile = i == 1 and leftSideTile or rightSideTile
        local sideDir = i == 1 and secondaryDir[1] or secondaryDir[2]
        
        print("DEBUG EDGE BLEND: Checking edge " .. (i == 1 and "LEFT" or "RIGHT") .. " tile at " .. tile:getX() .. "," .. tile:getY())
        
        if sideTile then
            print("DEBUG EDGE BLEND: Adjacent tile exists at " .. sideTile:getX() .. "," .. sideTile:getY())
            -- Check if the adjacent side tile doesn't have poured gravel
            if not DumpTruck.isPouredGravel(sideTile) then
                print("DEBUG EDGE BLEND: Adjacent tile is NOT gravel, proceeding")
                local terrain = DumpTruck.getBlendNaturalSprite(sideTile)
                print("DEBUG EDGE BLEND: Natural terrain = " .. tostring(terrain))
                if terrain then
                    local blend = DumpTruck.getEdgeBlendSprite(sideDir, terrain)
                    print("DEBUG EDGE BLEND: Calculated blend sprite = " .. tostring(blend) .. " for direction " .. sideDir)
                    if blend then
                        local success = DumpTruck.placeEdgeBlend(tile, blend)
                        print("DEBUG EDGE BLEND: placeEdgeBlend returned " .. tostring(success))
                    end
                end
            else
                print("DEBUG EDGE BLEND: Adjacent tile IS gravel, skipping")
            end
        else
            print("DEBUG EDGE BLEND: No adjacent tile")
        end
    end
end

-- Check if a grass tile adjacent to a gravel tile forms a corner pattern
function DumpTruck.checkForCornerPattern(gravelTile)
    if not gravelTile or not DumpTruck.isFullGravelFloor(gravelTile) then
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

            -- Then check other adjacent tiles from the grass tile's perspective
            for _, otherCheck in ipairs(otherAdjacentChecks) do
                -- Skip the direction that points back to our original gravel tile
                if otherCheck.dir ~= check.opposite then
                    if otherCheck.tile and DumpTruck.isFullGravelFloor(otherCheck.tile) then
                        gravelCount = gravelCount + 1
                        table.insert(gravelDirections, otherCheck.dir)
                    end
                end
            end

            -- If we found exactly one other gravel floor tile, we have a corner pattern
            if gravelCount == 1 then
                -- Look up the appropriate triangle offset in our mapping
                for _, mapping in ipairs(DumpTruckConstants.ADJACENT_TO_BLEND_MAPPING) do
                    local directions = mapping.adjacent_directions
                    
                    -- Check if our gravel directions match this mapping (order doesn't matter)
                    if (gravelDirections[1] == directions[1] and gravelDirections[2] == directions[2]) or
                       (gravelDirections[1] == directions[2] and gravelDirections[2] == directions[1]) then
                        return adjacentTile, mapping.triangle_offset
                    end
                end
            end
        end
    end

    return nil, nil
end

function DumpTruck.fillGaps(leftTile, rightTile)
    local adjacentTile1, triangleOffset1 = DumpTruck.checkForCornerPattern(leftTile)
    local adjacentTile2, triangleOffset2 = DumpTruck.checkForCornerPattern(rightTile)

    if adjacentTile1 and triangleOffset1 then
        DumpTruck.placeGapFiller(adjacentTile1, triangleOffset1)
    end

    if adjacentTile2 and triangleOffset2 then
        DumpTruck.placeGapFiller(adjacentTile2, triangleOffset2)
    end
end

function DumpTruck.smoothRoad(currentSquares, fx, fy)
    if #currentSquares < 2 then
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
    -- Check if this is upgrading a gap filler to full gravel
    local floor = sq:getFloor()
    local isGapFillerUpgrade = false
    if floor then
        local floorModData = floor:getModData()
        if floorModData and floorModData.isGapFiller then
        isGapFillerUpgrade = true
            -- When addFloor() is called below, it will replace the gap filler floor
            -- and remove attached sprites automatically
        end
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
        newFloor:transmitModData()
    end
    
    -- Disable erosion on this square (single player implementation)
    sq:disableErosion()
    
    
    DumpTruck.removeOppositeEdgeBlends(sq)

    
    sq:RecalcProperties()
    sq:DirtySlice()
    -- Transmit floor changes to clients (server-side or singleplayer)
    if isServer() then
        sq:transmitFloor()
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
    DumpTruck.debugPrint("Vehicle coordinates: cx=" .. cx .. ", cy=" .. cy .. ", cz=" .. cz)
    cz = 0 -- Assume ground level for simplicity

    -- Get forward vector first
    local fx, fy = DumpTruck.getVectorFromPlayer(vehicle)
    
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
    DumpTruck.debugPrint("tryPourGravelUnderTruck: Current squares to process:")
    for i, sq in ipairs(currentSquares) do
        DumpTruck.debugPrint(string.format("[DEBUG] Current square %d - x: %d, y: %d", 
            tostring(i), tostring(sq:getX()), tostring(sq:getY())))
    end
    
    -- Track if any gravel was placed this update
    local gravelPlaced = false
    
    -- Place gravel on valid squares, skipping ones that already have gravel
    for _, sq in ipairs(currentSquares) do
        if sq and DumpTruck.isSquareValidForGravel(sq) then
            if DumpTruck.getGravelCount(vehicle) <= 0 then
                DumpTruck.debugPrint("GRAVEL RAN OUT - stopping dump")
                DumpTruck.stopDumping(vehicle)
                return
            end
            DumpTruck.debugPrint("PLACED gravel at square: x=" .. sq:getX() .. ", y=" .. sq:getY())
            DumpTruck.placeGravelFloorOnTile(DumpTruckConstants.GRAVEL_SPRITE, sq)
            DumpTruck.consumeGravelFromTruckBed(vehicle)
            gravelPlaced = true
        else
            if sq then
                DumpTruck.debugPrint("SKIPPED square (not valid): x=" .. sq:getX() .. ", y=" .. sq:getY())
            end
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

-- Stop dumping sounds
function DumpTruck.stopDumpingSounds(vehicle, soundID)
    
    -- Stop loop if playing
    if soundID and soundID ~= 0 then
        local emitter = vehicle:getEmitter()
        if emitter then
            emitter:stopSound(soundID)
        end
    end
    
    -- Play hydraulic lift down and fade-out sounds
    vehicle:playSound("HydraulicLiftDown")
    vehicle:playSound("GravelDumpEnd")
    
    -- Clear from modData
    local data = vehicle:getModData()
    data.gravelLoopSoundID = nil
end

-- Start dumping
function DumpTruck.startDumping(vehicle)
    local data = vehicle:getModData()
    data.dumpingGravelActive = true
    vehicle:setMaxSpeed(DumpTruckConstants.MAX_DUMP_SPEED)
    
    -- Start dumping sounds
    DumpTruck.debugPrint("Starting dumping sounds")
    vehicle:playSound("HydraulicLiftRaised")
    vehicle:playSound("GravelDumpStart")
    local emitter = vehicle:getEmitter()
    data.gravelLoopSoundID = emitter:playSound("GravelDumpLoop")
end

-- Stop dumping
function DumpTruck.stopDumping(vehicle)
    local data = vehicle:getModData()
    data.dumpingGravelActive = false
    vehicle:setMaxSpeed(DumpTruckConstants.DEFAULT_MAX_SPEED)
    
    -- Stop dumping sounds
    DumpTruck.stopDumpingSounds(vehicle, data.gravelLoopSoundID)
end

-- Toggle gravel dumping based on key press
function DumpTruck.toggleGravelDumping(key)
    if key == DumpTruckConstants.DUMP_KEY then
        local playerObj = getSpecificPlayer(0)
        if not playerObj then return end
        local vehicle = playerObj:getVehicle()
        if vehicle and vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
            local data = vehicle:getModData()
            
            if data.dumpingGravelActive then
                DumpTruck.stopDumping(vehicle)
            else
                DumpTruck.startDumping(vehicle)
            end
        end
    end
end
-- Event bindings
Events.OnKeyPressed.Add(DumpTruck.toggleGravelDumping)

return DumpTruck