-- DumpTruckOverlayClassify.lua
-- Sprite-name math for gravel overlays: which tile in a blends_natural row means what.
--
-- Pure Lua: strings and tables only, no game globals, so tests/overlay_classify_test.lua
-- can run it under plain `lua`. Live-square adapters live in DumpTruckCore.

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local DumpTruckOverlayClassify = {}

local TILES_PER_ROW = 16
local GAP_FILLER_OFFSET_MIN = 1
local GAP_FILLER_OFFSET_MAX = 4

-- Row positions that are whole-tile terrain rather than a blend or triangle
local BASE_TERRAIN_OFFSETS = { [0] = true, [5] = true, [6] = true, [7] = true }

-- In-row offset -> the cardinal edge that blend is drawn on
local DIRECTION_BY_OFFSET = {}
for direction, offsets in pairs(DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS) do
    for _, offset in ipairs(offsets) do
        DIRECTION_BY_OFFSET[offset] = direction
    end
end

local SPRITE_PATTERN = "^" .. DumpTruckConstants.EDGE_BLEND_SPRITES .. "_(%d+)$"

-- Tile number of a blends_natural sprite, or nil if the name is not one
function DumpTruckOverlayClassify.getTileNumber(spriteName)
    if type(spriteName) ~= "string" then
        return nil
    end
    return tonumber(spriteName:match(SPRITE_PATTERN))
end

-- Position 0-15 within the sprite's row of 16
function DumpTruckOverlayClassify.getInRowOffset(spriteName)
    local tileNumber = DumpTruckOverlayClassify.getTileNumber(spriteName)
    if not tileNumber then
        return nil
    end
    return tileNumber % TILES_PER_ROW
end

-- First tile of the sprite's row, so every variant of one terrain normalizes to the same base
function DumpTruckOverlayClassify.getRowStart(spriteName)
    local tileNumber = DumpTruckOverlayClassify.getTileNumber(spriteName)
    if not tileNumber then
        return nil
    end
    return math.floor(tileNumber / TILES_PER_ROW) * TILES_PER_ROW
end

-- Sprite at an offset within the same row as terrainSpriteName
function DumpTruckOverlayClassify.getSpriteForOffset(terrainSpriteName, offset)
    if type(offset) ~= "number" then
        return nil
    end
    local rowStart = DumpTruckOverlayClassify.getRowStart(terrainSpriteName)
    if not rowStart then
        return nil
    end
    return DumpTruckConstants.EDGE_BLEND_SPRITES .. "_" .. (rowStart + offset)
end

-- True when the sprite is a full terrain tile we can blend against
function DumpTruckOverlayClassify.isBaseTerrainSprite(spriteName)
    local offset = DumpTruckOverlayClassify.getInRowOffset(spriteName)
    return offset ~= nil and BASE_TERRAIN_OFFSETS[offset] == true
end

-- Cardinal edge an edge-blend sprite faces, or nil when the sprite is not an edge blend
function DumpTruckOverlayClassify.getEdgeBlendDirection(spriteName)
    local offset = DumpTruckOverlayClassify.getInRowOffset(spriteName)
    if not offset then
        return nil
    end
    return DIRECTION_BY_OFFSET[offset]
end

-- Triangle offset 1-4 of a gap filler sprite, or nil when the sprite is not one
function DumpTruckOverlayClassify.getGapFillerOffset(spriteName)
    local offset = DumpTruckOverlayClassify.getInRowOffset(spriteName)
    if not offset then
        return nil
    end
    if offset >= GAP_FILLER_OFFSET_MIN and offset <= GAP_FILLER_OFFSET_MAX then
        return offset
    end
    return nil
end

--[[
    classify: What a floor is, from its own sprite plus the sprites attached to it.
    Input:
        floorSpriteName: string - the floor's own sprite
        attachedSpriteNames: table - array of attached sprite names (may be nil or empty)
    Output: table {type, sprite, direction, triangleOffset} for our tiles, nil for anything else
]]
function DumpTruckOverlayClassify.classify(floorSpriteName, attachedSpriteNames)
    if floorSpriteName ~= DumpTruckConstants.GRAVEL_SPRITE then
        return nil
    end

    if attachedSpriteNames then
        for i = 1, #attachedSpriteNames do
            local spriteName = attachedSpriteNames[i]

            local triangleOffset = DumpTruckOverlayClassify.getGapFillerOffset(spriteName)
            if triangleOffset then
                return {
                    type = DumpTruckConstants.TILE_TYPES.GAP_FILLER,
                    sprite = spriteName,
                    triangleOffset = triangleOffset
                }
            end

            local direction = DumpTruckOverlayClassify.getEdgeBlendDirection(spriteName)
            if direction then
                return {
                    type = DumpTruckConstants.TILE_TYPES.EDGE_BLEND,
                    sprite = spriteName,
                    direction = direction
                }
            end
        end
    end

    return { type = DumpTruckConstants.TILE_TYPES.GRAVEL }
end

--[[
    blendPointsAtGravel: Is this blend facing a neighbor that is already gravel?
    A blend belongs on a gravel-to-terrain edge, so one facing gravel is a stale seam.
    Input:
        blendSpriteName: string - attached sprite to test
        neighborIsGravelByDirection: table - {NORTH = bool, SOUTH = bool, EAST = bool, WEST = bool}
    Output: boolean
]]
function DumpTruckOverlayClassify.blendPointsAtGravel(blendSpriteName, neighborIsGravelByDirection)
    if not neighborIsGravelByDirection then
        return false
    end
    local direction = DumpTruckOverlayClassify.getEdgeBlendDirection(blendSpriteName)
    if not direction then
        return false
    end
    return neighborIsGravelByDirection[direction] == true
end

-- blendPointsAtGravel across every sprite attached to one floor
function DumpTruckOverlayClassify.anyBlendPointsAtGravel(attachedSpriteNames, neighborIsGravelByDirection)
    if not attachedSpriteNames then
        return false
    end
    for i = 1, #attachedSpriteNames do
        if DumpTruckOverlayClassify.blendPointsAtGravel(attachedSpriteNames[i], neighborIsGravelByDirection) then
            return true
        end
    end
    return false
end

return DumpTruckOverlayClassify
