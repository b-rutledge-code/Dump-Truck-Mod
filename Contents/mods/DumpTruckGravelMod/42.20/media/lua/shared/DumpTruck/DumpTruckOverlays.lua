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

--[[
    replaceAttachedSprites: rebuild this floor's attached list to exactly `spriteNames`.

    The engine only offers RemoveAttachedAnims (clear all), so any surgical edit is
    clear-then-reattach the keepers. Syncs the resulting list the same way place/remove do.
]]
local function replaceAttachedSprites(square, spriteNames)
    local floor = square:getFloor()
    if not floor then
        return false
    end

    floor:RemoveAttachedAnims()
    for i = 1, #spriteNames do
        local spriteObj = getSprite(spriteNames[i])
        if spriteObj then
            floor:AttachExistingAnim(spriteObj, 0, 0, false, 0, false, 0.0)
        end
    end

    if floor.DirtySlice then floor:DirtySlice() end
    square:RecalcProperties()
    square:DirtySlice()

    if isServer() then
        syncOverlayToClients(square, floor)
    end

    return true
end

--[[
    removeAttachedSprite: drop one attached sprite and keep every other.

    Used when a same-direction blend is replaced or a single stale blend is cleaned up
    without wiping blends on the square's other faces.
]]
function DumpTruckOverlays.removeAttachedSprite(square, spriteName)
    if not square or not spriteName then
        return false
    end

    local floor = square:getFloor()
    if not floor then
        return false
    end

    local attached = DumpTruckCore.getAttachedSpriteNames(floor)
    local keepers = {}
    local found = false
    for i = 1, #attached do
        if attached[i] == spriteName and not found then
            found = true
        else
            table.insert(keepers, attached[i])
        end
    end

    if not found then
        return false
    end

    return replaceAttachedSprites(square, keepers)
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
    removeStaleEdgeBlends: drop only the blend faces that border gravel neighbours.

    Rebuilds the attached list once so blends on other faces (and any non-blend attaches)
    stay put. Full clear remains available via removeOverlay for whole-square resets.
]]
local function removeStaleEdgeBlends(square, neighborIsGravelByDirection)
    if not square then
        return false
    end

    local floor = square:getFloor()
    if not floor then
        return false
    end

    local attached = DumpTruckCore.getAttachedSpriteNames(floor)
    local keepers = {}
    local removedAny = false
    for i = 1, #attached do
        local name = attached[i]
        if DumpTruckOverlayClassify.blendBordersGravel(name, neighborIsGravelByDirection) then
            removedAny = true
        else
            table.insert(keepers, name)
        end
    end

    if not removedAny then
        return false
    end

    DumpTruckCore.debugPrint("[DumpTruck] cleanup (", square:getX(), ", ", square:getY(), ", ", square:getZ(), ")")
    return replaceAttachedSprites(square, keepers)
end

--[[
    removeOppositeEdgeBlends: Removes edge blends between this square and gravel neighbors
    Clears stale-direction blends on this square that border gravel neighbors
    Clears stale-direction blends on gravel neighbors that border this square
]]
function DumpTruckOverlays.removeOppositeEdgeBlends(square)
    if not square then 
        return 
    end

    local neighbors = getNeighborsByDirection(square)

    -- Check MY blends on edges shared with neighbors
    local neighborIsGravel = {}
    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbor = neighbors[direction]
        neighborIsGravel[direction] = neighbor ~= nil and DumpTruckCore.isPouredRoad(neighbor)
    end

    removeStaleEdgeBlends(square, neighborIsGravel)

    -- Check NEIGHBOR blends on the edge they share with me
    local squareIsGravel = DumpTruckCore.isPouredRoad(square)
    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbor = neighbors[direction]
        if neighbor and DumpTruckCore.isPouredRoad(neighbor) then
            local sharedEdgeIsGravel = { [OPPOSITE_DIRECTION[direction]] = squareIsGravel }
            removeStaleEdgeBlends(neighbor, sharedEdgeIsGravel)
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
    placeGapFiller: Places a road floor with natural terrain triangle overlay
    Input:
        nonGravelSquare: IsoGridSquare - Square that doesn't have a road (corner gap)
        triangleOffset: number - Triangle offset (1-4) from corner pattern mapping
        material: string - Poured material of the road that opened this pocket
    Output: boolean - true if successful, false otherwise
]]
function DumpTruckOverlays.placeGapFiller(nonGravelSquare, triangleOffset, material)
    if not nonGravelSquare or not triangleOffset then
        return false
    end

    local pourable = DumpTruckConstants.POURABLE_BY_FLOOR_TYPE[material]
    if not pourable then
        return false
    end
    
    -- Check if already has gravel (don't overwrite)
    if DumpTruckCore.isPouredRoad(nonGravelSquare) then
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
    
    -- Save the ground as it was, floor sprite plus its own attachments, for the shovel
    local shovelledSprites = DumpTruckCore.getRestoreSpriteNames(nonGravelSquare)
    
    -- Place the road floor (now it's a road square for shoveling)
    local newFloor = nonGravelSquare:addFloor(pourable.sprite)
    if not newFloor then
        return false
    end
    
    -- Set metadata so it's recognized as road and can be shoveled
    local floorModData = newFloor:getModData()
    floorModData.pouredFloor = pourable.floorType
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
    convertFullRoadToGapFiller: give a finished road square the complementary triangle.

    The triangle is drawn from the terrain this square was poured over, read from the
    `shovelledSprites` stamp the pour left behind, since the square's own sprite is road now.
    Ground poured over pavement, or road laid before the stamp existed, has no natural
    terrain to cut a triangle from and keeps its solid floor.

    Placement follows `placeGapFiller`: a fresh floor carries the road sprite and its stamps,
    then the triangle attaches to it. The new floor arrives on clients as a whole object with
    no attachments, so the previous edge blend goes with it.

    Input:
        roadSquare: IsoGridSquare - finished full road square on a filler's triangle face
        triangleOffset: number - complementary triangle offset (1-4)
    Output: boolean - true when the square now wears the triangle
]]
function DumpTruckOverlays.convertFullRoadToGapFiller(roadSquare, triangleOffset)
    if not roadSquare or not triangleOffset then
        return false
    end

    local overlay = DumpTruckCore.classifySquare(roadSquare)
    if not overlay then
        return false
    end

    local pourable = DumpTruckConstants.POURABLE_BY_FLOOR_TYPE[overlay.material]
    if not pourable then
        return false
    end

    local floor = roadSquare:getFloor()
    if not floor or not floor:hasModData() then
        return false
    end

    local shovelledSprites = floor:getModData().shovelledSprites
    local naturalTerrainSprite = shovelledSprites and shovelledSprites[1] or nil
    if not DumpTruckOverlayClassify.isBaseTerrainSprite(naturalTerrainSprite) then
        return false
    end

    local triangleSprite = DumpTruckOverlays.getGapFillerTriangleSprite(triangleOffset, naturalTerrainSprite)
    if not triangleSprite then
        return false
    end

    local newFloor = roadSquare:addFloor(pourable.sprite)
    if not newFloor then
        return false
    end

    local floorModData = newFloor:getModData()
    floorModData.pouredFloor = pourable.floorType
    floorModData.shovelled = nil
    -- The whole stamp rides across, so ground that came with its own attachments still
    -- restores them when this square is dug up
    local carriedStamp = {}
    for i = 1, #shovelledSprites do
        carriedStamp[i] = shovelledSprites[i]
    end
    floorModData.shovelledSprites = carriedStamp
    -- Server only: a client floor object has no id the server can resolve, and the unread
    -- payload desyncs the stream. See docs/bugs.md and multiplayer-architecture.
    if isServer() then
        newFloor:transmitModData()
    end

    DumpTruckOverlays.placeOverlay(roadSquare, triangleSprite)

    roadSquare:disableErosion()
    if isServer() then
        sendServerCommand("DumpTruckGravelMod", "disableErosionAt", { x = roadSquare:getX(), y = roadSquare:getY(), z = roadSquare:getZ() })
    end

    DumpTruckOverlays.removeOppositeEdgeBlends(roadSquare)

    roadSquare:RecalcProperties()
    roadSquare:DirtySlice()

    DumpTruckCore.debugPrint("[DumpTruck] gapFillerFromRoad (", roadSquare:getX(), ", ", roadSquare:getY(), ", ", roadSquare:getZ(), ") offset ", triangleOffset)

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

    if not DumpTruckCore.isPouredRoad(gravelSquare) then
        return false
    end

    local floor = gravelSquare:getFloor()
    if not floor then
        return false
    end

    local newDirection = DumpTruckOverlayClassify.getEdgeBlendDirection(blendSprite)
    if not newDirection then
        return false
    end

    local overlay = DumpTruckCore.classifySquare(gravelSquare)

    -- Never blend over a gap filler triangle
    if overlay and overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        return false
    end

    local attached = DumpTruckCore.getAttachedSpriteNames(floor)
    for i = 1, #attached do
        local name = attached[i]
        if name == blendSprite then
            return false
        end
        local existingDirection = DumpTruckOverlayClassify.getEdgeBlendDirection(name)
        if existingDirection == newDirection then
            -- Same face, different sprite (e.g. material change): replace that face only
            DumpTruckOverlays.removeAttachedSprite(gravelSquare, name)
            break
        end
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

--[[
    cardinalsAlong: the cardinal directions a vector points in, strongest first.

    A vector on an axis gives one direction; a diagonal one gives two, the road's dominant
    across axis first. Each exposed face that has terrain beside it takes its own blend.
]]
local function cardinalsAlong(dx, dy)
    local horizontal = (dx > 0 and "EAST") or (dx < 0 and "WEST") or nil
    local vertical = (dy > 0 and "SOUTH") or (dy < 0 and "NORTH") or nil

    if not horizontal then
        return { vertical }
    end
    if not vertical then
        return { horizontal }
    end
    if math.abs(dx) >= math.abs(dy) then
        return { horizontal, vertical }
    end
    return { vertical, horizontal }
end

local function getNeighbour(square, direction)
    if direction == "NORTH" then return square:getN() end
    if direction == "SOUTH" then return square:getS() end
    if direction == "EAST" then return square:getE() end
    if direction == "WEST" then return square:getW() end
    return nil
end

--[[
    blendTowards: border this square against the terrain on one side.

    Reports whether that side was terrain to blend against at all, which is a different
    question from whether the sprite changed: a square already wearing the right blend has
    a finished side, and the caller still counts the face as handled.
]]
local function blendTowards(square, direction)
    local sideSquare = getNeighbour(square, direction)
    if not sideSquare or DumpTruckCore.isPouredRoad(sideSquare) then
        return false
    end

    local terrain = DumpTruckOverlays.getBlendNaturalSprite(sideSquare)
    if not terrain then
        return false
    end

    local blend = DumpTruckOverlays.getEdgeBlendSprite(direction, terrain)
    if blend then
        DumpTruckOverlays.placeEdgeBlend(square, blend)
    end

    return true
end

--[[
    blendFaceTowards: border one road square against named terrain on one named face.

    `addEdgeBlends` reads its directions from a column's shape, which the shovel heal has
    none of: it works outward from a single square the player dug. The terrain is named by
    the caller rather than read from the neighbour, so the heal can blend toward a square it
    knows is open even on a machine whose copy of that square is still catching up.
]]
function DumpTruckOverlays.blendFaceTowards(roadSquare, direction, terrainSprite)
    if not roadSquare or not direction or not terrainSprite then
        return false
    end

    local blend = DumpTruckOverlays.getEdgeBlendSprite(direction, terrainSprite)
    if not blend then
        return false
    end

    return DumpTruckOverlays.placeEdgeBlend(roadSquare, blend)
end

--[[
    addEdgeBlends: border a column's two outer squares against the terrain beside them.

    The vector from the first square to the last is the road's across direction, so the
    first square faces its negation and the last faces it. Taking it from the squares is
    what lets the multiplayer server agree: it smooths a column it receives as bare
    coordinates and never learns which way the truck was pointing.

    A column that runs diagonally offers each end two outward faces instead of one, and on
    a staircase an end square really is exposed on both — each open face gets its own blend.
    A face abutting poured road (including a gap filler) is skipped so the other face still
    receives its blend.
]]
function DumpTruckOverlays.addEdgeBlends(leftSquare, rightSquare)
    if not leftSquare or not rightSquare then
        return
    end

    local acrossX = rightSquare:getX() - leftSquare:getX()
    local acrossY = rightSquare:getY() - leftSquare:getY()

    for _, direction in ipairs(cardinalsAlong(-acrossX, -acrossY)) do
        blendTowards(leftSquare, direction)
    end

    for _, direction in ipairs(cardinalsAlong(acrossX, acrossY)) do
        blendTowards(rightSquare, direction)
    end
end

-- GAP FILLING

--[[
    checkForCornerPattern: find the pocket a corner of this road square leaves open.

    Reports the road's own material alongside the pocket, so the filler is poured from what
    the road beside it is made of. A column can straddle a stripe boundary when one bag runs
    out mid-sweep, so the material belongs to the square that opened the pocket rather than
    to the row as a whole.
]]
function DumpTruckOverlays.checkForCornerPattern(gravelSquare)
    local material = DumpTruckCore.getPouredMaterial(gravelSquare)
    if not material or not DumpTruckCore.isFullRoadFloor(gravelSquare) then
        return nil, nil, nil
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
        if adjacentSquare and not DumpTruckCore.isPouredRoad(adjacentSquare) then
            
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
                    if otherCheck.square and DumpTruckCore.isFullRoadFloor(otherCheck.square) then
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
                        return adjacentSquare, mapping.triangle_offset, material
                    end
                end
            end
        end
    end

    return nil, nil, nil
end

--[[
    fillGaps: place a triangle in every corner pocket this row leaves behind.

    Every square gets checked, not just the row's two ends. A diagonal road's outer
    hull is a staircase, so its pockets sit beside squares in the middle of the row as
    readily as beside the ends.
]]
function DumpTruckOverlays.fillGaps(currentSquares)
    for i = 1, #currentSquares do
        local pocketSquare, triangleOffset, material =
            DumpTruckOverlays.checkForCornerPattern(currentSquares[i])
        if pocketSquare and triangleOffset then
            DumpTruckOverlays.placeGapFiller(pocketSquare, triangleOffset, material)
        end
    end
end

--[[
    healTriangleFaces: put the complementary filler on a filler's two triangle faces.

    Solid road on a triangle face butts a whole tile of gravel against a half tile of grass,
    which reads as a notch bitten out of the road. The complementary filler carries the other
    half of that same square, so the two triangles meet along the shared edge.

    Squares under this pour tick's band stay solid: the truck may have just driven over a
    filler and upgraded it, and a complementary partner outside the column would otherwise
    convert it straight back. Open ground on a triangle face is already the terrain the
    triangle shows, and an open L-pocket there belongs to `fillGaps`, so both are left as
    they are.
]]
local function healTriangleFaces(fillerSquare, triangleOffset, bandSet)
    local oppositeOffset = DumpTruckConstants.GAP_FILLER_OPPOSITE_OFFSET[triangleOffset]
    local faces = DumpTruckConstants.GAP_FILLER_TRIANGLE_FACES[triangleOffset]
    if not oppositeOffset or not faces then
        return
    end

    for _, direction in ipairs(faces) do
        local faceSquare = getNeighbour(fillerSquare, direction)
        if faceSquare and DumpTruckCore.isFullRoadFloor(faceSquare) then
            local key = faceSquare:getX() .. "," .. faceSquare:getY() .. "," .. faceSquare:getZ()
            if not (bandSet and bandSet[key]) then
                DumpTruckOverlays.convertFullRoadToGapFiller(faceSquare, oppositeOffset)
            end
        end
    end
end

--[[
    healGapFillerTriangleFaces: settle the road against every filler this row touches.

    The fillers are gathered before any of them is acted on, so a square that becomes a
    filler during the pass is judged on the next one, when the road around it has settled.
    `bandSet` is the union of every column swept this pour tick; squares in it are not
    converted, so drive-over upgrades and the intentional road spine stay solid.
]]
function DumpTruckOverlays.healGapFillerTriangleFaces(currentSquares, bandSet)
    local fillers = {}

    for i = 1, #currentSquares do
        local square = currentSquares[i]
        if square then
            for _, direction in ipairs(CARDINAL_DIRECTIONS) do
                local neighbour = getNeighbour(square, direction)
                local overlay = neighbour and DumpTruckCore.classifySquare(neighbour)
                if overlay
                        and overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER
                        and overlay.triangleOffset then
                    table.insert(fillers, { square = neighbour, triangleOffset = overlay.triangleOffset })
                end
            end
        end
    end

    for i = 1, #fillers do
        healTriangleFaces(fillers[i].square, fillers[i].triangleOffset, bandSet)
    end
end

-- SHOVEL HEAL

--[[
    fillerKeepsItsArms: does this filler still have the L that earned it?

    A filler's triangle marks the open half of a pocket held by two full-road arms. Dig one
    arm out and the triangle is left describing a corner that no longer exists.
]]
local function fillerKeepsItsArms(fillerSquare, triangleOffset)
    local arms = DumpTruckConstants.GAP_FILLER_ROAD_ARMS[triangleOffset]
    if not arms then
        return false
    end

    for _, direction in ipairs(arms) do
        local armSquare = getNeighbour(fillerSquare, direction)
        if not armSquare or not DumpTruckCore.isFullRoadFloor(armSquare) then
            return false
        end
    end

    return true
end

--[[
    restoreGapFillerToTerrain: give a filler's square back the ground it was cut from.

    Follows the shovel: the stamp's first sprite becomes the floor and the rest attach to it,
    so ground that arrived with its own overlay keeps it. The floor is replaced whole rather
    than repainted, which is what reaches multiplayer clients intact.
]]
function DumpTruckOverlays.restoreGapFillerToTerrain(fillerSquare)
    if not fillerSquare then
        return false
    end

    local floor = fillerSquare:getFloor()
    if not floor or not floor:hasModData() then
        return false
    end

    local stamp = floor:getModData().shovelledSprites
    local terrainSprite = stamp and stamp[1] or nil
    if not DumpTruckOverlayClassify.isBaseTerrainSprite(terrainSprite) then
        return false
    end

    local restoredAttachments = {}
    for i = 2, #stamp do
        table.insert(restoredAttachments, stamp[i])
    end

    local newFloor = fillerSquare:addFloor(terrainSprite)
    if not newFloor then
        return false
    end

    local floorModData = newFloor:getModData()
    floorModData.pouredFloor = nil
    floorModData.shovelledSprites = nil
    floorModData.shovelled = nil
    if isServer() then
        newFloor:transmitModData()
    end

    for i = 1, #restoredAttachments do
        DumpTruckOverlays.placeOverlay(fillerSquare, restoredAttachments[i])
    end

    fillerSquare:RecalcProperties()
    fillerSquare:DirtySlice()

    DumpTruckCore.debugPrint("[DumpTruck] fillerRestored (", fillerSquare:getX(), ", ", fillerSquare:getY(), ", ", fillerSquare:getZ(), ")")

    return true
end

--[[
    settleAfterPlace: settle the road around a square the player just laid by hand.

    Mirror of healAfterShovel with the center treated as new full road instead of a hole:
    L-pockets beside the tile can take fillers (the new tile is an arm), and each open face
    of the new tile gets an edge blend. No triangle-face conversion — that pass belongs to
    the truck's pour band.
]]
function DumpTruckOverlays.settleAfterPlace(roadSquare)
    if not roadSquare then
        return
    end
    -- Hand place just wrote pouredFloor; if classify still misses, keep going from the
    -- square the cursor gave us rather than bailing silently.
    if not DumpTruckCore.isFullRoadFloor(roadSquare) then
        local floor = roadSquare:getFloor()
        local poured = floor and floor:hasModData() and floor:getModData().pouredFloor
        if not DumpTruckConstants.POURABLE_BY_FLOOR_TYPE[poured] then
            return
        end
    end

    DumpTruckCore.debugPrint("[DumpTruck] settleAfterPlace (", roadSquare:getX(), ", ", roadSquare:getY(), ", ", roadSquare:getZ(), ")")

    DumpTruckOverlays.fillGaps({ roadSquare })

    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        blendTowards(roadSquare, direction)
    end

    DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(roadSquare)
    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbour = getNeighbour(roadSquare, direction)
        if neighbour then
            DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(neighbour)
        end
    end
end

--[[
    healAfterShovel: settle the road around a square the player just dug out.

    Runs only after vanilla has restored the dug square (`ISShovelGround:complete`), so the
    hole already reads as open ground. Scope is the hole and its four cardinals — nothing
    further out, and no triangle-face conversion of solid road (that pass belongs to pour).

    Dig does not place gap fillers. New triangles on shovel heal refilled open L-pockets —
    including holes the player had already dug — so progress on a hole never stuck. Fillers
    stay a pour / hand-place settle job. This pass only clears orphan fillers whose arms are
    gone, then reties edge blends into the hole.
]]
function DumpTruckOverlays.healAfterShovel(openSquare)
    if not openSquare then
        return
    end

    local terrainSprite = DumpTruckOverlays.getBlendNaturalSprite(openSquare)
    local neighbours = {}
    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbour = getNeighbour(openSquare, direction)
        if neighbour then
            neighbours[direction] = neighbour
        end
    end

    -- Fillers that lost an arm to the shovel describe a corner that is gone
    for _, neighbour in pairs(neighbours) do
        local overlay = DumpTruckCore.classifySquare(neighbour)
        if overlay
                and overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER
                and overlay.triangleOffset
                and not fillerKeepsItsArms(neighbour, overlay.triangleOffset) then
            DumpTruckOverlays.restoreGapFillerToTerrain(neighbour)
        end
    end

    for _, neighbour in pairs(neighbours) do
        DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(neighbour)
    end

    if terrainSprite then
        for direction, neighbour in pairs(neighbours) do
            if DumpTruckCore.isFullRoadFloor(neighbour) then
                DumpTruckOverlays.blendFaceTowards(neighbour, OPPOSITE_DIRECTION[direction], terrainSprite)
            end
        end
    end
end

function DumpTruckOverlays.smoothRoad(currentSquares, bandSet)
    if #currentSquares < 2 then
        return
    end

    -- Order: gap fillers first, then the road settles against them, then edge blends, then cleanup
    DumpTruckOverlays.fillGaps(currentSquares)

    DumpTruckOverlays.healGapFillerTriangleFaces(currentSquares, bandSet)

    DumpTruckOverlays.addEdgeBlends(currentSquares[1], currentSquares[#currentSquares])

    -- Every square in the row, ends included: a blend only counts as stale when it faces
    -- gravel, so the outward blends just placed on the ends are left alone. Squares skipped
    -- as already-gravel are covered too, which heals seams when re-driving beside an old road.
    for i = 1, #currentSquares do
        DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(currentSquares[i])
    end
end

return DumpTruckOverlays
