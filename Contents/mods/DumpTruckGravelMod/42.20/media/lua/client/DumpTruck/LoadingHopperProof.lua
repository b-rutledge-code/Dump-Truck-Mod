-- Early 2D-building proofs. Re-registers DumpTruck.placeHopper with payload.mode.
-- mode nil/"g3" = existing 3D G3 stamp (LoadingHopperBind).
-- mode "proof1" | "proof2" | "proof3" = kill-criteria stamps.

DumpTruck = DumpTruck or {}

local PROOF_FLOOR = "floors_exterior_tilesandstone_01_4"
local PROOF_POST = "construction_01_48"
local PROOF_RAIL = "fixtures_railings_01_27"

local function squareAt(x, y, z)
    local cell = getCell()
    if cell.getOrCreateGridSquare ~= nil then
        return cell:getOrCreateGridSquare(x, y, z)
    end
    return cell:getGridSquare(x, y, z)
end

local function spriteName(obj)
    if obj == nil then
        return nil
    end
    local spr = obj:getSprite()
    if spr == nil then
        return nil
    end
    return spr:getName()
end

local function isProofSprite(name)
    return name == PROOF_FLOOR or name == PROOF_POST or name == PROOF_RAIL
        or (name ~= nil and string.sub(name, 1, 10) == "hopper_2d_")
end

local function isHopperSprite(name)
    return name ~= nil and string.sub(name, 1, 15) == "loading_hopper_"
end

local function clearArea(ax, ay, az, radius)
    local cell = getCell()
    for dx = -radius, radius do
        for dy = -radius, radius do
            for dz = 0, 3 do
                local sq = cell:getGridSquare(ax + dx, ay + dy, az + dz)
                if sq ~= nil then
                    local objs = sq:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local obj = objs:get(i)
                        local name = spriteName(obj)
                        if isProofSprite(name) or isHopperSprite(name) then
                            sq:RemoveTileObject(obj)
                        end
                    end
                end
            end
        end
    end
end

local function placeSprite(ax, ay, az, dx, dy, dz, name)
    local dest = squareAt(ax + dx, ay + dy, az + dz)
    if dest == nil then
        return false
    end
    local obj = IsoObject.new(getCell(), dest, name)
    dest:AddTileObject(obj)
    if dest.RecalcProperties ~= nil then
        dest:RecalcProperties()
    end
    if dest.RecalcAllWithNeighbours ~= nil then
        dest:RecalcAllWithNeighbours(true)
    end
    return true
end

local function placeFloor(ax, ay, az, dx, dy, dz, name)
    local dest = squareAt(ax + dx, ay + dy, az + dz)
    if dest == nil then
        return false
    end
    if dest.addFloor ~= nil then
        dest:addFloor(name)
    else
        placeSprite(ax, ay, az, dx, dy, dz, name)
    end
    if dest.RecalcProperties ~= nil then
        dest:RecalcProperties()
    end
    if dest.RecalcAllWithNeighbours ~= nil then
        dest:RecalcAllWithNeighbours(true)
    end
    return true
end

-- Proof 1: opaque vanilla floor @ z=3 + post @ z=0 (lighting kill criterion).
local function stampProof1(ax, ay, az)
    local postOk = placeSprite(ax, ay, az, 0, 0, 0, PROOF_POST)
    local floorOk = placeFloor(ax, ay, az, 0, 0, 3, PROOF_FLOOR)
    return {
        ok = postOk and floorOk,
        mode = "proof1",
        floor = PROOF_FLOOR,
        post = PROOF_POST,
        postOk = postOk,
        floorOk = floorOk,
        x = ax,
        y = ay,
        z = az,
    }
end

-- Proof 2: 3x3 deck ring of floor tiles @ z=3 (iso crop stand-in until FBX bake).
local function stampProof2(ax, ay, az)
    placeSprite(ax, ay, az, 0, 0, 0, PROOF_POST)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not (dx == 0 and dy == 0) then
                placeFloor(ax, ay, az, dx, dy, 3, PROOF_FLOOR)
                placeSprite(ax, ay, az, dx, dy, 3, PROOF_RAIL)
            end
        end
    end
    -- opening center: no floor
    return { ok = true, mode = "proof2", cells = 8, x = ax, y = ay, z = az }
end

-- Proof 3: open bay posts + mid + deck (cutaway check).
local function stampProof3(ax, ay, az)
    local posts = {
        { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 },
    }
    for i = 1, #posts do
        local p = posts[i]
        placeSprite(ax, ay, az, p[1], p[2], 0, PROOF_POST)
        placeSprite(ax, ay, az, p[1], p[2], 1, PROOF_POST)
        placeSprite(ax, ay, az, p[1], p[2], 2, PROOF_POST)
    end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local edge = (math.abs(dx) == 2 or math.abs(dy) == 2)
            local corner = (math.abs(dx) == 2 and math.abs(dy) == 2)
            if edge and not corner then
                placeFloor(ax, ay, az, dx, dy, 3, PROOF_FLOOR)
            end
            if corner then
                placeFloor(ax, ay, az, dx, dy, 3, PROOF_FLOOR)
                placeSprite(ax, ay, az, dx, dy, 3, PROOF_RAIL)
            end
        end
    end
    return { ok = true, mode = "proof3", x = ax, y = ay, z = az }
end

local function deckAsFloor()
    return DumpTruck.Hopper2dDeckAsFloor == true
end

local function placeByKind(ax, ay, az, dx, dy, dz, name, kind)
    if kind == "floor" and deckAsFloor() then
        return placeFloor(ax, ay, az, dx, dy, dz, name)
    end
    return placeSprite(ax, ay, az, dx, dy, dz, name)
end

local function placeDeckCell(ax, ay, az, dx, dy, dz, name)
    return placeByKind(ax, ay, az, dx, dy, dz, name, "floor")
end

local function placeCell(ax, ay, az, c)
    if c.edge then
        -- transparentFloor needs a square below it, or the engine culls the square as covering.
        squareAt(ax + c.gx, ay + c.gy, az + c.fz - 1)
    end
    return placeByKind(ax, ay, az, c.gx, c.gy, c.fz, c.sprite, c.kind or "object")
end

local function findCell(gx, gy, fz, kind)
    local cells = DumpTruck.Hopper2dCells
    if cells == nil then
        return nil
    end
    for i = 1, #cells do
        local c = cells[i]
        if c.gx == gx and c.gy == gy and c.fz == fz then
            if kind == nil or c.kind == kind or (kind == "floor" and c.kind == nil) then
                return c
            end
        end
    end
    return nil
end

local function findFloorCellsAt(gx, gy, fz)
    local out = {}
    local cells = DumpTruck.Hopper2dCells
    if cells == nil then
        return out
    end
    for i = 1, #cells do
        local c = cells[i]
        if c.gx == gx and c.gy == gy and c.fz == fz and (c.kind == "floor" or c.kind == nil) then
            table.insert(out, c)
        end
    end
    return out
end

-- Dig #2: two adjacent fully-decked floor cells @ z=3.
local function stampDig2(ax, ay, az)
    local a = findCell(0, 2, 3, "floor")
    local b = findCell(1, 2, 3, "floor")
    if a == nil or b == nil then
        local decks = {}
        if DumpTruck.Hopper2dCells ~= nil then
            for i = 1, #DumpTruck.Hopper2dCells do
                local c = DumpTruck.Hopper2dCells[i]
                if c.fz == 3 and (c.kind == "floor" or c.kind == nil) then
                    table.insert(decks, c)
                end
            end
        end
        for i = 1, #decks do
            for j = i + 1, #decks do
                local d1 = decks[i]
                local d2 = decks[j]
                if math.abs(d1.gx - d2.gx) + math.abs(d1.gy - d2.gy) == 1 then
                    a = d1
                    b = d2
                    break
                end
            end
            if a ~= nil and b ~= nil then
                break
            end
        end
    end
    if a == nil or b == nil then
        return { ok = false, error = "no adjacent deck pair for dig2" }
    end
    local okA = placeFloor(ax, ay, az, 0, 0, 3, a.sprite)
    local okB = placeFloor(ax, ay, az, 1, 0, 3, b.sprite)
    -- Place matching upper sprites at the same world offsets when present.
    local ua = findCell(a.gx, a.gy, 3, "object")
    local ub = findCell(b.gx, b.gy, 3, "object")
    if ua ~= nil then
        placeSprite(ax, ay, az, 0, 0, 3, ua.sprite)
    end
    if ub ~= nil then
        placeSprite(ax, ay, az, 1, 0, 3, ub.sprite)
    end
    return {
        ok = okA and okB,
        mode = "dig2",
        a = a.sprite,
        b = b.sprite,
        aGx = a.gx,
        aGy = a.gy,
        bGx = b.gx,
        bGy = b.gy,
        okA = okA,
        okB = okB,
        asFloor = true,
        x = ax,
        y = ay,
        z = az,
    }
end

-- Dig #3: one column stack (fz 0..2) + deck floor + rail-edge neighbour.
local function stampDig3(ax, ay, az)
    local wanted = {
        { 2, -4, 0 },
        { 2, -4, 1 },
        { 2, -4, 2 },
        { 2, -4, 3 },
        { 3, -4, 3 },
    }
    local placed = 0
    local failed = 0
    local sprites = {}
    if DumpTruck.Hopper2dCells == nil then
        return { ok = false, error = "no Hopper2dCells" }
    end
    for w = 1, #wanted do
        local gx, gy, fz = wanted[w][1], wanted[w][2], wanted[w][3]
        local any = false
        for i = 1, #DumpTruck.Hopper2dCells do
            local c = DumpTruck.Hopper2dCells[i]
            if c.gx == gx and c.gy == gy and c.fz == fz then
                any = true
                -- Stamp relative to first wanted cell as origin offset.
                local dx = gx - 2
                local dy = gy - (-4)
                if placeCell(ax, ay, az, {
                    gx = dx,
                    gy = dy,
                    fz = fz,
                    sprite = c.sprite,
                    kind = c.kind or "object",
                }) then
                    placed = placed + 1
                    table.insert(sprites, c.sprite)
                else
                    failed = failed + 1
                end
            end
        end
        if not any then
            failed = failed + 1
        end
    end
    return {
        ok = failed == 0 and placed > 0,
        mode = "dig3",
        placed = placed,
        failed = failed,
        sprites = sprites,
        x = ax,
        y = ay,
        z = az,
    }
end

-- Dig #1: vanilla sandstone floor @ (0,0,0) beside one custom foot object @ (1,0,0).
local function stampDig1(ax, ay, az)
    local foot = findCell(-3, -4, 0)
    if foot == nil and DumpTruck.Hopper2dCells ~= nil then
        for i = 1, #DumpTruck.Hopper2dCells do
            local c = DumpTruck.Hopper2dCells[i]
            if c.fz == 0 then
                foot = c
                break
            end
        end
    end
    if foot == nil then
        return { ok = false, error = "no foot cell for dig1" }
    end
    local sandOk = placeFloor(ax, ay, az, 0, 0, 0, PROOF_FLOOR)
    local footOk = placeSprite(ax, ay, az, 1, 0, 0, foot.sprite)
    return {
        ok = sandOk and footOk,
        mode = "dig1",
        sandstone = PROOF_FLOOR,
        foot = foot.sprite,
        footGx = foot.gx,
        footGy = foot.gy,
        sandOk = sandOk,
        footOk = footOk,
        x = ax,
        y = ay,
        z = az,
    }
end

-- Calibration: vanilla sandstone @ (0,0,3) beside custom deck floor @ (1,0,3).
local function stampCalib(ax, ay, az)
    local custom = findCell(0, 2, 3, "floor")
    if custom == nil then
        custom = findCell(1, 2, 3, "floor")
    end
    if custom == nil and DumpTruck.Hopper2dCells ~= nil and #DumpTruck.Hopper2dCells > 0 then
        for i = 1, #DumpTruck.Hopper2dCells do
            local c = DumpTruck.Hopper2dCells[i]
            if c.fz == 3 and (c.kind == "floor" or c.kind == nil) then
                custom = c
                break
            end
        end
    end
    if custom == nil then
        return { ok = false, error = "no deck cell for calib" }
    end
    local sandOk = placeFloor(ax, ay, az, 0, 0, 3, PROOF_FLOOR)
    local customOk = placeDeckCell(ax, ay, az, 1, 0, 3, custom.sprite)
    return {
        ok = sandOk and customOk,
        mode = "calib",
        sandstone = PROOF_FLOOR,
        custom = custom.sprite,
        customGx = custom.gx,
        customGy = custom.gy,
        deckAsFloor = deckAsFloor(),
        sandOk = sandOk,
        customOk = customOk,
        x = ax,
        y = ay,
        z = az,
    }
end

-- Floor-path proof: same deck sprite as addFloor @ (0,0,3) and IsoObject @ (2,0,3).
local function stampFloorPath(ax, ay, az)
    local custom = findCell(-2, -1, 3)
    if custom == nil and DumpTruck.Hopper2dCells ~= nil then
        for i = 1, #DumpTruck.Hopper2dCells do
            if DumpTruck.Hopper2dCells[i].fz == 3 then
                custom = DumpTruck.Hopper2dCells[i]
                break
            end
        end
    end
    if custom == nil then
        return { ok = false, error = "no deck cell for floorpath" }
    end
    local asFloor = placeFloor(ax, ay, az, 0, 0, 3, custom.sprite)
    local asObj = placeSprite(ax, ay, az, 2, 0, 3, custom.sprite)
    placeFloor(ax, ay, az, 1, 0, 3, PROOF_FLOOR) -- spacer reference
    return {
        ok = asFloor and asObj,
        mode = "floorpath",
        sprite = custom.sprite,
        asFloor = asFloor,
        asObj = asObj,
        x = ax,
        y = ay,
        z = az,
    }
end

-- Fixture / ring: stamp all loaded Hopper2dCells (fixture bake is a small set).
local function stampFixture(ax, ay, az)
    local cells = DumpTruck.Hopper2dCells
    if cells == nil or #cells == 0 then
        return { ok = false, error = "no Hopper2dCells" }
    end
    local placed = 0
    local failed = 0
    for i = 1, #cells do
        if placeCell(ax, ay, az, cells[i]) then
            placed = placed + 1
        else
            failed = failed + 1
        end
    end
    return {
        ok = failed == 0,
        mode = "fixture",
        placed = placed,
        failed = failed,
        cells = #cells,
        deckAsFloor = deckAsFloor(),
        x = ax,
        y = ay,
        z = az,
    }
end

-- Full custom 2D flood from bake (DumpTruck.Hopper2dCells).
local function stampFlood(ax, ay, az)
    local cells = DumpTruck.Hopper2dCells
    if cells == nil or #cells == 0 then
        return { ok = false, error = "no Hopper2dCells (LoadingHopper2dCells.lua)" }
    end
    local placed = 0
    local failed = 0
    for i = 1, #cells do
        if placeCell(ax, ay, az, cells[i]) then
            placed = placed + 1
        else
            failed = failed + 1
        end
    end
    -- Hopper controls find the stock on this invisible object at the bay centre.
    local anchorOk = placeSprite(ax, ay, az, 0, 0, 0, DumpTruck.Hopper2dAnchorSprite)
    if not anchorOk then
        failed = failed + 1
    end
    return {
        ok = failed == 0,
        anchor = anchorOk,
        mode = "flood",
        placed = placed,
        failed = failed,
        cells = #cells,
        deckAsFloor = deckAsFloor(),
        x = ax,
        y = ay,
        z = az,
    }
end

-- Hybrid: vanilla construction posts + sandstone deck only (mesh footprint).
-- Legs match generate_hopper / slice: X ±2.40 → ±2; Y ±3.30 → 3 and -4; mid -1,0.
-- Deck ring thicker on N/S; chute opening empty. No ducts / clutter props.
local function stampHybrid(ax, ay, az)
    local legs = {
        { -2, -4 }, { 2, -4 },
        { -2, 3 }, { 2, 3 },
        { -2, -1 }, { 2, -1 },
        { -2, 0 }, { 2, 0 },
    }
    local posts = 0
    for i = 1, #legs do
        local p = legs[i]
        placeFloor(ax, ay, az, p[1], p[2], 0, PROOF_FLOOR) -- footer pad
        for fz = 0, 2 do
            if placeSprite(ax, ay, az, p[1], p[2], fz, PROOF_POST) then
                posts = posts + 1
            end
        end
    end

    -- Deck: outer x -3..3, y -5..4 (extra walk N/S). Hole ≈ bin (±1.5).
    local floors = 0
    local rails = 0
    for dx = -3, 3 do
        for dy = -5, 4 do
            local inHole = (math.abs(dx) <= 1 and math.abs(dy) <= 1)
            if not inHole then
                if placeFloor(ax, ay, az, dx, dy, 3, PROOF_FLOOR) then
                    floors = floors + 1
                end
                local onRim = (dx == -3 or dx == 3 or dy == -5 or dy == 4)
                if onRim then
                    if placeSprite(ax, ay, az, dx, dy, 3, PROOF_RAIL) then
                        rails = rails + 1
                    end
                end
            end
        end
    end

    return {
        ok = posts > 0 and floors > 0,
        mode = "hybrid",
        posts = posts,
        floors = floors,
        rails = rails,
        x = ax,
        y = ay,
        z = az,
    }
end

local function registerDevHook()
    if PzDevMcpHooks == nil or PzDevMcpHooks.register == nil then
        return
    end
    -- Capture prior G3 placeHopper if present by wrapping.
    PzDevMcpHooks.register("DumpTruck.placeHopper", function(payload)
        local player = getPlayer()
        if player == nil then
            return { ok = false, error = "no player" }
        end
        local square = player:getCurrentSquare()
        if square == nil then
            return { ok = false, error = "no square" }
        end
        local ax, ay, az = square:getX(), square:getY(), square:getZ()
        local mode = "g3"
        if payload ~= nil and payload.mode ~= nil then
            mode = payload.mode
        end
        if mode == "proof1" or mode == "proof2" or mode == "proof3"
            or mode == "flood" or mode == "hybrid"
            or mode == "calib" or mode == "dig1" or mode == "dig2" or mode == "dig3"
            or mode == "fixture" or mode == "floorpath" then
            -- Multi-floor stamps use dz offsets from ground; keep anchor at z=0.
            az = 0
            clearArea(ax, ay, az, 20)
            if mode == "proof1" then
                return stampProof1(ax, ay, az)
            elseif mode == "proof2" then
                return stampProof2(ax, ay, az)
            elseif mode == "proof3" then
                return stampProof3(ax, ay, az)
            elseif mode == "hybrid" then
                return stampHybrid(ax, ay, az)
            elseif mode == "dig1" then
                return stampDig1(ax, ay, az)
            elseif mode == "dig2" then
                return stampDig2(ax, ay, az)
            elseif mode == "dig3" then
                return stampDig3(ax, ay, az)
            elseif mode == "calib" then
                return stampCalib(ax, ay, az)
            elseif mode == "fixture" then
                return stampFixture(ax, ay, az)
            elseif mode == "floorpath" then
                return stampFloorPath(ax, ay, az)
            end
            return stampFlood(ax, ay, az)
        end
        -- Default: G3 3D stamp (same as LoadingHopperBind).
        clearArea(ax, ay, az, 20)
        local ANCHOR = "loading_hopper_0"
        local obj = IsoObject.new(getCell(), square, ANCHOR)
        square:AddTileObject(obj)
        if DumpTruck.bindHopperModel ~= nil then
            DumpTruck.bindHopperModel(obj, ANCHOR)
        end
        -- Trigger existing stamp via OnObjectAdded path: place then let Bind stamp.
        -- Force stamp by placing anchor; Bind's consider/stamp runs on add.
        return { ok = true, mode = "g3", x = ax, y = ay, z = az, note = "anchor placed; Bind stamps PIECES" }
    end)
end

Events.OnGameStart.Add(registerDevHook)
registerDevHook()
