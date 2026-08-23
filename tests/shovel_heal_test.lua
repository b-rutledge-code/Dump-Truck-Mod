-- Unit tests for DumpTruckOverlays.healAfterShovel and the stamps it restores from.
-- Plain lua, no game required: `lua tests/shovel_heal_test.lua` from anywhere,
-- or scripts/run-overlay-tests.sh.
--
-- Floors here carry real modData, because the heal reads the `shovelledSprites` stamp a
-- pour leaves behind. `shovel()` below does what vanilla ISShovelGround:shovelGround does,
-- so the tests exercise the heal against ground the game has already restored, and against
-- ground that has not been restored yet, which is what a multiplayer server sees.

local testDir = ((arg and arg[0]) or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = testDir .. "/../Contents/mods/DumpTruckGravelMod/42.20/media/lua/shared/?.lua;" .. package.path

local Classify = require("DumpTruck/DumpTruckOverlayClassify")
local Constants = require("DumpTruck/DumpTruckConstants")

local GRASS = "blends_natural_01_64"
local GRASS_TUFT = "blends_grassoverlays_01_5"

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

-- FAKE WORLD

isServer = function() return false end
ZombRand = function() return 1 end
getSprite = function(name)
    return { name = name, getName = function(self) return self.name end }
end

local world

local function makeFloor(spriteName, modData)
    return {
        attached = {},
        sprite = getSprite(spriteName),
        modData = modData or {},
        getSprite = function(self) return self.sprite end,
        setSprite = function(self, spriteObj) self.sprite = spriteObj end,
        AttachExistingAnim = function(self, spriteObj)
            table.insert(self.attached, spriteObj:getName())
        end,
        RemoveAttachedAnims = function(self) self.attached = {} end,
        DirtySlice = function() end,
        hasModData = function() return true end,
        getModData = function(self) return self.modData end,
        transmitModData = function() end
    }
end

local function makeSquare(x, y)
    return {
        x = x, y = y, floor = makeFloor(GRASS),
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function() return 0 end,
        getFloor = function(self) return self.floor end,
        getN = function(self) return world[self.x .. "," .. (self.y - 1)] end,
        getS = function(self) return world[self.x .. "," .. (self.y + 1)] end,
        getE = function(self) return world[(self.x + 1) .. "," .. self.y] end,
        getW = function(self) return world[(self.x - 1) .. "," .. self.y] end,
        addFloor = function(self, spriteName)
            self.floor = makeFloor(spriteName)
            return self.floor
        end,
        disableErosion = function() end,
        RecalcProperties = function() end,
        DirtySlice = function() end
    }
end

-- A 9x9 patch of grass, road painted on afterwards
local function newWorld()
    world = {}
    for x = 6, 14 do
        for y = 6, 14 do
            world[x .. "," .. y] = makeSquare(x, y)
        end
    end
    return world
end

local function at(x, y) return world[x .. "," .. y] end

-- Pave the way a pour leaves the square: road sprite, poured stamp, and the ground it
-- covered recorded for the shovel
local function pave(x, y, floorType)
    local pourable = Constants.POURABLE_BY_FLOOR_TYPE[floorType or "gravel"]
    local square = at(x, y)
    square.floor = makeFloor(pourable.sprite, {
        pouredFloor = pourable.floorType,
        shovelledSprites = { GRASS }
    })
    return square
end

local function attachedOf(square) return square:getFloor().attached end

local function blendDirections(square)
    local dirs = {}
    for _, name in ipairs(attachedOf(square)) do
        local direction = Classify.getEdgeBlendDirection(name)
        if direction then
            table.insert(dirs, direction)
        end
    end
    return dirs
end

local function hasBlendDirection(square, direction)
    for _, d in ipairs(blendDirections(square)) do
        if d == direction then
            return true
        end
    end
    return false
end

local function sortedDirs(dirs)
    local copy = {}
    for i = 1, #dirs do copy[i] = dirs[i] end
    table.sort(copy)
    return table.concat(copy, ",")
end

local function equalsDirs(square, expected, message)
    equals(sortedDirs(blendDirections(square)), sortedDirs(expected), message)
end

local function classifySquare(square)
    if not square then return nil end
    local floor = square:getFloor()
    return Classify.classify(floor:getSprite():getName(), floor.attached, floor.modData.pouredFloor)
end

package.loaded["DumpTruck/DumpTruckCore"] = {
    isPouredRoad = function(square) return classifySquare(square) ~= nil end,
    isFullRoadFloor = function(square)
        local overlay = classifySquare(square)
        return overlay ~= nil and overlay.type ~= Constants.TILE_TYPES.GAP_FILLER
    end,
    getPouredMaterial = function(square)
        local overlay = classifySquare(square)
        return overlay and overlay.material or nil
    end,
    getAttachedSpriteNames = function(floor) return floor.attached end,
    getPouredFloorStamp = function(floor) return floor.modData.pouredFloor end,
    getRestoreSpriteNames = function(square)
        local floor = square and square:getFloor()
        if not floor then return nil end
        local names = { floor:getSprite():getName() }
        for _, name in ipairs(floor.attached) do
            if not Classify.getEdgeBlendDirection(name) and not Classify.getGapFillerOffset(name) then
                table.insert(names, name)
            end
        end
        return names
    end,
    classifySquare = classifySquare,
    debugPrint = function() end
}

-- The pour effect is a client-only visual with no bearing on overlay geometry
package.loaded["DumpTruck/DumpTruckPourEffect"] = {
    scheduleDelayedReveal = function() end
}

local Overlays = require("DumpTruck/DumpTruckOverlays")

-- What vanilla ISShovelGround:shovelGround does to the dug square: attachments off, the
-- stamp's ground back on, road metadata gone
local function shovel(x, y)
    local square = at(x, y)
    local floor = square:getFloor()
    local stamp = floor.modData.shovelledSprites
    floor:RemoveAttachedAnims()
    if stamp then
        floor.sprite = getSprite(stamp[1])
        for i = 2, #stamp do
            floor:AttachExistingAnim(getSprite(stamp[i]))
        end
    end
    floor.modData.shovelledSprites = nil
    floor.modData.pouredFloor = nil
    return square
end

-- STAMPS: the shovel gets back the ground that was here, attachments included

newWorld()
table.insert(at(10, 10):getFloor().attached, GRASS_TUFT)
pave(11, 10)
pave(10, 11)
pave(11, 11)
check(Overlays.placeGapFiller(at(10, 10), 1, "gravel"), "gap filler placed over grass wearing a tuft")
local stamp = at(10, 10):getFloor().modData.shovelledSprites
equals(#stamp, 2, "gap filler stamp records ground sprite and its attachment")
equals(stamp[1], GRASS, "stamp starts with the floor sprite")
equals(stamp[2], GRASS_TUFT, "stamp carries the ground's own attachment")

-- The triangle the filler wears is the road's, not the ground's, so it stays out of the stamp
local fillerOverlay = classifySquare(at(10, 10))
equals(fillerOverlay and fillerOverlay.type, Constants.TILE_TYPES.GAP_FILLER, "filler classifies as a gap filler")
equals(#at(10, 10):getFloor().modData.shovelledSprites, 2, "the filler's own triangle is not stamped")

-- CENTRE TILE: every face around the hole takes a blend

newWorld()
for x = 9, 11 do
    for y = 9, 11 do
        pave(x, y)
    end
end
shovel(10, 10)
Overlays.healAfterShovel(at(10, 10))
equals(classifySquare(at(10, 10)), nil, "the dug square is open ground")
equalsDirs(at(10, 9), { "SOUTH" }, "north neighbour blends toward the hole")
equalsDirs(at(10, 11), { "NORTH" }, "south neighbour blends toward the hole")
equalsDirs(at(11, 10), { "WEST" }, "east neighbour blends toward the hole")
equalsDirs(at(9, 10), { "EAST" }, "west neighbour blends toward the hole")

-- Running the heal twice stacks nothing
local settled = #attachedOf(at(10, 9))
Overlays.healAfterShovel(at(10, 10))
equals(#attachedOf(at(10, 9)), settled, "repeat heal: no duplicate blends stacked on")

-- A dig does not convert solid road into gap fillers (pour-only triangle-face heal)
newWorld()
for x = 9, 11 do
    for y = 9, 11 do
        pave(x, y)
    end
end
shovel(10, 10)
Overlays.healAfterShovel(at(10, 10))
for x = 9, 11 do
    for y = 9, 11 do
        if not (x == 10 and y == 10) then
            local overlay = classifySquare(at(x, y))
            check(overlay ~= nil and overlay.type ~= Constants.TILE_TYPES.GAP_FILLER,
                "dig does not convert solid road at " .. x .. "," .. y)
        end
    end
end

-- EDGE TILE: the hole-facing blend arrives beside the outward blend already there

newWorld()
local stripFirst = pave(10, 9)
pave(10, 10)
local stripLast = pave(10, 11)
Overlays.addEdgeBlends(stripFirst, stripLast)
equalsDirs(stripFirst, { "NORTH" }, "strip end starts with its outward blend")
shovel(10, 10)
Overlays.healAfterShovel(at(10, 10))
equalsDirs(stripFirst, { "NORTH", "SOUTH" }, "strip end keeps its outward blend and gains the hole face")
equalsDirs(stripLast, { "SOUTH", "NORTH" }, "other strip end keeps its outward blend too")

-- SPUR END: one road neighbour, one blend

newWorld()
pave(10, 10)
pave(10, 11)
shovel(10, 11)
Overlays.healAfterShovel(at(10, 11))
equalsDirs(at(10, 10), { "SOUTH" }, "spur end: the one surviving road square blends the hole face")

-- LAST TILE: nothing left to heal against

newWorld()
pave(10, 10)
shovel(10, 10)
Overlays.healAfterShovel(at(10, 10))
equals(classifySquare(at(10, 10)), nil, "last tile: the square is open ground")
equals(#attachedOf(at(10, 9)), 0, "last tile: neighbouring terrain takes no blend")
equals(#attachedOf(at(9, 10)), 0, "last tile: no blend on terrain to the west")

-- DUG FILLER: dig heal never places fillers, so the triangle does not come back

newWorld()
pave(11, 10)
pave(10, 11)
pave(11, 11)
check(Overlays.placeGapFiller(at(10, 10), 1, "gravel"), "pocket filled before the shovel")
shovel(10, 10)
Overlays.healAfterShovel(at(10, 10))
equals(classifySquare(at(10, 10)), nil, "dug filler stays open ground")
equals(#attachedOf(at(10, 10)), 0, "dug filler keeps no triangle")
check(hasBlendDirection(at(10, 11), "NORTH"), "road south of the dug filler blends the hole face")
check(hasBlendDirection(at(11, 10), "WEST"), "road east of the dug filler blends the hole face")

-- TWO-NEIGHBOUR HOLE: still an L-pocket geometrically, dig heal still places no triangle
newWorld()
pave(11, 10)
pave(10, 11)
pave(10, 10)
shovel(10, 10)
Overlays.healAfterShovel(at(10, 10))
equals(classifySquare(at(10, 10)), nil, "two-neighbour hole stays open terrain")
equals(#attachedOf(at(10, 10)), 0, "two-neighbour hole gets no triangle")

-- DUG ARM: a filler that lost an arm goes back to terrain

newWorld()
pave(11, 10)
pave(10, 11)
pave(11, 11)
check(Overlays.placeGapFiller(at(10, 10), 1, "gravel"), "pocket filled before the arm is dug")
shovel(11, 10)
Overlays.healAfterShovel(at(11, 10))
equals(classifySquare(at(10, 10)), nil, "orphaned filler is terrain again")
equals(#attachedOf(at(10, 10)), 0, "orphaned filler carries no triangle")
equals(at(10, 10):getFloor():getSprite():getName(), GRASS, "orphaned filler wears its stamped ground")
equals(at(10, 10):getFloor().modData.pouredFloor, nil, "orphaned filler is no longer stamped as road")
check(hasBlendDirection(at(11, 11), "NORTH"), "road south of the dug arm blends the hole face")

-- A filler that still has both arms is left alone
newWorld()
pave(11, 10)
pave(10, 11)
pave(11, 11)
check(Overlays.placeGapFiller(at(10, 10), 1, "gravel"), "pocket filled before an unrelated shovel")
shovel(11, 11)
Overlays.healAfterShovel(at(11, 11))
local keptOverlay = classifySquare(at(10, 10))
equals(keptOverlay and keptOverlay.type, Constants.TILE_TYPES.GAP_FILLER, "filler with both arms keeps its triangle")

-- HAND PLACE: settleAfterPlace blends the new road's open faces
newWorld()
local hand = pave(10, 10)
Overlays.settleAfterPlace(hand)
equalsDirs(hand, { "NORTH", "SOUTH", "EAST", "WEST" }, "hand place alone: all four faces blend")

newWorld()
pave(10, 9)
pave(10, 11)
local mid = pave(10, 10)
Overlays.settleAfterPlace(mid)
equalsDirs(mid, { "EAST", "WEST" }, "hand place between north/south road: only open faces blend")

-- Hand place that opens an L-pocket uses the same fillGaps as the truck; covered by
-- placeGapFiller tests above. settleAfterPlace's job under test is the open-face blends.

if #failures > 0 then
    print("shovel heal: " .. #failures .. " of " .. checks .. " checks FAILED")
    for _, message in ipairs(failures) do
        print("  - " .. message)
    end
    os.exit(1)
end

print("shovel heal: " .. checks .. " checks passed")
