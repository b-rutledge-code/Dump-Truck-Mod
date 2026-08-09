-- Unit tests for DumpTruck/DumpTruckBandRaster.
-- Plain lua, no game required: `lua tests/band_raster_test.lua` from anywhere,
-- or scripts/run-overlay-tests.sh.

local testDir = ((arg and arg[0]) or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = testDir .. "/../Contents/mods/DumpTruckGravelMod/42.20/media/lua/shared/?.lua;" .. package.path

local Raster = require("DumpTruck/DumpTruckBandRaster")

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

local function tileList(column)
    local parts = {}
    for _, tile in ipairs(column) do
        table.insert(parts, "(" .. tile.x .. "," .. tile.y .. ")")
    end
    return table.concat(parts, " ")
end

local function sharesAxis(column)
    local firstX, firstY = column[1].x, column[1].y
    local sameX, sameY = true, true
    for i = 2, #column do
        if column[i].x ~= firstX then sameX = false end
        if column[i].y ~= firstY then sameY = false end
    end
    return sameX or sameY
end

local function flatten(columns)
    local tiles, count = {}, 0
    for _, column in ipairs(columns) do
        for _, tile in ipairs(column) do
            local key = tile.x .. ":" .. tile.y
            if not tiles[key] then
                tiles[key] = tile
                count = count + 1
            end
        end
    end
    return tiles, count
end

-- A road you can drive on is one connected surface. Tiles meeting only at a corner are
-- the checkerboard a perpendicular line sampler produces on a diagonal, so reachability
-- counts north/south/east/west steps only.
local function connectedCount(tiles)
    local start
    for _, tile in pairs(tiles) do
        start = tile
        break
    end
    if not start then return 0 end

    local seen = { [start.x .. ":" .. start.y] = true }
    local queue = { start }
    local reached = 1
    while #queue > 0 do
        local tile = table.remove(queue)
        local neighbours = {
            { x = tile.x + 1, y = tile.y },
            { x = tile.x - 1, y = tile.y },
            { x = tile.x, y = tile.y + 1 },
            { x = tile.x, y = tile.y - 1 },
        }
        for _, neighbour in ipairs(neighbours) do
            local key = neighbour.x .. ":" .. neighbour.y
            if tiles[key] and not seen[key] then
                seen[key] = true
                reached = reached + 1
                table.insert(queue, tiles[key])
            end
        end
    end
    return reached
end

-- OFFSET BEHIND

do
    local x, y = Raster.offsetBehind(10.5, 10.5, 1, 0, 3)
    equals(x, 7.5, "pour point sits behind an east heading")
    equals(y, 10.5, "east heading does not move the pour point sideways")

    -- The heading arrives unnormalized from the driver, so the offset normalizes it
    local dx, dy = Raster.offsetBehind(10.5, 10.5, 3, 4, 5)
    equals(dx, 10.5 - 3, "unnormalized heading still offsets by the asked distance in x")
    equals(dy, 10.5 - 4, "unnormalized heading still offsets by the asked distance in y")
end

-- CARDINAL ROWS

do
    -- Standing still on a tile centre, east: one row of three centred on the truck
    local columns = Raster.getColumns(10.5, 10.5, 10.5, 10.5, 1, 0, 3)
    equals(#columns, 1, "a still truck lays one column")
    equals(#columns[1], 3, "width 3 lays three tiles")
    equals(tileList(columns[1]), "(10,9) (10,10) (10,11)", "width 3 row is centred on the truck")
    check(sharesAxis(columns[1]), "cardinal column shares an axis")
end

do
    -- Width 2 has no middle tile, so it rides one side: the truck's tile plus the next
    local columns = Raster.getColumns(10.5, 10.5, 10.5, 10.5, 1, 0, 2)
    equals(#columns, 1, "width 2 still lays one column")
    equals(tileList(columns[1]), "(10,10) (10,11)", "width 2 rides the truck's right")
end

do
    -- Driving east three tiles: a column per tile of travel, plus the starting tile
    local columns = Raster.getColumns(10.5, 10.5, 13.5, 10.5, 1, 0, 3)
    equals(#columns, 4, "three tiles of travel lay four columns")
    for index, column in ipairs(columns) do
        equals(#column, 3, "column " .. index .. " is three tiles wide")
        check(sharesAxis(column), "column " .. index .. " of an east road shares an axis")
    end
    equals(tileList(columns[1]), "(10,9) (10,10) (10,11)", "first column of an east road")
    equals(tileList(columns[4]), "(13,9) (13,10) (13,11)", "last column of an east road")
end

do
    -- North and west confirm the row does not depend on which way the heading points
    local north = Raster.getColumns(10.5, 10.5, 10.5, 10.5, 0, -1, 3)
    equals(tileList(north[1]), "(9,10) (10,10) (11,10)", "width 3 row heading north")

    -- Same three tiles as heading east, ordered the other way: a column runs across the
    -- road from the driver's left to right, which turns around with the truck
    local west = Raster.getColumns(10.5, 10.5, 10.5, 10.5, -1, 0, 3)
    equals(tileList(west[1]), "(10,11) (10,10) (10,9)", "width 3 row heading west")
end

do
    -- Wherever the truck sits inside its tile, a cardinal row is exactly `width` tiles
    for step = 0, 9 do
        local offset = step / 10
        for _, width in ipairs({ 2, 3 }) do
            local columns = Raster.getColumns(10 + offset, 10 + offset, 10 + offset, 10 + offset, 1, 0, width)
            local total = 0
            for _, column in ipairs(columns) do
                total = total + #column
            end
            equals(total, width, "width " .. width .. " row at offset " .. offset .. " is exactly " .. width .. " tiles")
        end
    end
end

-- DIAGONAL SWEEP

do
    local columns = Raster.getColumns(10.5, 10.5, 20.5, 20.5, 1, 1, 3)
    local tiles, count = flatten(columns)

    check(count > 0, "a 45 degree sweep covers tiles")
    equals(connectedCount(tiles), count, "a 45 degree road is one connected surface, not a corner-touching checkerboard")

    -- Area of the swept band: width by the travelled length plus the half tile it
    -- reaches past each end
    local travelled = math.sqrt(10 * 10 + 10 * 10)
    local expected = 3 * (travelled + 1)
    check(count >= expected * 0.75 and count <= expected * 1.3,
        "45 degree coverage stays near the band's area (expected about " .. math.floor(expected) .. ", got " .. count .. ")")

    -- No column stretches wider than the road
    for index, column in ipairs(columns) do
        local minX, maxX, minY, maxY = column[1].x, column[1].x, column[1].y, column[1].y
        for _, tile in ipairs(column) do
            minX = math.min(minX, tile.x)
            maxX = math.max(maxX, tile.x)
            minY = math.min(minY, tile.y)
            maxY = math.max(maxY, tile.y)
        end
        local span = math.sqrt((maxX - minX) ^ 2 + (maxY - minY) ^ 2)
        check(span <= 3 + 1, "45 degree column " .. index .. " spans no more than the road width")
    end
end

do
    -- The edge blend gate reads the tiles alone, so a diagonal has to look different
    -- from a straightaway in the square list itself
    local columns = Raster.getColumns(10.5, 10.5, 20.5, 20.5, 1, 1, 3)
    local diagonalColumns = 0
    for _, column in ipairs(columns) do
        if #column >= 2 and not sharesAxis(column) then
            diagonalColumns = diagonalColumns + 1
        end
    end
    check(diagonalColumns > 0, "a 45 degree sweep produces columns that share no axis")
end

do
    -- A tick short enough to stay inside one tile still lays road
    local columns = Raster.getColumns(10.5, 10.5, 10.7, 10.7, 1, 1, 3)
    local _, count = flatten(columns)
    check(count >= 3, "a crawling tick still lays a row (got " .. count .. ")")
end

do
    -- Reversing keeps an even road on the same side of the truck as driving forward
    local forward = Raster.getColumns(10.5, 10.5, 13.5, 10.5, 1, 0, 2)
    local reversing = Raster.getColumns(13.5, 10.5, 10.5, 10.5, 1, 0, 2)
    local _, forwardCount = flatten(forward)
    local _, reverseCount = flatten(reversing)
    equals(reverseCount, forwardCount, "reversing covers as many tiles as driving forward")

    local forwardTiles = flatten(forward)
    local reverseTiles = flatten(reversing)
    local sameSide = true
    for key in pairs(reverseTiles) do
        if not forwardTiles[key] then sameSide = false end
    end
    check(sameSide, "reversing lays the even-width road on the same side as driving forward")
end

-- GUARDS

do
    equals(#Raster.getColumns(10.5, 10.5, 10.5, 10.5, 0, 0, 3), 0, "a heading of zero lays nothing")
    equals(#Raster.getColumns(10.5, 10.5, 10.5, 10.5, 1, 0, 0), 0, "a width of zero lays nothing")
end

if #failures > 0 then
    print("band raster: " .. #failures .. " of " .. checks .. " checks FAILED")
    for _, message in ipairs(failures) do
        print("  - " .. message)
    end
    os.exit(1)
end

print("band raster: " .. checks .. " checks passed")
