-- DumpTruckBandRaster.lua
-- Which tiles a road of a given width covers as the truck sweeps from one pour point to
-- the next. Pure math on tile coordinates: no game objects, so tests/band_raster_test.lua
-- runs it outside the game.

local DumpTruckBandRaster = {}

-- Under this the truck barely moved, so its heading describes the road better than the
-- direction between two nearly identical points
local MIN_SEGMENT = 0.25

local function normalize(x, y)
    local length = math.sqrt(x * x + y * y)
    if length < 1e-6 then
        return nil, nil
    end
    return x / length, y / length
end

--[[
    offsetBehind: the point `distance` behind a position, along the given heading.

    The bed empties off the back of the truck, so gravel lands here rather than under
    the cab.
]]
function DumpTruckBandRaster.offsetBehind(cx, cy, fx, fy, distance)
    local headingX, headingY = normalize(fx, fy)
    if not headingX then
        return cx, cy
    end
    return cx - headingX * distance, cy - headingY * distance
end

--[[
    getColumns: the tiles a road of `width` covers sweeping from (ax,ay) to (bx,by).

    A tile joins the road when its centre lies inside the swept rectangle. Reading
    coverage off the area, rather than sampling points along the road's perpendicular,
    is what makes a diagonal solid: on a 45 degree heading that perpendicular runs
    through tile corners, and the tiles its samples land on touch only at their corners,
    leaving holes between them.

    Across the road the test is half open, so a cardinal row is exactly `width` tiles
    wherever the truck happens to sit inside its own tile. Along the road it reaches
    half a tile past each end, so a crawling truck still lays a row when one tick's
    pour point falls in the same tile as the last.

    Returns columns ordered along the road, each column ordered across it, so a column's
    first and last tiles are the road's two edges.
]]
function DumpTruckBandRaster.getColumns(ax, ay, bx, by, fx, fy, width)
    if not width or width < 1 then
        return {}
    end

    local headingX, headingY = normalize(fx, fy)
    if not headingX then
        return {}
    end

    local travelX, travelY = bx - ax, by - ay
    local alongX, alongY = normalize(travelX, travelY)
    if not alongX or (travelX * travelX + travelY * travelY) < MIN_SEGMENT * MIN_SEGMENT then
        alongX, alongY = headingX, headingY
    end

    local acrossX, acrossY = -alongY, alongX
    -- Reversing points the sweep against the heading. Holding the across vector on the
    -- heading's side keeps an even-width road on the same side of the truck either way.
    if acrossX * -headingY + acrossY * headingX < 0 then
        acrossX, acrossY = -acrossX, -acrossY
    end

    -- An even width has no middle tile, so the road rides half a tile across instead of
    -- straddling the truck
    if width % 2 == 0 then
        ax, ay = ax + acrossX * 0.5, ay + acrossY * 0.5
        bx, by = bx + acrossX * 0.5, by + acrossY * 0.5
    end

    local segmentEnd = (bx - ax) * alongX + (by - ay) * alongY
    local halfWidth = width / 2

    local pad = halfWidth + 1
    local minTileX = math.floor(math.min(ax, bx) - pad)
    local maxTileX = math.floor(math.max(ax, bx) + pad)
    local minTileY = math.floor(math.min(ay, by) - pad)
    local maxTileY = math.floor(math.max(ay, by) + pad)

    local columnsByKey = {}
    local keys = {}

    for tileX = minTileX, maxTileX do
        for tileY = minTileY, maxTileY do
            local dx = tileX + 0.5 - ax
            local dy = tileY + 0.5 - ay
            local across = dx * acrossX + dy * acrossY
            if across >= -halfWidth and across < halfWidth then
                local along = dx * alongX + dy * alongY
                if along >= -0.5 and along < segmentEnd + 0.5 then
                    local key = math.floor(along + 0.5)
                    local column = columnsByKey[key]
                    if not column then
                        column = {}
                        columnsByKey[key] = column
                        table.insert(keys, key)
                    end
                    table.insert(column, { x = tileX, y = tileY, across = across })
                end
            end
        end
    end

    table.sort(keys)

    local columns = {}
    for _, key in ipairs(keys) do
        local column = columnsByKey[key]
        table.sort(column, function(left, right) return left.across < right.across end)

        local ordered = {}
        for _, tile in ipairs(column) do
            table.insert(ordered, { x = tile.x, y = tile.y })
        end
        table.insert(columns, ordered)
    end

    return columns
end

return DumpTruckBandRaster
