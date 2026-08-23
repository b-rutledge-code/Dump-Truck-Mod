-- Unit tests for DumpTruckCore.getShovelledSpritesForPour.
-- Plain lua: scripts/run-overlay-tests.sh

local testDir = ((arg and arg[0]) or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = testDir .. "/../Contents/mods/DumpTruckGravelMod/42.20/media/lua/shared/?.lua;" .. package.path

local Classify = require("DumpTruck/DumpTruckOverlayClassify")
local Constants = require("DumpTruck/DumpTruckConstants")

local GRASS = "blends_natural_01_64"
local GRAVEL = Constants.POURABLE_BY_FLOOR_TYPE.gravel.sprite
local TUFT = "blends_grassoverlays_01_5"
local TRIANGLE = "blends_natural_01_17"

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

local function listEq(actual, expected, message)
    if #actual ~= #expected then
        check(false, message .. " (length " .. #actual .. " vs " .. #expected .. ")")
        return
    end
    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            check(false, message .. " (index " .. i .. ": expected " .. expected[i] .. ", got " .. actual[i] .. ")")
            return
        end
    end
    check(true, message)
end

getSprite = function(name)
    return { name = name, getName = function(self) return self.name end }
end

local function makeSquare(floorSprite, modData, attached)
    local floor = {
        attached = attached or {},
        sprite = getSprite(floorSprite),
        modData = modData or {},
        getSprite = function(self) return self.sprite end,
        hasModData = function() return true end,
        getModData = function(self) return self.modData end,
    }
    return {
        floor = floor,
        getFloor = function(self) return self.floor end,
    }
end

-- Stub getAttachedSpriteNames path via fake floor.attached list
package.loaded["DumpTruck/DumpTruckCore"] = nil
local Core = require("DumpTruck/DumpTruckCore")
function Core.getAttachedSpriteNames(floor)
    return floor.attached
end

-- Open grass with a tuft: read from the floor
local grassSq = makeSquare(GRASS, {}, { TUFT })
listEq(Core.getShovelledSpritesForPour(grassSq), { GRASS, TUFT }, "open grass: floor plus attachment")

-- Full gravel road with good shovelledSprites: carry forward, not re-read from gravel floor
local roadSq = makeSquare(GRAVEL, { pouredFloor = "gravel", shovelledSprites = { GRASS, TUFT } }, {})
listEq(Core.getShovelledSpritesForPour(roadSq), { GRASS, TUFT }, "re-pour over road: carry shovelledSprites")

-- Gap filler upgrading to full road: carry shovelledSprites, ignore triangle on attachments
local fillerSq = makeSquare(GRAVEL, { pouredFloor = "gravel", shovelledSprites = { GRASS } }, { TRIANGLE })
listEq(Core.getShovelledSpritesForPour(fillerSq), { GRASS }, "gap filler upgrade: carry shovelledSprites")

-- Gap filler / road with missing or road-valued shovelledSprites: never re-read gravel floor
local bareFillerSq = makeSquare(GRAVEL, { pouredFloor = "gravel" }, { TRIANGLE })
listEq(Core.getShovelledSpritesForPour(bareFillerSq), { "blends_natural_01_64" },
    "gap filler upgrade with no shovelledSprites: dirt fallback, not gravel")

local corruptSq = makeSquare(GRAVEL, { pouredFloor = "gravel", shovelledSprites = { GRAVEL } }, {})
listEq(Core.getShovelledSpritesForPour(corruptSq), { "blends_natural_01_64" },
    "road-valued shovelledSprites on pour: dirt fallback, not gravel floor read")

if #failures > 0 then
    print("shovelledSprites: " .. #failures .. " of " .. checks .. " checks FAILED")
    for _, message in ipairs(failures) do
        print("  - " .. message)
    end
    os.exit(1)
end

print("shovelledSprites: " .. checks .. " checks passed")
