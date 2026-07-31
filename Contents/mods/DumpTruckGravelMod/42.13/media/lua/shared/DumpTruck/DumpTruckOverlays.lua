-- DumpTruckOverlays.lua
-- Edge blends, gap fillers, and overlay management

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")
local DumpTruckOverlayClassify = require("DumpTruck/DumpTruckOverlayClassify")

local DumpTruckOverlays = {}

local CARDINAL_DIRECTIONS = { "NORTH", "SOUTH", "EAST", "WEST" }
local OPPOSITE_DIRECTION = { NORTH = "SOUTH", SOUTH = "NORTH", EAST = "WEST", WEST = "EAST" }

-- CENTRAL OVERLAY METHODS
-- Overlays are attached sprites and nothing else: the engine saves them with the floor
-- (IsoObject.save/load), so there is no metadata to keep.

--[[
    syncOverlayToClients: push this floor's attached sprites to clients, addressed by coordinate.

    The engine's own UpdateItemSprite packet identifies the target by its index in the square's
    object list. A freshly poured square carries client-only objects the server does not have
    (the pour effect's fake floor and speckle overlay), so the index does not line up: the client
    applies the update to the wrong object or drops it, silently in both cases, and nothing
    re-sends it. The blend then stays invisible until a relog rebuilds the square from the server.

    A square's coordinates cannot skew, so the client resolves its own floor and re-attaches.
]]
local function syncOverlayToClients(square, floor)
    sendServerCommand("DumpTruckGravelMod", "syncOverlay", {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        sprites = DumpTruckCore.getAttachedSpriteNames(floor)
    })
end

-- Place overlay on square (gap filler or edge blend)
-- Uses AttachExistingAnim to attach sprite to floor, transmits to MP
function DumpTruckOverlays.placeOverlay(square, sprite)
    if not square or not sprite then
        return false
    end
    local floor = square:getFloor()
    if not floor then
        return false
    end
    local spriteObj = getSprite(sprite)
    if not spriteObj then
        return false
    end
    
    -- Attach sprite to floor using vanilla pattern (see ISShovelGround.lua)
    floor:AttachExistingAnim(spriteObj, 0, 0, false, 0, false, 0.0)
    
    -- Force tile refresh so the attached anim is drawn (SP and MP)
    if floor.DirtySlice then floor:DirtySlice() end
    square:RecalcProperties()
    square:DirtySlice()
    
    -- Sync to MP clients (server only - not needed in SP)
    if isServer() then
        syncOverlayToClients(square, floor)
    end
    
    return true
end

-- Remove overlay from square (gap filler or edge blend)
-- Uses RemoveAttachedAnims to remove all attached sprites
function DumpTruckOverlays.removeOverlay(square)
    if not square then return false end
    
    local floor = square:getFloor()
    if not floor then return false end
    
    -- Remove all attached anims from floor
    floor:RemoveAttachedAnims()
    
    -- Sync to MP clients (server only - not needed in SP)
    if isServer() then
        syncOverlayToClients(square, floor)
    end
    
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

    local floorSprite = floor:getSprite()
    local spriteName = floorSprite and floorSprite:getName()

    if DumpTruckOverlayClassify.isBaseTerrainSprite(spriteName) then
        return spriteName
    end
    
    return nil
end

-- EDGE BLEND HELPERS

-- Helper: Check if square has any blends pointing toward a gravel neighbor
local function hasBlendPointingAtGravel(square, neighborIsGravelByDirection)
    if not square then return false end
    
    local floor = square:getFloor()
    if not floor then return false end

    return DumpTruckOverlayClassify.anyBlendPointsAtGravel(
        DumpTruckCore.getAttachedSpriteNames(floor),
        neighborIsGravelByDirection
    )
end

-- Helper: the four neighbors keyed by the direction they lie in
local function getNeighborsByDirection(square)
    return {
        NORTH = square:getN(),
        SOUTH = square:getS(),
        EAST = square:getE(),
        WEST = square:getW()
    }
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

    local neighbors = getNeighborsByDirection(square)

    -- Check MY blends pointing at neighbors
    local neighborIsGravel = {}
    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbor = neighbors[direction]
        neighborIsGravel[direction] = neighbor ~= nil and DumpTruckCore.isPouredGravel(neighbor)
    end

    if hasBlendPointingAtGravel(square, neighborIsGravel) then
        DumpTruckCore.debugPrint("[DumpTruck] cleanup (", square:getX(), ", ", square:getY(), ", ", square:getZ(), ")")
        DumpTruckOverlays.removeOverlayFromSquare(square)
    end

    -- Check NEIGHBOR blends pointing back at me
    local squareIsGravel = DumpTruckCore.isPouredGravel(square)
    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbor = neighbors[direction]
        if neighbor and DumpTruckCore.isPouredGravel(neighbor) then
            local pointingBackAtMe = { [OPPOSITE_DIRECTION[direction]] = squareIsGravel }
            if hasBlendPointingAtGravel(neighbor, pointingBackAtMe) then
                DumpTruckCore.debugPrint("[DumpTruck] cleanup (", neighbor:getX(), ", ", neighbor:getY(), ", ", neighbor:getZ(), ")")
                DumpTruckOverlays.removeOverlayFromSquare(neighbor)
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
    local offsets = DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS[direction]
    if not offsets then 
        return nil 
    end
    
    -- Randomly choose between the two variations
    local offset = offsets[ZombRand(1, 3)] -- ZombRand(1,3) returns either 1 or 2
    
    return DumpTruckOverlayClassify.getSpriteForOffset(terrainBlock, offset)
end

--[[
    getGapFillerTriangleSprite: Calculates the natural terrain triangle sprite for gap filling
    Input:
        triangleOffset: number - Triangle offset (1-4) from corner pattern mapping
        naturalTerrainSprite: string - Natural terrain sprite (e.g., "blends_natural_01_64")
    Output: string - Natural terrain triangle sprite (e.g., "blends_natural_01_17")
]]
function DumpTruckOverlays.getGapFillerTriangleSprite(triangleOffset, naturalTerrainSprite)
    return DumpTruckOverlayClassify.getSpriteForOffset(naturalTerrainSprite, triangleOffset)
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
    DumpTruckOverlays.placeOverlay(nonGravelSquare, triangleSprite)

    nonGravelSquare:disableErosion()
    if isServer() then
        sendServerCommand("DumpTruckGravelMod", "disableErosionAt", { x = nonGravelSquare:getX(), y = nonGravelSquare:getY(), z = nonGravelSquare:getZ() })
    end

    DumpTruckOverlays.removeOppositeEdgeBlends(nonGravelSquare)
    
    nonGravelSquare:RecalcProperties()
    nonGravelSquare:DirtySlice()

    local oldFloorSpriteName = shovelledSprites and shovelledSprites[1] or nil
    if oldFloorSpriteName then
        local DumpTruckPourEffect = require("DumpTruck/DumpTruckPourEffect")
        DumpTruckPourEffect.scheduleDelayedReveal(nonGravelSquare, oldFloorSpriteName)
    end
    DumpTruckCore.debugPrint("[DumpTruck] gapFiller (", nonGravelSquare:getX(), ", ", nonGravelSquare:getY(), ", ", nonGravelSquare:getZ(), ")")

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

    if not DumpTruckCore.isPouredGravel(gravelSquare) then
        return false
    end

    local floor = gravelSquare:getFloor()
    if not floor then
        return false
    end

    local overlay = DumpTruckCore.classifySquare(gravelSquare)

    -- Never blend over a gap filler triangle
    if overlay and overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        return false
    end

    if overlay and overlay.type == DumpTruckConstants.TILE_TYPES.EDGE_BLEND then
        if overlay.sprite == blendSprite then
            return false
        end
        -- Different blend already attached: replace it
        DumpTruckOverlays.removeOverlay(gravelSquare)
    end

    if not DumpTruckOverlays.placeOverlay(gravelSquare, blendSprite) then
        return false
    end
    DumpTruckCore.debugPrint("[DumpTruck] edgeBlend (", gravelSquare:getX(), ", ", gravelSquare:getY(), ", ", gravelSquare:getZ(), ") ", blendSprite)

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

        if not sideSquare then
            -- skip
        elseif DumpTruckCore.isPouredGravel(sideSquare) then
            -- skip
        else
            local terrain = DumpTruckOverlays.getBlendNaturalSprite(sideSquare)
            if not terrain then
                -- skip
            else
                local blend = DumpTruckOverlays.getEdgeBlendSprite(sideDir, terrain)
                if not blend then
                    -- skip
                else
                    DumpTruckOverlays.placeEdgeBlend(square, blend)
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

    local leftSquare = currentSquares[1]
    local rightSquare = currentSquares[#currentSquares]

    -- Order: gap fillers first, then edge blends, then cleanup
    DumpTruckOverlays.fillGaps(leftSquare, rightSquare)
    DumpTruckOverlays.addEdgeBlends(leftSquare, rightSquare)
    -- Every square in the row, ends included: a blend only counts as stale when it faces
    -- gravel, so the outward blends just placed on the ends are left alone. Squares skipped
    -- as already-gravel are covered too, which heals seams when re-driving beside an old road.
    for i = 1, #currentSquares do
        DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(currentSquares[i])
    end
end

return DumpTruckOverlays
