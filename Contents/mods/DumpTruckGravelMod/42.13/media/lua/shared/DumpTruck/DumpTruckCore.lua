-- DumpTruckCore.lua
-- Core utility functions for the DumpTruck mod

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local DumpTruckCore = {}
DumpTruckCore.debugMode = false

-- Utility function for debug printing
function DumpTruckCore.debugPrint(...)
    if DumpTruckCore.debugMode then
        print("[DEBUG]", ...)
    end
end

-- Check if a square is a full gravel floor (not a blend)
function DumpTruckCore.isFullGravelFloor(square)
    if not square then return false end
    local floor = square:getFloor()
    if not floor then return false end
    
    -- Gap fillers should NOT count as full gravel for corner detection
    -- (prevents cascading gap filler placement)
    local floorModData = floor:getModData()
    if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        return false
    end
    
    -- Check sprite directly for gravel (no metadata needed)
    local floorSprite = floor:getSprite()
    if not floorSprite then return false end
    local spriteName = floorSprite:getName()
    return spriteName == DumpTruckConstants.GRAVEL_SPRITE
end

-- Check if a square is poured gravel
function DumpTruckCore.isPouredGravel(square)
    if not square then return false end
    
    -- Check if it's a full gravel floor
    local isGravel = DumpTruckCore.isFullGravelFloor(square)
    
    -- Check if it's a gap filler (gravel floor with gap filler overlay)
    local floor = square:getFloor()
    local floorModData = floor and floor:getModData()
    local isGapFiller = floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.GAP_FILLER
    
    return isGravel or isGapFiller
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
    if DumpTruckCore.isPouredGravel(sq) then
        -- Allow gap fillers to be upgraded to full gravel squares
        local floor = sq:getFloor()
        local floorModData = floor and floor:getModData()
        if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
            return true  -- Allow gap filler upgrade
        end
        return false  -- Reject full gravel squares
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

return DumpTruckCore
