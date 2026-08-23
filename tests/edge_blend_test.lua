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

-- Every blend direction currently attached, in attach order
local function blendDirections(square)
    local dirs = {}
    for _, name in ipairs(square:getFloor().attached) do
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

-- DIAGONAL COLUMNS: two outward faces per end, each open face gets its own blend

newWorld()
local diagonalFirst = paveGravel(10, 11)
paveGravel(11, 11)
local diagonalLast = paveGravel(11, 10)
Overlays.addEdgeBlends(diagonalFirst, diagonalLast)
equalsDirs(diagonalFirst, { "WEST", "SOUTH" }, "diagonal column: first square blends both outward faces")
equalsDirs(diagonalLast, { "EAST", "NORTH" }, "diagonal column: last square blends both outward faces")

-- The reported bug: the dominant face abuts gravel a gap filler left behind, so that face
-- is skipped and the square's other exposed face still receives its blend
newWorld()
local blockedFirst = paveGravel(10, 11)
paveGravel(11, 11)
local blockedLast = paveGravel(11, 10)
paveGravel(9, 11)  -- gap filler west of the first square
paveGravel(12, 10) -- gap filler east of the last square
Overlays.addEdgeBlends(blockedFirst, blockedLast)
equalsDirs(blockedFirst, { "SOUTH" }, "blocked diagonal: first square blends its open face")
equalsDirs(blockedLast, { "NORTH" }, "blocked diagonal: last square blends its open face")

-- A column that only wobbles off the axis still blends along the road's dominant side
newWorld()
local wobbleFirst = paveGravel(9, 10)
paveGravel(10, 10)
paveGravel(11, 10)
local wobbleLast = paveGravel(12, 11)
Overlays.addEdgeBlends(wobbleFirst, wobbleLast)
check(hasBlendDirection(wobbleFirst, "WEST"), "wobbling column: first square uses the dominant axis")
check(hasBlendDirection(wobbleLast, "EAST"), "wobbling column: last square uses the dominant axis")

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
local settledCount = #settledFirst:getFloor().attached
Overlays.addEdgeBlends(settledFirst, settledLast)
equals(#settledFirst:getFloor().attached, settledCount, "repeat pour: no duplicate sprites stacked on")
equalsDirs(settledFirst, { "WEST", "SOUTH" }, "repeat pour: first square keeps both faces")

-- Placing a second-face blend keeps the first face
newWorld()
local corner = paveGravel(10, 10)
local northBlend = Overlays.getEdgeBlendSprite("NORTH", GRASS)
local eastBlend = Overlays.getEdgeBlendSprite("EAST", GRASS)
check(Overlays.placeEdgeBlend(corner, northBlend), "place north blend")
check(Overlays.placeEdgeBlend(corner, eastBlend), "place east blend keeps north")
equalsDirs(corner, { "NORTH", "EAST" }, "corner carries both north and east blends")
equals(#corner:getFloor().attached, 2, "corner has exactly two attached blends")

-- Same-direction different material replaces only that face
local sandTerrain = Constants.POURABLE_BY_FLOOR_TYPE.sand.sprite
local northSand = Overlays.getEdgeBlendSprite("NORTH", sandTerrain)
check(Overlays.placeEdgeBlend(corner, northSand), "same-direction material replace")
equalsDirs(corner, { "EAST", "NORTH" }, "material replace keeps the other face")
check(hasBlendDirection(corner, "NORTH"), "replaced face is still north")
check(not hasBlendDirection(corner, "SOUTH"), "no accidental south blend")
local northSpriteAfter = nil
for _, name in ipairs(corner:getFloor().attached) do
    if Classify.getEdgeBlendDirection(name) == "NORTH" then
        northSpriteAfter = name
    end
end
equals(northSpriteAfter, northSand, "north face now uses the sand-row blend")

-- removeAttachedSprite drops one face and keeps the other
check(Overlays.removeAttachedSprite(corner, eastBlend), "remove east face")
equalsDirs(corner, { "NORTH" }, "remove one face leaves the other")
check(not Overlays.removeAttachedSprite(corner, eastBlend), "removing a missing sprite is a no-op")

-- Stale-blend cleanup removes only the stale direction
newWorld()
local seam = paveGravel(10, 10)
paveGravel(11, 10)
local westBlend = Overlays.getEdgeBlendSprite("WEST", GRASS)
local eastStale = Overlays.getEdgeBlendSprite("EAST", GRASS)
Overlays.placeEdgeBlend(seam, westBlend)
Overlays.placeEdgeBlend(seam, eastStale)
equalsDirs(seam, { "WEST", "EAST" }, "seam starts with outward and inward blends")
Overlays.removeEdgeBlendsBetweenPourableSquares(seam)
equalsDirs(seam, { "WEST" }, "stale east blend cleaned; west outward blend kept")

-- Full clear still empties every attached sprite
newWorld()
local wipe = paveGravel(10, 10)
Overlays.placeEdgeBlend(wipe, Overlays.getEdgeBlendSprite("NORTH", GRASS))
Overlays.placeEdgeBlend(wipe, Overlays.getEdgeBlendSprite("WEST", GRASS))
check(#wipe:getFloor().attached == 2, "wipe candidate has two blends")
Overlays.removeOverlay(wipe)
equals(#wipe:getFloor().attached, 0, "full clear empties the attached list")

if #failures > 0 then
    print("edge blends: " .. #failures .. " of " .. checks .. " checks FAILED")
    for _, message in ipairs(failures) do
        print("  - " .. message)
    end
    os.exit(1)
end

print("edge blends: " .. checks .. " checks passed")
