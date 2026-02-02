-- DumpTruckOverlays.lua
-- Edge blends, gap fillers, and overlay management

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")

local DumpTruckOverlays = {}

-- OVERLAY METADATA HELPERS

-- Initialize overlay metadata (gap fillers and edge blends only)
-- Store on FLOOR modData - saves with world, LoadGridsquare recreates on reload
-- transmitModData syncs to other clients for LoadGridsquare restore function
function DumpTruckOverlays.initializeOverlayMetadata(square, tileType, sprite)
    if not square then return end
    
    local floor = square:getFloor()
    if not floor then return end
    
    local floorModData = floor:getModData()
    floorModData.overlayType = tileType
    floorModData.overlaySprite = sprite
    
    -- Sync modData to other clients for restore function
    floor:transmitModData()
end

-- Reset overlay metadata to clean state
-- Store on FLOOR modData, transmit to sync with other clients
function DumpTruckOverlays.resetOverlayMetadata(square)
    if not square then return end
    
    local floor = square:getFloor()
    if not floor then return end
    
    local floorModData = floor:getModData()
    floorModData.overlayType = nil
    floorModData.overlaySprite = nil
    floor:transmitModData()  -- Sync to other clients
end

-- Get overlay data from floor modData
-- Returns {type, sprite} or nil if no overlay
function DumpTruckOverlays.getOverlayData(square)
    if not square then return nil end
    local floor = square:getFloor()
    if not floor then return nil end
    local floorModData = floor:getModData()
    if not floorModData or not floorModData.overlayType then return nil end
    return {
        type = floorModData.overlayType,
        sprite = floorModData.overlaySprite
    }
end

-- CENTRAL OVERLAY METHODS

-- Place overlay on square (gap filler or edge blend)
-- Uses AttachExistingAnim to attach sprite to floor, transmits to MP, sets metadata
function DumpTruckOverlays.placeOverlay(square, sprite, tileType)
    if not square or not sprite then return false end
    
    local floor = square:getFloor()
    if not floor then return false end
    
    local spriteObj = getSprite(sprite)
    if not spriteObj then return false end
    
    -- Attach sprite to floor using vanilla pattern (see ISShovelGround.lua)
    floor:AttachExistingAnim(spriteObj, 0, 0, false, 0, false, 0.0)
    
    -- Sync to MP clients (server only - not needed in SP)
    if isServer() then
        floor:transmitUpdatedSpriteToClients()
    end
    
    DumpTruckOverlays.initializeOverlayMetadata(square, tileType, sprite)
    return true
end

-- Remove overlay from square (gap filler or edge blend)
-- Uses RemoveAttachedAnims to remove all attached sprites, clears metadata
function DumpTruckOverlays.removeOverlay(square)
    if not square then return false end
    
    local floor = square:getFloor()
    if not floor then return false end
    
    -- Remove all attached anims from floor
    floor:RemoveAttachedAnims()
    
    -- Sync to MP clients (server only - not needed in SP)
    if isServer() then
        floor:transmitUpdatedSpriteToClients()
    end
    
    DumpTruckOverlays.resetOverlayMetadata(square)
    return true
end

-- Remove overlay and update square properties (for shoveling/cleanup)
-- Wrapper around removeOverlay with additional square updates
function DumpTruckOverlays.removeOverlayFromSquare(square)
    if not DumpTruckOverlays.removeOverlay(square) then
        return false
    end
    
    square:RecalcProperties()
    square:DirtySlice()
    if square.transmitFloor then square:transmitFloor() end
    
    return true
end

-- TERRAIN DETECTION

function DumpTruckOverlays.getBlendNaturalSprite(sq)
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

-- EDGE BLEND HELPERS

-- Helper: Check if square has any blends pointing toward a gravel neighbor
local function hasBlendPointingAtGravel(square, adjacentChecks)
    if not square then return false end
    
    local floor = square:getFloor()
    if not floor then return false end
    
    local floorModData = floor:getModData()
    if not floorModData or floorModData.overlayType ~= DumpTruckConstants.TILE_TYPES.EDGE_BLEND or not floorModData.overlaySprite then
        return false
    end
    
    -- Check if this square's edge blend points at any gravel neighbor
    for _, check in ipairs(adjacentChecks) do
        if check.square and DumpTruckCore.isPouredGravel(check.square) then
            local baseNumber = tonumber(floorModData.overlaySprite:match(DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)"))
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
    return false
end

--[[
    removeOppositeEdgeBlends: Removes edge blends between this square and gravel neighbors
    Clears edge blends on this square pointing at gravel neighbors
    Clears edge blends on gravel neighbors pointing back at this square
]]
function DumpTruckOverlays.removeOppositeEdgeBlends(square)
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
        DumpTruckOverlays.removeOverlayFromSquare(square)
    end
    
    -- Check NEIGHBOR blends pointing back at me
    local neighborChecks = {
        {square = square:getN(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.SOUTH},
        {square = square:getS(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.NORTH},
        {square = square:getE(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.WEST},
        {square = square:getW(), offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS.EAST}
    }
    
    for _, check in ipairs(neighborChecks) do
        if check.square and DumpTruckCore.isPouredGravel(check.square) then
            if hasBlendPointingAtGravel(check.square, {{square = square, offsets = check.offsets}}) then
                DumpTruckOverlays.removeOverlayFromSquare(check.square)
            end
        end
    end
end

--[[
    removeEdgeBlendsBetweenPourableSquares: Legacy function, now calls removeOppositeEdgeBlends
]]
function DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(pourableSquare)
    DumpTruckOverlays.removeOppositeEdgeBlends(pourableSquare)
end

-- SPRITE GENERATION

--[[
    getEdgeBlendSprite: Generates the appropriate edge blend sprite based on direction and terrain
    Input:
        direction: string - The direction to blend ("NORTH", "SOUTH", "EAST", "WEST")
        terrainBlock: string - The base terrain sprite name
    Output: string - The edge blend sprite name, or nil if no edge blend is available
]]
function DumpTruckOverlays.getEdgeBlendSprite(direction, terrainBlock)
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
function DumpTruckOverlays.getGapFillerTriangleSprite(triangleOffset, naturalTerrainSprite)
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

-- PLACEMENT FUNCTIONS

--[[
    placeGapFiller: Places gravel floor with natural terrain triangle overlay
    Input:
        nonGravelSquare: IsoGridSquare - Square that doesn't have gravel (corner gap)
        triangleOffset: number - Triangle offset (1-4) from corner pattern mapping
    Output: boolean - true if successful, false otherwise
]]
function DumpTruckOverlays.placeGapFiller(nonGravelSquare, triangleOffset)
    if not nonGravelSquare or not triangleOffset then
        return false
    end
    
    -- Check if already has gravel (don't overwrite)
    if DumpTruckCore.isPouredGravel(nonGravelSquare) then
        return false
    end
    
    -- Get the natural terrain sprite from the square
    local naturalTerrainSprite = DumpTruckOverlays.getBlendNaturalSprite(nonGravelSquare)
    if not naturalTerrainSprite then
        return false
    end
    
    -- Calculate the natural triangle sprite
    local triangleSprite = DumpTruckOverlays.getGapFillerTriangleSprite(triangleOffset, naturalTerrainSprite)
    if not triangleSprite then
        return false
    end
    
    -- Save original floor sprite for shoveling restoration
    local originalFloor = nonGravelSquare:getFloor()
    local shovelledSprites = nil
    if originalFloor and originalFloor:getSprite() then
        shovelledSprites = {originalFloor:getSprite():getName()}
    end
    
    -- Place GRAVEL floor (now it's a gravel square for shoveling)
    local newFloor = nonGravelSquare:addFloor(DumpTruckConstants.GRAVEL_SPRITE)
    if not newFloor then
        return false
    end
    
    -- Set metadata so it's recognized as gravel and can be shoveled
    local floorModData = newFloor:getModData()
    floorModData.pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
    floorModData.shovelled = nil
    if shovelledSprites then
        floorModData.shovelledSprites = shovelledSprites
    end
    
    -- Add the natural terrain triangle as an overlay object
    DumpTruckOverlays.placeOverlay(nonGravelSquare, triangleSprite, DumpTruckConstants.TILE_TYPES.GAP_FILLER)
    
    -- Disable erosion on this square
    nonGravelSquare:disableErosion()
    
    -- Remove any old edge blend overlays and clear metadata
    DumpTruckOverlays.removeOppositeEdgeBlends(nonGravelSquare)
    
    if nonGravelSquare.transmitFloor then nonGravelSquare:transmitFloor() end
    nonGravelSquare:RecalcProperties()
    nonGravelSquare:DirtySlice()
    
    return true
end

--[[
    placeEdgeBlend: Attaches edge blend sprite to existing gravel floor
    Input:
        gravelSquare: IsoGridSquare - Square with gravel floor
        blendSprite: string - Edge blend sprite to attach (e.g., "blends_natural_01_8")
    Output: boolean - true if successful, false otherwise
]]
function DumpTruckOverlays.placeEdgeBlend(gravelSquare, blendSprite)
    if not gravelSquare or not blendSprite then
        return false
    end
    
    -- Must be a gravel square
    if not DumpTruckCore.isPouredGravel(gravelSquare) then
        return false
    end
    
    -- Get the gravel floor
    local floor = gravelSquare:getFloor()
    if not floor then
        return false
    end
    
    -- Get floor modData for overlay checks
    local floorModData = floor:getModData()
    
    -- Don't place edge blends on gap fillers (they already have natural terrain triangles)
    if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        return false
    end
    
    -- Check if this blend already exists
    if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND and floorModData.overlaySprite == blendSprite then
        return false  -- Already attached
    end
    
    -- Remove old edge blend if different
    if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND and floorModData.overlaySprite and floorModData.overlaySprite ~= blendSprite then
        DumpTruckOverlays.removeOverlay(gravelSquare)
    end
    
    -- Add the blend sprite as an overlay object
    if not DumpTruckOverlays.placeOverlay(gravelSquare, blendSprite, DumpTruckConstants.TILE_TYPES.EDGE_BLEND) then
        return false
    end
    
    if gravelSquare.transmitFloor then gravelSquare:transmitFloor() end
    gravelSquare:RecalcProperties()
    gravelSquare:DirtySlice()
    
    return true
end

-- ROAD SMOOTHING

function DumpTruckOverlays.addEdgeBlends(leftSquare, rightSquare)
    if not leftSquare or not rightSquare then 
        return 
    end
    
    local secondaryDir
    if leftSquare:getX() == rightSquare:getX() then
        -- For east-west roads, determine which direction to use based on Y coordinates
        if leftSquare:getY() > rightSquare:getY() then
            -- Going west: left square is south, right square is north
            secondaryDir = {"SOUTH", "NORTH"}
        else
            -- Going east: left square is north, right square is south
            secondaryDir = {"NORTH", "SOUTH"}
        end
    else
        -- For north-south roads, determine which direction to use based on X coordinates
        if leftSquare:getX() < rightSquare:getX() then
            -- Going south: left square is west, right square is east
            secondaryDir = {"WEST", "EAST"}
        else
            -- Going north: left square is east, right square is west
            secondaryDir = {"EAST", "WEST"}
        end
    end
    
    -- Get the adjacent squares for edge blending
    local leftSideSquare, rightSideSquare
    if secondaryDir[1] == "NORTH" then
        leftSideSquare = leftSquare:getN()
    elseif secondaryDir[1] == "SOUTH" then
        leftSideSquare = leftSquare:getS()
    elseif secondaryDir[1] == "EAST" then
        leftSideSquare = leftSquare:getE()
    elseif secondaryDir[1] == "WEST" then
        leftSideSquare = leftSquare:getW()
    end
    
    if secondaryDir[2] == "NORTH" then
        rightSideSquare = rightSquare:getN()
    elseif secondaryDir[2] == "SOUTH" then
        rightSideSquare = rightSquare:getS()
    elseif secondaryDir[2] == "EAST" then
        rightSideSquare = rightSquare:getE()
    elseif secondaryDir[2] == "WEST" then
        rightSideSquare = rightSquare:getW()
    end
    
    -- Add terrain blends for outer edges
    for i, square in ipairs({leftSquare, rightSquare}) do
        local sideSquare = i == 1 and leftSideSquare or rightSideSquare
        local sideDir = i == 1 and secondaryDir[1] or secondaryDir[2]
        
        if sideSquare then
            -- Check if the adjacent side square doesn't have poured gravel
            if not DumpTruckCore.isPouredGravel(sideSquare) then
                local terrain = DumpTruckOverlays.getBlendNaturalSprite(sideSquare)
                if terrain then
                    local blend = DumpTruckOverlays.getEdgeBlendSprite(sideDir, terrain)
                    if blend then
                        DumpTruckOverlays.placeEdgeBlend(square, blend)
                    end
                end
            end
        end
    end
end

-- GAP FILLING

-- Check if a grass square adjacent to a gravel square forms a corner pattern
function DumpTruckOverlays.checkForCornerPattern(gravelSquare)
    if not gravelSquare or not DumpTruckCore.isFullGravelFloor(gravelSquare) then
        return nil, nil
    end

    -- Check each adjacent square
    local adjacentChecks = {
        {square = gravelSquare:getN(), dir = "NORTH", opposite = "SOUTH"},
        {square = gravelSquare:getS(), dir = "SOUTH", opposite = "NORTH"},
        {square = gravelSquare:getE(), dir = "EAST", opposite = "WEST"},
        {square = gravelSquare:getW(), dir = "WEST", opposite = "EAST"}
    }

    for _, check in ipairs(adjacentChecks) do
        local adjacentSquare = check.square
        if adjacentSquare and not DumpTruckCore.isPouredGravel(adjacentSquare) then
            
            -- Found a non-gravel square, check its other adjacent squares
            local otherAdjacentChecks = {
                {square = adjacentSquare:getN(), dir = "NORTH"},
                {square = adjacentSquare:getS(), dir = "SOUTH"},
                {square = adjacentSquare:getE(), dir = "EAST"},
                {square = adjacentSquare:getW(), dir = "WEST"}
            }

            local gravelCount = 0
            local gravelDirections = {}

            -- First add the direction FROM the grass square TO the original gravel square
            -- This is the opposite of how we found the grass square
            table.insert(gravelDirections, check.opposite)

            -- Then check other adjacent squares from the grass square's perspective
            for _, otherCheck in ipairs(otherAdjacentChecks) do
                -- Skip the direction that points back to our original gravel square
                if otherCheck.dir ~= check.opposite then
                    if otherCheck.square and DumpTruckCore.isFullGravelFloor(otherCheck.square) then
                        gravelCount = gravelCount + 1
                        table.insert(gravelDirections, otherCheck.dir)
                    end
                end
            end

            -- If we found exactly one other gravel floor square, we have a corner pattern
            if gravelCount == 1 then
                -- Look up the appropriate triangle offset in our mapping
                for _, mapping in ipairs(DumpTruckConstants.ADJACENT_TO_BLEND_MAPPING) do
                    local directions = mapping.adjacent_directions
                    
                    -- Check if our gravel directions match this mapping (order doesn't matter)
                    if (gravelDirections[1] == directions[1] and gravelDirections[2] == directions[2]) or
                       (gravelDirections[1] == directions[2] and gravelDirections[2] == directions[1]) then
                        return adjacentSquare, mapping.triangle_offset
                    end
                end
            end
        end
    end

    return nil, nil
end

function DumpTruckOverlays.fillGaps(leftSquare, rightSquare)
    local adjacentSquare1, triangleOffset1 = DumpTruckOverlays.checkForCornerPattern(leftSquare)
    local adjacentSquare2, triangleOffset2 = DumpTruckOverlays.checkForCornerPattern(rightSquare)

    if adjacentSquare1 and triangleOffset1 then
        DumpTruckOverlays.placeGapFiller(adjacentSquare1, triangleOffset1)
    end

    if adjacentSquare2 and triangleOffset2 then
        DumpTruckOverlays.placeGapFiller(adjacentSquare2, triangleOffset2)
    end
end

function DumpTruckOverlays.smoothRoad(currentSquares, fx, fy)
    if #currentSquares < 2 then
        return
    end

    local cz = currentSquares[1]:getZ()
    
    -- Only check the outer edges of the road
    local leftSquare = currentSquares[1]
    local rightSquare = currentSquares[#currentSquares]
    
    -- Fill gaps and add edge blends
    DumpTruckOverlays.fillGaps(leftSquare, rightSquare)
    
    DumpTruckOverlays.addEdgeBlends(leftSquare, rightSquare)
    
    -- Clean up edge blends between pourable squares (after addEdgeBlends)
    for _, square in ipairs(currentSquares) do
        DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(square)
    end
end

return DumpTruckOverlays
