-- DumpTruckCore.lua
-- Core utility functions for the DumpTruck mod

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckOverlayClassify = require("DumpTruck/DumpTruckOverlayClassify")

local DumpTruckCore = {}
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

-- Classify a live square: returns {type, sprite, direction, triangleOffset} or nil
function DumpTruckCore.classifySquare(square)
    if not square then return nil end

    local floor = square:getFloor()
    if not floor then return nil end

    local floorSprite = floor:getSprite()
    if not floorSprite then return nil end

    return DumpTruckOverlayClassify.classify(floorSprite:getName(), DumpTruckCore.getAttachedSpriteNames(floor))
end

-- Check if a square is a full gravel floor (not a blend)
-- Gap fillers do NOT count, so corner detection cannot cascade into them
function DumpTruckCore.isFullGravelFloor(square)
    local overlay = DumpTruckCore.classifySquare(square)
    return overlay ~= nil and overlay.type ~= DumpTruckConstants.TILE_TYPES.GAP_FILLER
end

-- Check if a square is poured gravel (full gravel or a gap filler)
function DumpTruckCore.isPouredGravel(square)
    return DumpTruckCore.classifySquare(square) ~= nil
end

-- Check if square is valid for gravel
function DumpTruckCore.isSquareValidForGravel(sq)
    if not sq then
        return false
    end
    if CFarmingSystem and CFarmingSystem.instance:getLuaObjectOnSquare(sq) then
        return false
    end
    if sq:getProperties() and sq:getProperties():has("water") then
        return false
    end

    local overlay = DumpTruckCore.classifySquare(sq)
    if overlay then
        -- Gap fillers can be upgraded to full gravel; finished gravel is left alone
        return overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER
    end
    return true
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

--[[
    Floor sprite names for shovel restore (vanilla ISNaturalFloor.getFloorSpriteNames).
    Base floor first, then attached anim sprites.
]]
function DumpTruckCore.getFloorSpriteNames(square)
    local sprites = {}
    local floor = square and square:getFloor()
    if not floor then
        return sprites
    end

    local sprite = floor:getSprite()
    if sprite and sprite:getName() then
        table.insert(sprites, sprite:getName())
        local attached = floor:getAttachedAnimSprite()
        if attached then
            for i = 1, attached:size() do
                local parentSprite = attached:get(i - 1):getParentSprite()
                if parentSprite and parentSprite:getName() then
                    table.insert(sprites, parentSprite:getName())
                end
            end
        end
    end
    return sprites
end

-- Local erosion rebind only (no network). Clears nature categories; next/current load binds from floor.
function DumpTruckCore.resetErosionLocal(sq)
    if not sq then
        return
    end

    local erosion = sq:getErosionData()
    if erosion and erosion.reset then
        erosion:reset()
    end

    if ErosionMain and ErosionMain.LoadGridsquare then
        ErosionMain.LoadGridsquare(sq)
    end
end

--[[
    After pour: clear leftover nature erosion and re-bind from the current street floor.
    Replaces disableErosion so StreetCracks can run. Does not strip tall grass / trees.
]]
function DumpTruckCore.rebindErosionAfterPour(sq)
    DumpTruckCore.resetErosionLocal(sq)
    if isServer() then
        sendServerCommand("DumpTruckGravelMod", "resetErosionAt", {
            x = sq:getX(),
            y = sq:getY(),
            z = sq:getZ(),
        })
    end
end

return DumpTruckCore
