-- Early 2D-building proofs. Re-registers DumpTruck.placeHopper with payload.mode.
-- Placement helpers / flood / placePresetSite live in shared DumpTruckPresetSite.lua.
-- mode nil/"g3" = existing 3D G3 stamp (LoadingHopperBind).
-- mode "proof1" | "proof2" | "proof3" = kill-criteria stamps.

DumpTruck = DumpTruck or {}

local PROOF_FLOOR = "floors_exterior_tilesandstone_01_4"
local PROOF_POST = "construction_01_48"
local PROOF_RAIL = "fixtures_railings_01_27"

local function squareAt(x, y, z)
    if DumpTruck.hopperSquareAt ~= nil then
        return DumpTruck.hopperSquareAt(x, y, z)
    end
    local cell = getCell()
    if cell.getOrCreateGridSquare ~= nil then
        return cell:getOrCreateGridSquare(x, y, z)
    end
    return cell:getGridSquare(x, y, z)
end

local function spriteName(obj)
    if DumpTruck.hopperSpriteName ~= nil then
        return DumpTruck.hopperSpriteName(obj)
    end
    if obj == nil then
        return nil
    end
    local spr = obj:getSprite()
    if spr == nil then
        return nil
    end
    return spr:getName()
end

local function clearArea(ax, ay, az, radius)
    if DumpTruck.clearHopperArea ~= nil then
        DumpTruck.clearHopperArea(ax, ay, az, radius)
        return
    end
end

local function placeSprite(ax, ay, az, dx, dy, dz, name)
    if DumpTruck.placeHopperSprite ~= nil then
        return DumpTruck.placeHopperSprite(ax, ay, az, dx, dy, dz, name)
    end
    return nil
end

local function placeFloor(ax, ay, az, dx, dy, dz, name)
    if DumpTruck.placeHopperFloor ~= nil then
        return DumpTruck.placeHopperFloor(ax, ay, az, dx, dy, dz, name)
    end
    return false
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
        squareAt(ax + c.gx, ay + c.gy, az + c.fz - 1)
    end
    local kind = c.kind or "object"
    local placed = placeByKind(ax, ay, az, c.gx, c.gy, c.fz, c.sprite, kind)
    return placed and true or false
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
    return { ok = true, mode = "proof2", cells = 8, x = ax, y = ay, z = az }
end

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
    placeFloor(ax, ay, az, 1, 0, 3, PROOF_FLOOR)
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
        placeFloor(ax, ay, az, p[1], p[2], 0, PROOF_FLOOR)
        for fz = 0, 2 do
            if placeSprite(ax, ay, az, p[1], p[2], fz, PROOF_POST) then
                posts = posts + 1
            end
        end
    end
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
        if mode == "tiles" then
            local placed = 0
            local failed = 0
            for _, t in ipairs(payload.tiles) do
                local z = t.z or 0
                if placeSprite(t.x, t.y, z, 0, 0, 0, t.sprite) then
                    placed = placed + 1
                else
                    failed = failed + 1
                end
            end
            return { ok = failed == 0, mode = "tiles", placed = placed, failed = failed }
        end
        if mode == "removevehicles" then
            local radius = payload.radius or 20
            local current = player:getVehicle()
            local vehicles = getCell():getVehicles()
            local targets = {}
            local it = vehicles:iterator()
            while it:hasNext() do
                local v = it:next()
                local dx = v:getX() - ax
                local dy = v:getY() - ay
                if dx * dx + dy * dy <= radius * radius and v ~= current then
                    table.insert(targets, v)
                end
            end
            for _, v in ipairs(targets) do
                v:permanentlyRemove()
            end
            return { ok = true, mode = "removevehicles", removed = #targets, skippedPlayerVehicle = current ~= nil }
        end
        if mode == "untiles" then
            local removed = 0
            local missing = 0
            for _, t in ipairs(payload.tiles) do
                local sq = squareAt(t.x, t.y, t.z or 0)
                local hit = false
                if sq ~= nil then
                    local objs = sq:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local obj = objs:get(i)
                        if spriteName(obj) == t.sprite then
                            if sq.transmitRemoveItemFromSquare ~= nil then
                                sq:transmitRemoveItemFromSquare(obj)
                            else
                                sq:RemoveTileObject(obj)
                            end
                            hit = true
                        end
                        local attached = obj:getAttachedAnimSprite()
                        if attached ~= nil then
                            for a = attached:size() - 1, 0, -1 do
                                local parent = attached:get(a):getParentSprite()
                                if parent ~= nil and parent:getName() == t.sprite then
                                    obj:RemoveAttachedAnim(a)
                                    hit = true
                                end
                            end
                        end
                    end
                end
                if hit then
                    removed = removed + 1
                else
                    missing = missing + 1
                end
            end
            return { ok = missing == 0, mode = "untiles", removed = removed, missing = missing }
        end
        if mode == "clear" then
            local radius = 20
            if payload ~= nil and payload.radius ~= nil then
                radius = payload.radius
            end
            clearArea(ax, ay, 0, radius)
            return { ok = true, mode = "clear", x = ax, y = ay, z = 0, radius = radius }
        end
        if mode == "preset" then
            if payload ~= nil and payload.x ~= nil and payload.y ~= nil then
                ax, ay = math.floor(payload.x), math.floor(payload.y)
            end
            if DumpTruck.placePresetSite == nil then
                return { ok = false, error = "placePresetSite missing" }
            end
            return DumpTruck.placePresetSite(ax, ay, payload)
        end
        if mode == "proof1" or mode == "proof2" or mode == "proof3"
            or mode == "flood" or mode == "hybrid"
            or mode == "calib" or mode == "dig1" or mode == "dig2" or mode == "dig3"
            or mode == "fixture" or mode == "floorpath" then
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
            if DumpTruck.floodAt ~= nil then
                return DumpTruck.floodAt(ax, ay)
            end
            return { ok = false, error = "floodAt missing" }
        end
        clearArea(ax, ay, az, 20)
        local ANCHOR = "loading_hopper_0"
        local obj = IsoObject.new(getCell(), square, ANCHOR)
        if square.transmitAddObjectToSquare ~= nil then
            square:transmitAddObjectToSquare(obj, -1)
        else
            square:AddTileObject(obj)
        end
        if DumpTruck.bindHopperModel ~= nil then
            DumpTruck.bindHopperModel(obj, ANCHOR)
        end
        return { ok = true, mode = "g3", x = ax, y = ay, z = az, note = "anchor placed; Bind stamps PIECES" }
    end)
end

Events.OnGameStart.Add(registerDevHook)
registerDevHook()
