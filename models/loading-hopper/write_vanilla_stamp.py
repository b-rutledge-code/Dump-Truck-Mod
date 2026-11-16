"""Write LoadingHopperBind.lua for the vanilla steel + custom bin stamp."""

from __future__ import annotations

import os

OUT = (
    "/Users/jamesrutledge/pz-modding/mods/DumpTruckGravelMod/"
    "Contents/mods/DumpTruckGravelMod/42.20/media/lua/client/DumpTruck/LoadingHopperBind.lua"
)

BELT = "location_business_machinery_01_4"
BELT_END = "location_business_machinery_01_3"
ROLLER = "location_business_machinery_01_0"
FLOOR = "industry_01_16"
GRATE = "industry_01_37"
POST = "industry_02_24"
RAIL_W = "industry_02_8"
RAIL_N = "industry_02_9"
STAIR_BW = "fixtures_stairs_01_3"
STAIR_MW = "fixtures_stairs_01_4"
STAIR_TW = "fixtures_stairs_01_5"
STAIR_BN = "fixtures_stairs_01_11"
STAIR_MN = "fixtures_stairs_01_12"
STAIR_TN = "fixtures_stairs_01_13"

# Custom bin (one alwaysDraw spriteModel spanning the 2×2 opening).
BIN = {
    (-1, 0, 2): "loading_hopper_bin_1",
}


def add(pieces: list, x: int, y: int, z: int, sprite: str) -> None:
    pieces.append((x, y, z, sprite))


def build() -> list[tuple[int, int, int, str]]:
    pieces: list[tuple[int, int, int, str]] = []

    # Ground posts around the truck bay.
    for x, y in ((-2, -3), (1, -3), (-2, 2), (1, 2), (-2, -1), (1, -1), (-2, 0), (1, 0)):
        add(pieces, x, y, 0, POST)

    # Belt feed on ground (−X / y=0), rollers at the foot.
    add(pieces, 5, 0, 0, ROLLER)
    for x in (4, 3, 2, 1):
        add(pieces, x, 0, 0, BELT)
    add(pieces, 0, 0, 0, BELT_END)

    # Switchback stairs (+Y side, clear of the 2×2 bay opening).
    # F1 west, z=0: foot east → TW west.
    add(pieces, 2, 4, 0, STAIR_BW)
    add(pieces, 1, 4, 0, STAIR_MW)
    add(pieces, 0, 4, 0, STAIR_TW)
    # F2 north, z=1: BN on F1 landing square → TN toward bay.
    add(pieces, -1, 4, 1, STAIR_BN)
    add(pieces, -1, 3, 1, STAIR_MN)
    add(pieces, -1, 2, 1, STAIR_TN)
    # Landing after F2, then F3 west onto deck.
    add(pieces, -1, 1, 2, FLOOR)
    add(pieces, 2, 1, 2, STAIR_BW)
    add(pieces, 1, 1, 2, STAIR_MW)
    add(pieces, 0, 1, 2, STAIR_TW)

    # Belt climbs with landings (short horizontal runs beside the bay).
    add(pieces, -1, -2, 1, BELT)
    add(pieces, -1, -2, 2, BELT)
    add(pieces, -2, -2, 3, BELT_END)

    # Deck ring at z=3; 2×2 bay opening left empty for the chute.
    opening = {(-1, -1), (0, -1), (-1, 0), (0, 0)}
    for x in range(-3, 3):
        for y in range(-3, 4):
            if (x, y) in opening:
                continue
            add(pieces, x, y, 3, FLOOR)

    # Stair top lands on deck west of TW.
    add(pieces, -2, 3, 3, FLOOR)

    # Rails on deck outer edges (gap at stair arrival on −X at y=1).
    for y in range(-3, 4):
        if y == 1:
            continue
        add(pieces, -3, y, 3, RAIL_W)
        add(pieces, 2, y, 3, RAIL_W)
    for x in range(-3, 3):
        add(pieces, x, -3, 3, RAIL_N)
        add(pieces, x, 3, 3, RAIL_N)

    # Mid posts under deck corners.
    for x, y in ((-3, -3), (2, -3), (-3, 3), (2, 3)):
        add(pieces, x, y, 1, POST)
        add(pieces, x, y, 2, POST)

    # Stair top deck landing (west of F3 TW).
    add(pieces, -1, 1, 3, FLOOR)

    # Custom hopper bin visuals over the opening.
    for (x, y, z), sprite in sorted(BIN.items()):
        add(pieces, x, y, z, sprite)

    # Open bay under bin: grate fringe only (optional look).
    for x, y in ((-2, -1), (1, -1), (-2, 0), (1, 0)):
        add(pieces, x, y, 0, GRATE)

    return pieces


def write_lua(pieces: list[tuple[int, int, int, str]]) -> None:
    bin_names = set(BIN.values()) | {"loading_hopper_bin_0"}
    rows = []
    for x, y, z, sprite in pieces:
        rows.append('    {%d, %d, %d, "%s"},' % (x, y, z, sprite))
    body = "\n".join(rows)
    bin_list = ", ".join('["%s"] = true' % n for n in sorted(bin_names))
    text = '''-- Vanilla steel tower + custom hopper bin. Anchor is loading_hopper_bin_0.

local ANCHOR = "loading_hopper_bin_0"
local BIN_SPRITES = { %s }
local PIECES = {
%s
}

local busy = false

local function spriteName(obj)
    if obj == nil or obj.getSprite == nil then
        return nil
    end
    local spr = obj:getSprite()
    if spr == nil or spr.getName == nil then
        return nil
    end
    return spr:getName()
end

local function hasSprite(square, name)
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        if spriteName(objs:get(i)) == name then
            return true
        end
    end
    return false
end

local function squareAt(x, y, z)
    local cell = getCell()
    local square = cell:getGridSquare(x, y, z)
    if square == nil then
        square = cell:createNewGridSquare(x, y, z, true)
    end
    return square
end

local function bindBinModel(obj, name)
    if BIN_SPRITES[name] and obj ~= nil and obj.setSpriteModelName ~= nil then
        obj:setSpriteModelName(name)
    end
    if obj ~= nil and obj.invalidateRenderChunkLevel ~= nil then
        obj:invalidateRenderChunkLevel(136)
    end
end

local function stamp(anchor)
    if busy or anchor == nil then
        return
    end
    local data = anchor:getModData()
    if data.hopperGrid then
        return
    end
    local square = anchor:getSquare()
    if square == nil then
        return
    end
    busy = true
    local ax, ay, az = square:getX(), square:getY(), square:getZ()
    bindBinModel(anchor, ANCHOR)
    for i = 1, #PIECES do
        local piece = PIECES[i]
        local dest = squareAt(ax + piece[1], ay + piece[2], az + piece[3])
        if dest ~= nil and not hasSprite(dest, piece[4]) then
            local obj = IsoObject.new(getCell(), dest, piece[4])
            dest:AddTileObject(obj)
            bindBinModel(obj, piece[4])
            if dest.RecalcProperties ~= nil then
                dest:RecalcProperties()
            end
            if dest.RecalcAllWithNeighbours ~= nil then
                dest:RecalcAllWithNeighbours(true)
            end
        end
    end
    data.hopperGrid = true
    busy = false
end

local function onAnchor(isoObject)
    if isoObject == nil then
        return
    end
    if spriteName(isoObject) ~= ANCHOR then
        return
    end
    stamp(isoObject)
end

Events.OnObjectAdded.Add(onAnchor)

Events.LoadGridsquare.Add(function(square)
    if square == nil then
        return
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if spriteName(obj) == ANCHOR then
            stamp(obj)
            return
        end
    end
end)

local function registerDevHook()
    if PzDevMcpHooks == nil then
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
        if hasSprite(square, ANCHOR) then
            local objs = square:getObjects()
            for i = 0, objs:size() - 1 do
                local obj = objs:get(i)
                if spriteName(obj) == ANCHOR then
                    obj:getModData().hopperGrid = nil
                    stamp(obj)
                    return { ok = true, restamped = true }
                end
            end
        end
        local obj = IsoObject.new(getCell(), square, ANCHOR)
        square:AddTileObject(obj)
        stamp(obj)
        return { ok = true, x = square:getX(), y = square:getY(), z = square:getZ() }
    end)
end

Events.OnGameStart.Add(registerDevHook)
registerDevHook()
''' % (bin_list, body)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("wrote", OUT, "pieces", len(pieces))


if __name__ == "__main__":
    write_lua(build())
