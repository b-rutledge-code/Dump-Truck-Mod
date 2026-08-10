-- Unit tests for DumpTruckOverlays.addEdgeBlends.
-- Plain lua, no game required: `lua tests/edge_blend_test.lua` from anywhere,
-- or scripts/run-overlay-tests.sh.
--
-- The module reaches for game globals and for DumpTruckCore's live-square adapters, so
-- both are stubbed below over a grid of fake squares. The sprite math itself is the real
-- DumpTruckOverlayClassify, so a blend's direction is read back the way the game reads it.

local testDir = ((arg and arg[0]) or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = testDir .. "/../Contents/mods/DumpTruckGravelMod/42.20/media/lua/shared/?.lua;" .. package.path

local Classify = require("DumpTruck/DumpTruckOverlayClassify")
local Constants = require("DumpTruck/DumpTruckConstants")

local GRASS = "blends_natural_01_64"

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

local function makeSquare(x, y, floorSprite)
    local floor = {
        attached = {},
        sprite = getSprite(floorSprite),
        pouredFloor = nil,
        getSprite = function(self) return self.sprite end,
        AttachExistingAnim = function(self, spriteObj)
            table.insert(self.attached, spriteObj:getName())
        end,
        RemoveAttachedAnims = function(self) self.attached = {} end,
        DirtySlice = function() end
    }
    return {
        x = x, y = y, floor = floor,
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function() return 0 end,
        getFloor = function(self) return self.floor end,
        getN = function(self) return world[self.x .. "," .. (self.y - 1)] end,
        getS = function(self) return world[self.x .. "," .. (self.y + 1)] end,
        getE = function(self) return world[(self.x + 1) .. "," .. self.y] end,
        getW = function(self) return world[(self.x - 1) .. "," .. self.y] end,
        RecalcProperties = function() end,
        DirtySlice = function() end
    }
end

-- A 7x7 patch of grass, road painted on afterwards
local function newWorld()
    world = {}
    for x = 7, 13 do
        for y = 7, 13 do
            world[x .. "," .. y] = makeSquare(x, y, GRASS)
        end
    end
    return world
end

local function at(x, y) return world[x .. "," .. y] end

-- Pave with a real material: sprite and stamp both, the way a pour leaves the square,
-- so the module recognizes the road the same way the game does
local function pave(x, y, floorType)
    local pourable = Constants.POURABLE_BY_FLOOR_TYPE[floorType]
    local square = at(x, y)
    square.floor.sprite = getSprite(pourable.sprite)
    square.floor.pouredFloor = pourable.floorType
    return square
end

local function paveGravel(x, y)
    return pave(x, y, "gravel")
end

-- The direction of the blend now attached, or nil when the square carries none
local function blendDirection(square)
    local attached = square:getFloor().attached
    if #attached == 0 then
        return nil
    end
    return Classify.getEdgeBlendDirection(attached[#attached])
end

-- The real classifier over the fake floors, so "is this a road" is decided here the same
-- way it is in game: gravel by its street sprite, sand and dirt by their poured stamp
local function classifySquare(square)
    if not square then return nil end
    local floor = square:getFloor()
    return Classify.classify(floor:getSprite():getName(), floor.attached, floor.pouredFloor)
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
    classifySquare = classifySquare,
    debugPrint = function() end
}

local Overlays = require("DumpTruck/DumpTruckOverlays")

-- CARDINAL COLUMNS: the shape the old heading-free rule already handled

local function cardinalCase(label, tiles, expectedFirst, expectedLast)
    newWorld()
    local squares = {}
    for _, tile in ipairs(tiles) do
        table.insert(squares, paveGravel(tile[1], tile[2]))
    end
    Overlays.addEdgeBlends(squares[1], squares[#squares])
    equals(blendDirection(squares[1]), expectedFirst, label .. ": first square")
    equals(blendDirection(squares[#squares]), expectedLast, label .. ": last square")
end

cardinalCase("column running south", { {10,9}, {10,10}, {10,11} }, "NORTH", "SOUTH")
cardinalCase("column running north", { {10,11}, {10,10}, {10,9} }, "SOUTH", "NORTH")
cardinalCase("column running east", { {9,10}, {10,10}, {11,10} }, "WEST", "EAST")
cardinalCase("column running west", { {11,10}, {10,10}, {9,10} }, "EAST", "WEST")

-- DIAGONAL COLUMNS: two outward faces per end, dominant axis first

newWorld()
local diagonalFirst = paveGravel(10, 11)
paveGravel(11, 11)
local diagonalLast = paveGravel(11, 10)
Overlays.addEdgeBlends(diagonalFirst, diagonalLast)
equals(blendDirection(diagonalFirst), "WEST", "diagonal column: first square takes its outward face")
equals(blendDirection(diagonalLast), "EAST", "diagonal column: last square takes its outward face")

-- The reported bug: the dominant face abuts gravel a gap filler left behind, so the blend
-- has to fall through to the square's other exposed face rather than be dropped
newWorld()
local blockedFirst = paveGravel(10, 11)
paveGravel(11, 11)
local blockedLast = paveGravel(11, 10)
paveGravel(9, 11)  -- gap filler west of the first square
paveGravel(12, 10) -- gap filler east of the last square
Overlays.addEdgeBlends(blockedFirst, blockedLast)
equals(blendDirection(blockedFirst), "SOUTH", "blocked diagonal: first square falls through to its open face")
equals(blendDirection(blockedLast), "NORTH", "blocked diagonal: last square falls through to its open face")

-- A column that only wobbles off the axis still blends along the road's dominant side
newWorld()
local wobbleFirst = paveGravel(9, 10)
paveGravel(10, 10)
paveGravel(11, 10)
local wobbleLast = paveGravel(12, 11)
Overlays.addEdgeBlends(wobbleFirst, wobbleLast)
equals(blendDirection(wobbleFirst), "WEST", "wobbling column: first square uses the dominant axis")
equals(blendDirection(wobbleLast), "EAST", "wobbling column: last square uses the dominant axis")

-- NOTHING TO BLEND AGAINST

newWorld()
local walledFirst = paveGravel(10, 9)
paveGravel(10, 10)
local walledLast = paveGravel(10, 11)
paveGravel(10, 8)
paveGravel(10, 12)
Overlays.addEdgeBlends(walledFirst, walledLast)
equals(blendDirection(walledFirst), nil, "gravel on both sides: first square stays bare")
equals(blendDirection(walledLast), nil, "gravel on both sides: last square stays bare")

newWorld()
local pavedNeighbour = paveGravel(10, 9)
paveGravel(10, 10)
local pavedLast = paveGravel(10, 11)
at(10, 8).floor.sprite = getSprite("floors_interior_carpet_01_0") -- not terrain we can blend against
Overlays.addEdgeBlends(pavedNeighbour, pavedLast)
equals(blendDirection(pavedNeighbour), nil, "non-terrain neighbour: no blend")

-- MATERIALS: a road is known by its stamp, not by looking like one

-- Sand and dirt roads wear the same sprites as beaches and dirt fields, so the stamp is the
-- only thing separating a road we laid from ground that was always there.
newWorld()
local sandFirst = pave(10, 9, "sand")
pave(10, 10, "sand")
local sandLast = pave(10, 11, "sand")
Overlays.addEdgeBlends(sandFirst, sandLast)
equals(blendDirection(sandFirst), "NORTH", "sand road: first square blends against terrain")
equals(blendDirection(sandLast), "SOUTH", "sand road: last square blends against terrain")

-- The same sprite without a stamp is ordinary ground, and a road blends against it
newWorld()
local besideBeach = paveGravel(10, 10)
paveGravel(10, 11)
at(10, 9).floor.sprite = getSprite(Constants.POURABLE_BY_FLOOR_TYPE.sand.sprite)
Overlays.addEdgeBlends(besideBeach, at(10, 11))
equals(blendDirection(besideBeach), "NORTH", "unstamped sand is terrain, so the road blends against it")

-- Stamp that same neighbour and it becomes road: nothing to blend against any more
newWorld()
local besideSandRoad = paveGravel(10, 10)
paveGravel(10, 11)
pave(10, 9, "sand")
Overlays.addEdgeBlends(besideSandRoad, at(10, 11))
equals(blendDirection(besideSandRoad), nil, "a stamped sand road is not terrain to blend against")

-- A dirt road wears the very sprite this world uses for grass
newWorld()
local dirtFirst = pave(9, 10, "dirt")
pave(10, 10, "dirt")
local dirtLast = pave(11, 10, "dirt")
equals(at(9, 10).floor.sprite:getName(), GRASS, "dirt pours onto the same tile as the surrounding ground")
Overlays.addEdgeBlends(dirtFirst, dirtLast)
equals(blendDirection(dirtFirst), "WEST", "dirt road: first square still blends against the grass beside it")
equals(blendDirection(dirtLast), "EAST", "dirt road: last square still blends against the grass beside it")

-- A square already wearing the right blend keeps it instead of hunting for another face
newWorld()
local settledFirst = paveGravel(10, 11)
paveGravel(11, 11)
local settledLast = paveGravel(11, 10)
Overlays.addEdgeBlends(settledFirst, settledLast)
Overlays.addEdgeBlends(settledFirst, settledLast)
equals(blendDirection(settledFirst), "WEST", "repeat pour: first square keeps its face")
equals(#settledFirst:getFloor().attached, 1, "repeat pour: no second sprite stacked on")

if #failures > 0 then
    print("edge blends: " .. #failures .. " of " .. checks .. " checks FAILED")
    for _, message in ipairs(failures) do
        print("  - " .. message)
    end
    os.exit(1)
end

print("edge blends: " .. checks .. " checks passed")
