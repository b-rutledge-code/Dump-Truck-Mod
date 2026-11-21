-- Preset hopper flood + road-drive layout. Runs on the world owner (SP / dedicated).
-- Layout: docs/design-notes.md (Preset tower sites).

DumpTruck = DumpTruck or {}

local PROOF_FLOOR = "floors_exterior_tilesandstone_01_4"
local PROOF_POST = "construction_01_48"
local PROOF_RAIL = "fixtures_railings_01_27"
local GRAVEL_SPRITE = "blends_street_01_48"
local SIDE_W = "blends_natural_01_57"
local SIDE_E = "blends_natural_01_58"

-- Hopper cell extents (gx/gy) from LoadingHopper2dCells; drive is relative to anchor.
local HOPPER_GX_MIN, HOPPER_GX_MAX = -4, 3
local HOPPER_GY_MIN, HOPPER_GY_MAX = -5, 4
local DRIVE_DX_MIN, DRIVE_DX_MAX = -2, 1
local DRIVE_DY_MIN, DRIVE_DY_MAX = -8, 3

local function squareAt(x, y, z)
    local cell = getCell()
    if cell == nil then
        return nil
    end
    if cell.getOrCreateGridSquare ~= nil then
        return cell:getOrCreateGridSquare(x, y, z)
    end
    return cell:getGridSquare(x, y, z)
end

local function squareExisting(x, y, z)
    local cell = getCell()
    if cell == nil then
        return nil
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

local function squareHasSprite(sq, name)
    if sq == nil or name == nil then
        return false
    end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        if spriteName(objs:get(i)) == name then
            return true
        end
    end
    return false
end

local function removeObject(sq, obj)
    if sq == nil or obj == nil then
        return
    end
    if sq.transmitRemoveItemFromSquare ~= nil then
        sq:transmitRemoveItemFromSquare(obj)
    else
        sq:RemoveTileObject(obj)
    end
end

local function syncAttachedSprites(obj)
    if obj ~= nil and isServer() and obj.transmitUpdatedSpriteToClients ~= nil then
        obj:transmitUpdatedSpriteToClients()
    end
end

local function isProofSprite(name)
    return name == PROOF_FLOOR or name == PROOF_POST or name == PROOF_RAIL
        or (name ~= nil and string.sub(name, 1, 10) == "hopper_2d_")
end

local function isHopperSprite(name)
    return name ~= nil and string.sub(name, 1, 15) == "loading_hopper_"
end

local function isGrimeSprite(name)
    return name ~= nil and string.sub(name, 1, 19) == "overlay_grime_wall_"
end

local function clearArea(ax, ay, az, radius)
    local cell = getCell()
    if cell == nil then
        return
    end
    for dx = -radius, radius do
        for dy = -radius, radius do
            for dz = 0, 3 do
                local sq = cell:getGridSquare(ax + dx, ay + dy, az + dz)
                if sq ~= nil then
                    local objs = sq:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local obj = objs:get(i)
                        local name = spriteName(obj)
                        if isProofSprite(name) or isHopperSprite(name) or isGrimeSprite(name) then
                            removeObject(sq, obj)
                        end
                    end
                end
            end
        end
    end
end

local function placeSprite(ax, ay, az, dx, dy, dz, name)
    local dest = squareAt(ax + dx, ay + dy, az + dz)
    if dest == nil or name == nil then
        return nil
    end
    if squareHasSprite(dest, name) then
        return true
    end
    local obj = IsoObject.new(getCell(), dest, name)
    if dest.transmitAddObjectToSquare ~= nil then
        dest:transmitAddObjectToSquare(obj, -1)
    else
        dest:AddTileObject(obj)
    end
    if dest.RecalcProperties ~= nil then
        dest:RecalcProperties()
    end
    if dest.RecalcAllWithNeighbours ~= nil then
        dest:RecalcAllWithNeighbours(true)
    end
    return obj
end

local function placeFloor(ax, ay, az, dx, dy, dz, name)
    local dest = squareAt(ax + dx, ay + dy, az + dz)
    if dest == nil or name == nil then
        return false
    end
    if squareHasSprite(dest, name) then
        return true
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

local function deckAsFloor()
    return DumpTruck.Hopper2dDeckAsFloor == true
end

local function placeByKind(ax, ay, az, dx, dy, dz, name, kind)
    if kind == "floor" and deckAsFloor() then
        return placeFloor(ax, ay, az, dx, dy, dz, name)
    end
    return placeSprite(ax, ay, az, dx, dy, dz, name)
end

local function placeCell(ax, ay, az, c)
    if c.edge then
        -- transparentFloor needs a square below it, or the engine culls the square as covering.
        squareAt(ax + c.gx, ay + c.gy, az + c.fz - 1)
    end
    local kind = c.kind or "object"
    local placed = placeByKind(ax, ay, az, c.gx, c.gy, c.fz, c.sprite, kind)
    return placed and true or false
end

local function placeFlood(ax, ay, az)
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
    local anchorOk = placeSprite(ax, ay, az, 0, 0, 0, DumpTruck.Hopper2dAnchorSprite)
    if not anchorOk then
        failed = failed + 1
    end
    return {
        ok = failed == 0,
        anchor = anchorOk and true or false,
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

local function removeSpriteAt(x, y, z, name)
    local sq = squareAt(x, y, z)
    if sq == nil then
        return false
    end
    local hit = false
    local objs = sq:getObjects()
    for i = objs:size() - 1, 0, -1 do
        local obj = objs:get(i)
        if spriteName(obj) == name then
            removeObject(sq, obj)
            hit = true
        else
            local attached = obj:getAttachedAnimSprite()
            if attached ~= nil then
                local removedAttached = false
                for a = attached:size() - 1, 0, -1 do
                    local parent = attached:get(a):getParentSprite()
                    if parent ~= nil and parent:getName() == name then
                        obj:RemoveAttachedAnim(a)
                        removedAttached = true
                        hit = true
                    end
                end
                if removedAttached then
                    syncAttachedSprites(obj)
                end
            end
        end
    end
    return hit
end

local function spriteHasMowFlag(sprite)
    if sprite == nil then
        return false
    end
    local props = sprite:getProperties()
    if props == nil then
        return false
    end
    return props:has(IsoFlagType.canBeRemoved) or props:has(IsoFlagType.canBeCut)
end

local function isDriveFloorToClear(name)
    if name == nil then
        return false
    end
    return string.sub(name, 1, 16) == "blends_natural_"
end

local function mowSquare(x, y, z)
    local sq = squareAt(x, y, z)
    if sq == nil then
        return 0
    end
    local removed = 0
    local objs = sq:getObjects()
    for i = objs:size() - 1, 0, -1 do
        local obj = objs:get(i)
        local attached = obj:getAttachedAnimSprite()
        local removedAttached = false
        if attached ~= nil then
            for a = attached:size() - 1, 0, -1 do
                local parent = attached:get(a):getParentSprite()
                local pname = parent ~= nil and parent:getName() or nil
                if spriteHasMowFlag(parent) or isDriveFloorToClear(pname) then
                    obj:RemoveAttachedAnim(a)
                    removedAttached = true
                    removed = removed + 1
                end
            end
        end
        if removedAttached then
            syncAttachedSprites(obj)
        end
        local spr = obj:getSprite()
        local name = spriteName(obj)
        if spriteHasMowFlag(spr) or isDriveFloorToClear(name) then
            removeObject(sq, obj)
            removed = removed + 1
        end
    end
    return removed
end

local function disableErosionOnSquare(sq)
    if sq == nil then
        return
    end
    if sq.disableErosion ~= nil then
        sq:disableErosion()
    end
    if isServer() then
        sendServerCommand("DumpTruckGravelMod", "disableErosionAt", {
            x = sq:getX(),
            y = sq:getY(),
            z = sq:getZ(),
        })
    end
end

local function placeGravelFloor(x, y, z)
    local dest = squareAt(x, y, z)
    if dest == nil then
        return false
    end
    if squareHasSprite(dest, GRAVEL_SPRITE) then
        disableErosionOnSquare(dest)
        return true
    end
    if dest.addFloor ~= nil then
        dest:addFloor(GRAVEL_SPRITE)
    else
        if placeSprite(x, y, z, 0, 0, 0, GRAVEL_SPRITE) == nil then
            return false
        end
    end
    disableErosionOnSquare(dest)
    if dest.RecalcProperties ~= nil then
        dest:RecalcProperties()
    end
    if dest.RecalcAllWithNeighbours ~= nil then
        dest:RecalcAllWithNeighbours(true)
    end
    return true
end

-- True when ground squares for the hopper (and drive, unless drive=false) already exist.
-- Uses getGridSquare only — never creates — so dedicated skips unloadable cells.
function DumpTruck.presetFootprintLoaded(ax, ay, opts)
    opts = opts or {}
    local points = {
        { ax + HOPPER_GX_MIN, ay + HOPPER_GY_MIN },
        { ax + HOPPER_GX_MAX, ay + HOPPER_GY_MIN },
        { ax + HOPPER_GX_MIN, ay + HOPPER_GY_MAX },
        { ax + HOPPER_GX_MAX, ay + HOPPER_GY_MAX },
        { ax, ay },
    }
    if opts.drive ~= false then
        table.insert(points, { ax + DRIVE_DX_MIN, ay + DRIVE_DY_MIN })
        table.insert(points, { ax + DRIVE_DX_MAX, ay + DRIVE_DY_MIN })
        table.insert(points, { ax + DRIVE_DX_MIN, ay + DRIVE_DY_MAX })
        table.insert(points, { ax + DRIVE_DX_MAX, ay + DRIVE_DY_MAX })
    end
    for i = 1, #points do
        local p = points[i]
        if squareExisting(p[1], p[2], 0) == nil then
            return false
        end
    end
    return true
end

DumpTruck.clearHopperArea = clearArea
DumpTruck.placeHopperSprite = placeSprite
DumpTruck.placeHopperFloor = placeFloor
DumpTruck.hopperSquareAt = squareAt
DumpTruck.hopperSpriteName = spriteName

DumpTruck.floodAt = function(ax, ay)
    clearArea(ax, ay, 0, 20)
    return placeFlood(ax, ay, 0)
end

-- Preset site at hopper anchor (ax, ay). opts from PresetTowerSites:
--   drive ~= false → mow, gravel, junction cuts, side blends
--   drive == false → hopper flood only
--   clear = { { dx, dy, sprite }, ... } removed before flood
DumpTruck.placePresetSite = function(ax, ay, opts)
    opts = opts or {}

    local cleared = 0
    if opts.clear ~= nil then
        for _, c in ipairs(opts.clear) do
            if removeSpriteAt(ax + c.dx, ay + c.dy, 0, c.sprite) then
                cleared = cleared + 1
            end
        end
    end

    local flood = DumpTruck.floodAt(ax, ay)
    if flood == nil or flood.ok ~= true then
        return { ok = false, step = "flood", flood = flood, cleared = cleared }
    end

    if opts.drive == false then
        return {
            ok = true,
            flood = flood,
            cleared = cleared,
            mowed = 0,
            gravelPlaced = 0,
            gravelFailed = 0,
            junctionRemoved = 0,
            junctionMissing = 0,
            sidePlaced = 0,
            sideFailed = 0,
            x = ax,
            y = ay,
        }
    end

    local mowed = 0
    for x = ax + DRIVE_DX_MIN, ax + DRIVE_DX_MAX do
        for y = ay + DRIVE_DY_MIN, ay + DRIVE_DY_MAX do
            mowed = mowed + mowSquare(x, y, 0)
        end
    end

    local gravelPlaced = 0
    local gravelFailed = 0
    for x = ax + DRIVE_DX_MIN, ax + DRIVE_DX_MAX do
        for y = ay + DRIVE_DY_MIN, ay + DRIVE_DY_MAX do
            if placeGravelFloor(x, y, 0) then
                gravelPlaced = gravelPlaced + 1
            else
                gravelFailed = gravelFailed + 1
            end
        end
    end

    local junction = {
        { x = ax - 2, y = ay - 9, sprite = "blends_natural_01_59" },
        { x = ax - 1, y = ay - 9, sprite = "blends_natural_01_63" },
        { x = ax, y = ay - 9, sprite = "blends_natural_01_59" },
        { x = ax + 1, y = ay - 9, sprite = "blends_natural_01_63" },
    }
    local junctionRemoved = 0
    local junctionMissing = 0
    for _, t in ipairs(junction) do
        if removeSpriteAt(t.x, t.y, 0, t.sprite) then
            junctionRemoved = junctionRemoved + 1
        else
            junctionMissing = junctionMissing + 1
        end
    end

    local sidePlaced = 0
    local sideFailed = 0
    for y = ay + DRIVE_DY_MIN, ay + DRIVE_DY_MAX do
        if placeSprite(ax - 2, y, 0, 0, 0, 0, SIDE_W) then
            sidePlaced = sidePlaced + 1
        else
            sideFailed = sideFailed + 1
        end
        if placeSprite(ax + 1, y, 0, 0, 0, 0, SIDE_E) then
            sidePlaced = sidePlaced + 1
        else
            sideFailed = sideFailed + 1
        end
    end

    return {
        ok = gravelFailed == 0 and sideFailed == 0,
        flood = flood,
        cleared = cleared,
        mowed = mowed,
        gravelPlaced = gravelPlaced,
        gravelFailed = gravelFailed,
        junctionRemoved = junctionRemoved,
        junctionMissing = junctionMissing,
        sidePlaced = sidePlaced,
        sideFailed = sideFailed,
        x = ax,
        y = ay,
    }
end
