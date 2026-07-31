-- Unit tests for DumpTruck/DumpTruckOverlayClassify.
-- Plain lua, no game required: `lua tests/overlay_classify_test.lua` from anywhere,
-- or scripts/run-overlay-tests.sh.

local testDir = ((arg and arg[0]) or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = testDir .. "/../Contents/mods/DumpTruckGravelMod/42.20/media/lua/shared/?.lua;" .. package.path

local Classify = require("DumpTruck/DumpTruckOverlayClassify")
local Constants = require("DumpTruck/DumpTruckConstants")

local GRAVEL = Constants.GRAVEL_SPRITE
local TILE_TYPES = Constants.TILE_TYPES

local failures = {}
local checks = 0

local function check(ok, message)
    checks = checks + 1
    if not ok then
        table.insert(failures, message)
    end
end

local function equals(actual, expected, message)
    check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

-- Grass row 64-79 and a second row 16-31 to prove the math is not hardcoded to one terrain
local GRASS = "blends_natural_01_64"
local GRASS_VARIANT = "blends_natural_01_70"
local OTHER_ROW = "blends_natural_01_21"

-- Edge blend ids map to the cardinal they face, in both row variants
for direction, offsets in pairs(Constants.EDGE_BLEND_DIRECTION_OFFSETS) do
    for _, offset in ipairs(offsets) do
        equals(
            Classify.getEdgeBlendDirection("blends_natural_01_" .. offset),
            direction,
            "row 0 offset " .. offset .. " faces " .. direction
        )
        equals(
            Classify.getEdgeBlendDirection("blends_natural_01_" .. (64 + offset)),
            direction,
            "row 64 offset " .. offset .. " faces " .. direction
        )
    end
end

-- Gap filler triangles are offsets 1-4; edge blends are 8-15. The bands must not overlap.
for offset = 1, 4 do
    equals(Classify.getGapFillerOffset("blends_natural_01_" .. (64 + offset)), offset, "offset " .. offset .. " is a gap filler")
    equals(Classify.getEdgeBlendDirection("blends_natural_01_" .. (64 + offset)), nil, "offset " .. offset .. " is not an edge blend")
end
for offset = 8, 15 do
    equals(Classify.getGapFillerOffset("blends_natural_01_" .. (64 + offset)), nil, "offset " .. offset .. " is not a gap filler")
    check(Classify.getEdgeBlendDirection("blends_natural_01_" .. (64 + offset)) ~= nil, "offset " .. offset .. " is an edge blend")
end

-- Gap filler triangle sprite from terrain base + offset, with variants normalized to the row
equals(Classify.getSpriteForOffset(GRASS, 1), "blends_natural_01_65", "triangle 1 on grass row")
equals(Classify.getSpriteForOffset(GRASS_VARIANT, 1), "blends_natural_01_65", "grass variant normalizes to same row")
equals(Classify.getSpriteForOffset(OTHER_ROW, 3), "blends_natural_01_19", "triangle 3 on row 16")
equals(Classify.getSpriteForOffset("floors_exterior_natural_1", 1), nil, "non-blend terrain has no row")
equals(Classify.getSpriteForOffset(GRASS, nil), nil, "nil offset yields no sprite")

-- Base terrain detection gates which squares can take a blend at all
for _, offset in ipairs({ 0, 5, 6, 7 }) do
    check(Classify.isBaseTerrainSprite("blends_natural_01_" .. (64 + offset)), "offset " .. offset .. " is base terrain")
end
for _, offset in ipairs({ 1, 4, 8, 12, 15 }) do
    check(not Classify.isBaseTerrainSprite("blends_natural_01_" .. (64 + offset)), "offset " .. offset .. " is not base terrain")
end

-- classify: floor sprite plus attached names, no modData anywhere
equals(Classify.classify(GRAVEL, {}).type, TILE_TYPES.GRAVEL, "bare gravel floor")
equals(Classify.classify(GRAVEL, nil).type, TILE_TYPES.GRAVEL, "gravel floor with no attach list")
equals(Classify.classify(GRAVEL, { "blends_natural_01_72" }).type, TILE_TYPES.EDGE_BLEND, "gravel + blend is an edge blend")
equals(Classify.classify(GRAVEL, { "blends_natural_01_72" }).direction, "NORTH", "attached offset 8 faces north")
equals(Classify.classify(GRAVEL, { "blends_natural_01_65" }).type, TILE_TYPES.GAP_FILLER, "gravel + triangle is a gap filler")
equals(Classify.classify(GRAVEL, { "blends_natural_01_65" }).triangleOffset, 1, "gap filler keeps its triangle offset")
equals(Classify.classify(GRASS, { "blends_natural_01_72" }), nil, "non-gravel floor is not ours")
equals(Classify.classify(nil, nil), nil, "nil floor sprite is not ours")

-- Existing roads carry no modData at all: a gravel floor with an attached blend still classifies
local existingRoad = Classify.classify(GRAVEL, { "blends_natural_01_75" })
equals(existingRoad.type, TILE_TYPES.EDGE_BLEND, "existing road blend classifies from sprites alone")
equals(existingRoad.sprite, "blends_natural_01_75", "classify reports which sprite it matched")

-- Unrecognized and malformed attachments are ignored rather than misclassified
equals(Classify.classify(GRAVEL, { "f_wallvines_1_39", "dumptruck_pour_01" }).type, TILE_TYPES.GRAVEL, "unknown attachments do not classify")
equals(Classify.classify(GRAVEL, { false, 42, "blends_natural_01_72" }).type, TILE_TYPES.EDGE_BLEND, "malformed entries are skipped")
equals(Classify.getEdgeBlendDirection("blends_natural_01_72_extra"), nil, "trailing junk does not match")
equals(Classify.getEdgeBlendDirection("mymod_natural_01_72"), nil, "other tilesets do not match")

-- blendBordersGravel: a blend is stale only when its own edge is shared with gravel
local northBlend = "blends_natural_01_72"
check(Classify.blendBordersGravel(northBlend, { NORTH = true }), "north blend bordering gravel is stale")
check(not Classify.blendBordersGravel(northBlend, { NORTH = false }), "north blend bordering terrain is kept")
check(not Classify.blendBordersGravel(northBlend, { SOUTH = true, EAST = true, WEST = true }), "gravel on other sides does not matter")
check(not Classify.blendBordersGravel("blends_natural_01_65", { NORTH = true }), "a gap filler triangle never borders gravel")
check(not Classify.blendBordersGravel(northBlend, nil), "missing neighbor map is not a match")

-- End of a road row: the blend sits on the outward grass edge while gravel continues behind it,
-- so widening cleanup to the row ends cannot strip the blend we just placed.
local rowEndNeighbors = { WEST = false, EAST = true, NORTH = false, SOUTH = false }
local westFacingBlend = "blends_natural_01_73"
equals(Classify.getEdgeBlendDirection(westFacingBlend), "WEST", "offset 9 is the west edge")
check(not Classify.anyBlendBordersGravel({ westFacingBlend }, rowEndNeighbors), "outward end-of-row blend survives cleanup")
check(Classify.anyBlendBordersGravel({ "blends_natural_01_74" }, rowEndNeighbors), "inward blend over gravel is stripped")
check(not Classify.anyBlendBordersGravel(nil, rowEndNeighbors), "no attachments means nothing to strip")

if #failures > 0 then
    print(#failures .. " of " .. checks .. " checks FAILED:")
    for _, message in ipairs(failures) do
        print("  - " .. message)
    end
    os.exit(1)
end

print("overlay classify: " .. checks .. " checks passed")
