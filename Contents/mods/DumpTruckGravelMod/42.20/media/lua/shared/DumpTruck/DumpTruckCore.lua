-- DumpTruckCore.lua
-- Core utility functions for the DumpTruck mod

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckOverlayClassify = require("DumpTruck/DumpTruckOverlayClassify")

local DumpTruckCore = {}
-- Default off; toggle in-game with /dtdebug (see DumpTruckDebugChat.lua)
DumpTruckCore.debugMode = false

-- Utility function for debug printing
function DumpTruckCore.debugPrint(...)
    if DumpTruckCore.debugMode then
        print("[DEBUG]", ...)
    end
end

-- OVERLAY CLASSIFICATION
-- Overlay identity comes from the sprites attached to the floor, which the engine
-- saves and syncs on its own, so this works on a dedicated server and on roads
-- poured before the mod tracked overlays.

-- Names of every sprite attached to a floor (vanilla pattern, see ISNaturalFloor.getFloorSpriteNames)
function DumpTruckCore.getAttachedSpriteNames(floor)
    local names = {}
    if not floor or not floor:hasAttachedAnimSprites() then
        return names
    end

    local attached = floor:getAttachedAnimSprite()
    if not attached then
        return names
    end

    for i = 1, attached:size() do
        local instance = attached:get(i - 1)
        local parentSprite = instance and instance:getParentSprite()
        local name = parentSprite and parentSprite:getName()
        if name then
            table.insert(names, name)
        end
    end

    return names
end

--[[
    getRestoreSpriteNames: what the shovel puts back when this square's road is dug up.

    The floor's own sprite first, then the sprites attached to it, which is the order
    vanilla's ISNaturalFloor.getFloorSpriteNames writes and ISShovelGround reads back.
    Capturing the attachments is what preserves ground that came with its own overlay, a
    grass tuft or a puddle, instead of restoring a bare tile.

    Our own overlays are left out: a blend or a triangle belongs to the road, not to the
    ground beneath it, and restoring one would put road decoration on open terrain.
]]
function DumpTruckCore.getRestoreSpriteNames(square)
    if not square then
        return nil
    end

    local floor = square:getFloor()
    if not floor then
        return nil
    end

    local sprite = floor:getSprite()
    local baseName = sprite and sprite:getName()
    if not baseName then
        return nil
    end

    local names = { baseName }
    local attached = DumpTruckCore.getAttachedSpriteNames(floor)
    for i = 1, #attached do
        local name = attached[i]
        if not DumpTruckOverlayClassify.getEdgeBlendDirection(name)
                and not DumpTruckOverlayClassify.getGapFillerOffset(name) then
            table.insert(names, name)
        end
    end

    return names
end

--[[
    getShovelledSpritesForPour: the shovelledSprites to write on a floor this pour replaces.

    Open ground is read from the floor sprite and its attachments via getRestoreSpriteNames.

    A square that is already poured road (full or gap filler) must never re-read its floor:
    that sprite is road, and writing it into shovelledSprites makes the first dig put gravel
    back. Carry a good existing list; if there is none, use vanilla's dig-to-dirt sprite so
    a gap-filler upgrade cannot record gravel as the ground beneath the road.
]]
function DumpTruckCore.getShovelledSpritesForPour(square)
    if not square then
        return nil
    end

    local floor = square:getFloor()
    if floor and floor:hasModData() then
        local existing = floor:getModData().shovelledSprites
        if existing and existing[1]
                and DumpTruckOverlayClassify.isBaseTerrainSprite(existing[1]) then
            local carried = {}
            for i = 1, #existing do
                carried[i] = existing[i]
            end
            return carried
        end
    end

    if DumpTruckCore.isPouredRoad(square) then
        return { "blends_natural_01_64" }
    end

    return DumpTruckCore.getRestoreSpriteNames(square)
end

-- The floor's `pouredFloor` stamp, or nil on ground nobody has poured
function DumpTruckCore.getPouredFloorStamp(floor)
    if not floor or not floor:hasModData() then
        return nil
    end
    return floor:getModData().pouredFloor
end

-- Classify a live square: returns {type, material, sprite, direction, triangleOffset} or nil
function DumpTruckCore.classifySquare(square)
    if not square then return nil end

    local floor = square:getFloor()
    if not floor then return nil end

    local floorSprite = floor:getSprite()
    if not floorSprite then return nil end

    return DumpTruckOverlayClassify.classify(
        floorSprite:getName(),
        DumpTruckCore.getAttachedSpriteNames(floor),
        DumpTruckCore.getPouredFloorStamp(floor)
    )
end

-- Which material a square's road was poured from, or nil when it is not a road of ours
function DumpTruckCore.getPouredMaterial(square)
    local overlay = DumpTruckCore.classifySquare(square)
    return overlay and overlay.material or nil
end

-- Check if a square is a full road floor of any material (not a blend)
-- Gap fillers do NOT count, so corner detection cannot cascade into them: each filler a
-- corner check can see is a corner the next tick can build on, and the road grows a fresh
-- row of teeth down its side every pass
function DumpTruckCore.isFullRoadFloor(square)
    local overlay = DumpTruckCore.classifySquare(square)
    return overlay ~= nil and overlay.type ~= DumpTruckConstants.TILE_TYPES.GAP_FILLER
end

-- Check if a square is a poured road of any material (full floor or a gap filler)
function DumpTruckCore.isPouredRoad(square)
    return DumpTruckCore.classifySquare(square) ~= nil
end

--[[
    isSquareOpenGround: ground the truck is allowed to act on at all.

    Mirrors the checks vanilla's own ISNaturalFloor:isValid makes before spilling a bag, so
    the truck refuses the squares a player pouring by hand would be refused.
]]
function DumpTruckCore.isSquareOpenGround(sq)
    if not sq then
        return false
    end
    if CFarmingSystem and CFarmingSystem.instance:getLuaObjectOnSquare(sq) then
        return false
    end
    if sq:getProperties() and sq:getProperties():has("water") then
        return false
    end
    return true
end

--[[
    isSquareValidForPour: can this material go here?

    Same rule as vanilla ISNaturalFloor:isValid — refuse only when the square is already a
    finished pour of this material. That is what stops a dump tick from charging again for
    tiles the band still covers before the truck leaves them. A different material is allowed
    through, so dirt can bury a gravel road on a later pass.

    Gap fillers of any material can still be upgraded to a full floor: they are unfinished
    corners, not a finished surface to protect.
]]
function DumpTruckCore.isSquareValidForPour(sq, floorType)
    if not DumpTruckCore.isSquareOpenGround(sq) then
        return false
    end

    local overlay = DumpTruckCore.classifySquare(sq)
    if not overlay then
        return true
    end
    if overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        return true
    end
    return overlay.material ~= floorType
end

-- Get forward vector from vehicle driver
function DumpTruckCore.getVectorFromPlayer(vehicle)
    local driver = vehicle:getDriver()
    if driver == nil then
        return nil, nil
    end

    local vector = Vector2.new()
    driver:getForwardDirection(vector)

    return vector:getX(), vector:getY()
end

return DumpTruckCore
