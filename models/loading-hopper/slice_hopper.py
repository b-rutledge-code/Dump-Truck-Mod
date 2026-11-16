"""Cut the hopper into game tiles.

Visuals are one mesh per occupied (gx, gy, stamp-floor) cell. Band 1 merges
into the ground stamp for outdoor light. Band 2 and rim stamp one floor below
the deck solidfloor so the walkway and bin lip stay one mesh. Deck walk uses
invisible solidfloor (+ ForceAmbient) on the real deck level. Verts keep
absolute Z and no floor flag. Legs are solid.

The anchor is the lowest mesh at the bay-center column. One blender meter is
one tile; a floor is FLOOR_M meters. The game draws a model from the center of
its square with blender +X toward world -X, so the tile layout is mirrored in X.

Run in Blender with object loading_hopper (Z up, meters, origin at bay center).
"""

import math
import os
import struct

import bmesh
import bpy
from mathutils import Vector

# One floor is 2.44949 mesh meters. The camera's 1.5 scale already cancels undoCoreScale.
FLOOR_M = 2.44949
DECK_Z = 7.40
RIM_LEVEL = int(math.floor(DECK_Z / FLOOR_M))
# Rim meshes stamp one floor below so they stay drawn under the chute.
RIM_VISUAL_LEVEL = RIM_LEVEL - 1
HX = 2.40
HY = 3.30

REPO = "/Users/jamesrutledge/pz-modding/mods/DumpTruckGravelMod/Contents/mods/DumpTruckGravelMod"
MESH_DIR = os.path.join(REPO, "42.20/media/models_X/IsoObject")
SCRIPT_PATH = os.path.join(REPO, "42.20/media/scripts/loading_hopper.txt")
TILES_PATH = os.path.join(REPO, "42.20/media/loading_hopper.tiles")
LUA_PATH = os.path.join(REPO, "42.20/media/lua/client/DumpTruck/LoadingHopperBind.lua")
SPRITE_MODELS = os.path.join(REPO, "common/media/spriteModels.txt")


def clip_plane(poly, axis, limit, keep_ge):
    if not poly:
        return []
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        av = a[0][axis]
        bv = b[0][axis]
        a_in = av >= limit - 1e-8 if keep_ge else av <= limit + 1e-8
        b_in = bv >= limit - 1e-8 if keep_ge else bv <= limit + 1e-8
        if a_in and b_in:
            out.append(b)
        elif a_in != b_in:
            denom = bv - av
            t = 0.0 if abs(denom) < 1e-12 else (limit - av) / denom
            t = min(max(t, 0.0), 1.0)
            pos = a[0].lerp(b[0], t)
            uv = (
                a[1][0] + (b[1][0] - a[1][0]) * t,
                a[1][1] + (b[1][1] - a[1][1]) * t,
            )
            out.append((pos, uv))
            if b_in:
                out.append(b)
    return out


def clip_z(tri, z0, z1):
    return clip_span([tri], 2, z0, z1)


def clip_span(tris, axis, lo, hi):
    # The upper bound belongs to the next tile, so a face on the grid line is not drawn twice.
    hi = hi - 1e-5
    out = []
    for tri in tris:
        poly = clip_plane(list(tri), axis, lo, True)
        poly = clip_plane(poly, axis, hi, False)
        if len(poly) < 3:
            continue
        origin = poly[0]
        for i in range(1, len(poly) - 1):
            a, b, c = origin, poly[i], poly[i + 1]
            if (b[0] - a[0]).cross(c[0] - a[0]).length > 1e-6:
                out.append((a, b, c))
    return out


def world_col(x):
    """World column of a blender X. The game draws blender +X toward world -X."""
    return -int(math.floor(x)) - 1


def deck_cover(tris):
    """Area of deck plate top inside one tile, in square meters."""
    total = 0.0
    for tri in tris:
        a, b, c = tri[0][0], tri[1][0], tri[2][0]
        if max(abs(a.z - DECK_Z), abs(b.z - DECK_Z), abs(c.z - DECK_Z)) > 0.01:
            continue
        up = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if up > 0.0:
            total += up * 0.5
    return total


def mesh_cells(tris):
    """One XY cell per stamp floor.

    Band 1 → z=0 (outdoor light). Band 2 and rim → rim visual so the deck and
    bin lip stay one mesh. Absolute vertex Z is unchanged.
    """
    minx = min(pt[0].x for tri in tris for pt in tri)
    maxx = max(pt[0].x for tri in tris for pt in tri)
    miny = min(pt[0].y for tri in tris for pt in tri)
    maxy = max(pt[0].y for tri in tris for pt in tri)
    maxz = max(pt[0].z for tri in tris for pt in tri)
    gx0 = int(math.floor(minx))
    gx1 = int(math.floor(maxx - 1e-6))
    gy0 = int(math.floor(miny))
    gy1 = int(math.floor(maxy - 1e-6))
    fz1 = int(math.floor((maxz - 1e-6) / FLOOR_M))
    merged = {}
    for fz in range(0, fz1 + 1):
        z0 = fz * FLOOR_M
        z1 = z0 + FLOOR_M
        shell = []
        for tri in tris:
            shell.extend(clip_z(tri, z0, z1))
        print("floor", fz, "tris", len(shell))
        for gx in range(gx0, gx1 + 1):
            column = clip_span(shell, 0, float(gx), float(gx + 1))
            if not column:
                continue
            for gy in range(gy0, gy1 + 1):
                cell = clip_span(column, 1, float(gy), float(gy + 1))
                if not cell:
                    continue
                if fz == RIM_LEVEL or fz == RIM_VISUAL_LEVEL:
                    stamp_fz = RIM_VISUAL_LEVEL
                elif fz >= 1:
                    stamp_fz = 0
                else:
                    stamp_fz = fz
                key = (gx, gy, stamp_fz)
                if key in merged:
                    band, tris_acc = merged[key]
                    tris_acc.extend(cell)
                    merged[key] = (max(band, fz), tris_acc)
                else:
                    merged[key] = (fz, list(cell))
    cells = [
        (gx, gy, stamp_fz, band, cell)
        for (gx, gy, stamp_fz), (band, cell) in merged.items()
    ]
    cells.sort(key=lambda c: (c[2], c[1], c[0], c[3]))
    print(
        "mesh cells",
        len(cells),
        "x",
        gx0,
        gx1,
        "y",
        gy0,
        gy1,
        "floors",
        fz1,
        "rim_level",
        RIM_LEVEL,
        "rim_visual",
        RIM_VISUAL_LEVEL,
    )
    return cells


def read_tris(obj):
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    uv_lay = bm.loops.layers.uv.active
    tris = []
    for face in bm.faces:
        if len(face.verts) != 3:
            continue
        pts = []
        for loop in face.loops:
            uv = loop[uv_lay].uv
            pts.append((loop.vert.co.copy(), (uv.x, uv.y)))
        tris.append(pts)
    bm.free()
    return tris


def export_mesh(name, tris, origin):
    vertices = []
    uvs = []
    faces = []
    for tri in tris:
        start = len(vertices)
        for pos, uv in tri:
            # Measured from the center of the piece's tile, which is where the game draws from.
            local = pos - origin
            vertices.append((local.x, local.y, local.z))
            uvs.append(uv)
        faces.append((start, start + 1, start + 2))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for index, loop in enumerate(mesh.loops):
        layer.data[index].uv = uvs[index]
    # Clipped floor bands can leave flipped winding; fix before FBX.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(MESH_DIR, name + ".fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=False,
        add_leaf_bones=False,
        mesh_smooth_type="OFF",
        use_triangles=True,
        path_mode="AUTO",
        embed_textures=False,
    )
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.meshes.remove(mesh)


def write_tiles(pieces):
    def s(text):
        return text.encode("utf-8") + b"\n"

    body = bytearray()
    body += s("loading_hopper")
    body += s("loading_hopper")
    n = len(pieces)
    cols = 8
    rows = max(1, (n + cols - 1) // cols)
    body += struct.pack("<iiii", cols, rows, 1, n)
    for piece in pieces:
        props = []
        if piece["mesh"] or piece.get("invisible"):
            # Hide 2D tile; ForceAmbient so open-air z>0 floors are not black voids.
            props.append(("invisible", ""))
            props.append(("alwaysDraw", ""))
            props.append(("NeverCutaway", ""))
            props.append(("ForceAmbient", ""))
        if piece["ix"] == 0:
            props.append(("CustomName", "Loading Hopper"))
        if piece["solid"]:
            props.append(("solid", ""))
        if piece["floor"]:
            props.append(("solidfloor", ""))
        if piece.get("stair"):
            props.append((piece["stair"], ""))
        body += struct.pack("<i", len(props))
        for key, val in props:
            body += s(key)
            body += s(val)
    out = bytearray()
    out += b"tdef"
    out += struct.pack("<ii", 1, 1)
    out += body
    with open(TILES_PATH, "wb") as handle:
        handle.write(out)


def write_scripts(pieces):
    lines = ["module Base", "{"]
    for piece in pieces:
        if not piece["mesh"]:
            continue
        lines.append("    model LoadingHopper_%d" % piece["ix"])
        lines.append("    {")
        lines.append("        mesh = IsoObject/%s," % piece["mesh"])
        lines.append("        texture = IsoObject/loading_hopper,")
        lines.append("        scale = 1.0,")
        lines.append("        static = true,")
        lines.append("        undoCoreScale = true,")
        lines.append("    }")
        lines.append("")
        lines.append("    spriteModel loading_hopper_%d" % piece["ix"])
        lines.append("    {")
        lines.append("        modelScript = Base.LoadingHopper_%d," % piece["ix"])
        lines.append("        translate = 0.0 0.0 0.0,")
        lines.append("        rotate = 0.0 0.0 0.0,")
        lines.append("        scale = 1.0,")
        lines.append("    }")
        lines.append("")
    lines.append("}")
    with open(SCRIPT_PATH, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    sm = [
        "spriteModel",
        "{",
        "    VERSION = 1,",
        "",
        "    tileset",
        "    {",
        "        name = loading_hopper,",
        "",
    ]
    for piece in pieces:
        if not piece["mesh"]:
            continue
        col = piece["ix"] % 8
        row = piece["ix"] // 8
        sm.append("        tile")
        sm.append("        {")
        sm.append("            xy = %d %d," % (col, row))
        sm.append("            modelScript = Base.LoadingHopper_%d," % piece["ix"])
        sm.append("            translate = 0.0000 0.0000 0.0000,")
        sm.append("            rotate = 0.0000 0.0000 0.0000,")
        sm.append("            scale = 1.0000,")
        sm.append("        }")
        sm.append("")
    sm.append("    }")
    sm.append("}")
    os.makedirs(os.path.dirname(SPRITE_MODELS), exist_ok=True)
    with open(SPRITE_MODELS, "w", encoding="utf-8") as handle:
        handle.write("\n".join(sm) + "\n")


def write_lua(pieces):
    anchor = next(piece for piece in pieces if piece["ix"] == 0)
    ax, ay, az = anchor["gx"], anchor["gy"], anchor["fz"]
    rows = []
    for piece in pieces:
        if piece["ix"] == 0:
            continue
        rows.append(
            '    {%d, %d, %d, "loading_hopper_%d"},'
            % (piece["gx"] - ax, piece["gy"] - ay, piece["fz"] - az, piece["ix"])
        )
    body = "\n".join(rows)
    text = """-- Placing the anchor tile stamps the rest of the hopper.
-- Each entry is dx, dy, dz from the anchor square, then the sprite.

local ANCHOR = "loading_hopper_0"
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

local function isHopperName(name)
    return name ~= nil and string.sub(name, 1, 15) == "loading_hopper_"
end

local function squareAt(x, y, z)
    local cell = getCell()
    local square = cell:getGridSquare(x, y, z)
    if square == nil then
        square = cell:createNewGridSquare(x, y, z, true)
    end
    return square
end

local function bindModel(obj, name)
    if obj ~= nil and obj.setSpriteModelName ~= nil then
        obj:setSpriteModelName(name)
    end
    if obj ~= nil and obj.invalidateRenderChunkLevel ~= nil then
        obj:invalidateRenderChunkLevel(136)
    end
end

-- Drop loading_hopper_* nearby so rebuilds are not stuck on old / overlapping meshes.
-- keep_anchor: when true, leave the ANCHOR on (ax,ay,az) alone.
local function clearFootprint(ax, ay, az, keep_anchor)
    local cell = getCell()
    for dx = -20, 20 do
        for dy = -20, 20 do
            for dz = 0, 3 do
                local square = cell:getGridSquare(ax + dx, ay + dy, az + dz)
                if square ~= nil then
                    local objs = square:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local obj = objs:get(i)
                        local name = spriteName(obj)
                        if isHopperName(name) then
                            local same =
                                keep_anchor
                                and name == ANCHOR
                                and square:getX() == ax
                                and square:getY() == ay
                                and square:getZ() == az
                            if not same then
                                square:RemoveTileObject(obj)
                            end
                        end
                    end
                    if square.RecalcProperties ~= nil then
                        square:RecalcProperties()
                    end
                end
            end
        end
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
    clearFootprint(ax, ay, az, true)
    local function place(entry, bind)
        local dest = squareAt(ax + entry[1], ay + entry[2], az + entry[3])
        if dest == nil or hasSprite(dest, entry[4]) then
            return
        end
        local obj = IsoObject.new(getCell(), dest, entry[4])
        dest:AddTileObject(obj)
        if bind then
            bindModel(obj, entry[4])
        end
        if dest.RecalcProperties ~= nil then
            dest:RecalcProperties()
        end
        if dest.RecalcAllWithNeighbours ~= nil then
            dest:RecalcAllWithNeighbours(true)
        end
    end
    for i = 1, #PIECES do
        place(PIECES[i], true)
    end
    bindModel(anchor, ANCHOR)
    data.hopperGrid = true
    if anchor.transmitModData ~= nil then
        anchor:transmitModData()
    end
    busy = false
end

local function consider(obj)
    if spriteName(obj) ~= ANCHOR then
        return
    end
    stamp(obj)
end

Events.LoadGridsquare.Add(function(square)
    if square == nil then
        return
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        consider(objs:get(i))
    end
end)

Events.OnObjectAdded.Add(consider)

Events.OnTick.Add(function()
    local player = getPlayer()
    if player == nil then
        return
    end
    local sq = player:getCurrentSquare()
    if sq == nil then
        return
    end
    local cell = getCell()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for dx = -6, 6 do
        for dy = -6, 6 do
            for dz = 0, 3 do
                local square = cell:getGridSquare(x + dx, y + dy, z + dz)
                if square ~= nil then
                    local objs = square:getObjects()
                    for i = 0, objs:size() - 1 do
                        consider(objs:get(i))
                    end
                end
            end
        end
    end
end)

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
        -- Scrub every hopper in range (including other anchors), then one fresh stamp.
        clearFootprint(ax, ay, az, false)
        local obj = IsoObject.new(getCell(), square, ANCHOR)
        square:AddTileObject(obj)
        bindModel(obj, ANCHOR)
        stamp(obj)
        return { ok = true, x = ax, y = ay, z = az }
    end)
end

Events.OnGameStart.Add(registerDevHook)
registerDevHook()
""" % body
    os.makedirs(os.path.dirname(LUA_PATH), exist_ok=True)
    with open(LUA_PATH, "w", encoding="utf-8") as handle:
        handle.write(text)


def emit_mesh(pieces, tris, origin, gx, gy, fz):
    mesh_name = "loading_hopper_%d" % len(pieces)
    export_mesh(mesh_name, tris, origin)
    pieces.append(
        {
            "ix": len(pieces),
            "gx": gx,
            "gy": gy,
            "fz": fz,
            "mesh": mesh_name,
            "solid": False,
            "floor": False,
            "stair": None,
            "invisible": False,
        }
    )
    print("mesh", pieces[-1]["ix"], (gx, gy, fz), "tris", len(tris))


def emit_collision(pieces, by_square, gx, gy, fz):
    key = (gx, gy, fz)
    piece = by_square.get(key)
    if piece is not None:
        return piece
    piece = {
        "ix": len(pieces),
        "gx": gx,
        "gy": gy,
        "fz": fz,
        "mesh": None,
        "solid": False,
        "floor": False,
        "stair": None,
        "invisible": True,
    }
    pieces.append(piece)
    by_square[key] = piece
    print("collision", piece["ix"], key)
    return piece


def main():
    src = bpy.data.objects["loading_hopper"]
    tris = read_tris(src)
    print("source tris", len(tris))
    if RIM_VISUAL_LEVEL < 0:
        raise RuntimeError("rim visual level is negative")

    os.makedirs(MESH_DIR, exist_ok=True)
    for name in os.listdir(MESH_DIR):
        if name.startswith("loading_hopper") and name.endswith(".fbx"):
            os.remove(os.path.join(MESH_DIR, name))

    pieces = []
    cells = mesh_cells(tris)
    # Ground anchor at the bay center so stamp dz matches world floors when placed on z=0.
    # The truck bay often has no mesh there; use an invisible tile in that case.
    ground_center = [c for c in cells if c[0] == 0 and c[1] == 0 and c[2] == 0]
    if ground_center:
        gx, gy, stamp_fz, band, cell = ground_center[0]
        cells.remove(ground_center[0])
        emit_mesh(
            pieces,
            cell,
            Vector((gx + 0.5, gy + 0.5, 0.0)),
            -gx - 1,
            gy,
            0,
        )
    else:
        # Tiny stub so the placeable brush has a spriteModel; truck bay has no ground mesh.
        stub = [
            (
                (Vector((-0.05, -0.05, 0.01)), (0.0, 0.0)),
                (Vector((0.05, -0.05, 0.01)), (1.0, 0.0)),
                (Vector((0.0, 0.05, 0.01)), (0.5, 1.0)),
            )
        ]
        emit_mesh(pieces, stub, Vector((0.5, 0.5, 0.0)), -1, 0, 0)
        print("anchor", 0, (-1, 0, 0), "stub bay-center ground")

    # Per-floor meshes. Origin Z matches the stamp floor; verts keep absolute Z.
    # blender +X → world -X.
    for gx, gy, stamp_fz, band, cell in cells:
        emit_mesh(
            pieces,
            cell,
            Vector((gx + 0.5, gy + 0.5, stamp_fz * FLOOR_M)),
            -gx - 1,
            gy,
            stamp_fz,
        )

    by_square = {}
    for piece in pieces:
        key = (piece["gx"], piece["gy"], piece["fz"])
        if key not in by_square:
            by_square[key] = piece

    def tile_at(square):
        piece = by_square.get(square)
        if piece is None:
            piece = emit_collision(pieces, by_square, square[0], square[1], square[2])
        return piece

    # Upper deck walk surface: invisible solidfloor on the real deck level.
    for gx, gy, stamp_fz, band, cell in cells:
        if band == RIM_LEVEL and deck_cover(cell) >= 0.5:
            tile_at((-gx - 1, gy, RIM_LEVEL))["floor"] = True

    # The six legs. The center posts stand on the line between two rows, so both are solid.
    for x in (-HX, HX):
        for row in (int(math.floor(-HY)), int(math.floor(HY)), -1, 0):
            tile_at((world_col(x), row, 0))["solid"] = True

    if len(pieces) > 512:
        raise RuntimeError("tileset has %d tiles; the game allows 512" % len(pieces))

    write_tiles(pieces)
    write_scripts(pieces)
    write_lua(pieces)
    meshes = sum(1 for piece in pieces if piece["mesh"])
    solids = sum(1 for piece in pieces if piece["solid"])
    floors = sum(1 for piece in pieces if piece["floor"])
    stairs_n = sum(1 for piece in pieces if piece.get("stair"))
    invis = sum(1 for piece in pieces if piece.get("invisible"))
    print(
        "pieces",
        len(pieces),
        "meshes",
        meshes,
        "solid",
        solids,
        "floor",
        floors,
        "stair",
        stairs_n,
        "invisible",
        invis,
    )
    for piece in pieces:
        print(
            " ",
            piece["ix"],
            (piece["gx"], piece["gy"], piece["fz"]),
            "mesh" if piece["mesh"] else "-",
            "solid" if piece["solid"] else "",
            "floor" if piece["floor"] else "",
            piece.get("stair") or "",
            "inv" if piece.get("invisible") else "",
        )


main()
