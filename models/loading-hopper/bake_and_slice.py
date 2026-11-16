"""Import the authored OBJ, paint UV bands, export FBX, then run the tile slicer.

Run:
  blender --background --python bake_and_slice.py
"""

from __future__ import annotations

import array
import math
import os
import random
import runpy

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OBJ_PATH = os.path.join(HERE, "loading_hopper.obj")
PNG_PATH = os.path.join(HERE, "loading_hopper.png")
FBX_PATH = os.path.join(HERE, "loading_hopper.fbx")
# Unwrapped game tiles: floors_exterior_street_01_4 and
# floors_exterior_tilesandstone_01_4, iso shade removed. 128x128 RGB.
CONCRETE_A = os.path.join(HERE, "concrete_footer_a.raw")
CONCRETE_B = os.path.join(HERE, "concrete_footer_b.raw")
CONCRETE_TILE = 128
TEX_DST = (
    "/Users/jamesrutledge/pz-modding/mods/DumpTruckGravelMod/"
    "Contents/mods/DumpTruckGravelMod/42.20/media/textures/IsoObject/loading_hopper.png"
)
SLICE = os.path.join(HERE, "slice_hopper.py")

# Band order and colors (name → painted strip).
# Blue is pushed bright so mid-height steel under the deck still reads blue in shadow.
BANDS = [
    ("concrete", (0.50, 0.47, 0.42)),
    ("blue", (0.42, 0.55, 0.68)),
    ("blue_dark", (0.22, 0.28, 0.34)),
    ("deck", (0.26, 0.25, 0.23)),
    ("galvanized", (0.58, 0.57, 0.53)),
    ("belt", (0.10, 0.10, 0.09)),
    ("equipment", (0.20, 0.19, 0.18)),
]


def clear_meshes():
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)


def import_obj():
    clear_meshes()
    bpy.ops.wm.obj_import(filepath=OBJ_PATH, up_axis="Z", forward_axis="Y")
    obj = bpy.context.selected_objects[0]
    obj.name = "loading_hopper"
    bpy.context.view_layer.objects.active = obj
    return obj


def material_band_index(slot_name: str) -> int:
    key = slot_name.split(".", 1)[0]
    for i, (name, _color) in enumerate(BANDS):
        if name == key:
            return i
    raise RuntimeError("unknown material slot %r" % slot_name)


def _frac(value):
    return value - math.floor(value)


def _band_v(band, t):
    """t 0..1 across one material strip, inset so neighboring strips do not bleed."""
    return (band + 0.12 + 0.76 * min(max(t, 0.0), 1.0)) / len(BANDS)


def remap_uvs(obj):
    """Cube-project at one UV unit per meter.

    A thin member maps its short side across the band, so the lit edge and the
    shadow edge sit on the beam. A plate tiles the same shading once per meter
    on both axes, so a wall is not one flat color.
    """
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=1.0, correct_aspect=False, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.verify()
    slot_names = [s.name for s in obj.material_slots]
    for face in bm.faces:
        name = slot_names[face.material_index]
        band = material_band_index(name)
        us = [loop[uvl].uv.x for loop in face.loops]
        vs = [loop[uvl].uv.y for loop in face.loops]
        umin, umax = min(us), max(us)
        vmin, vmax = min(vs), max(vs)
        span_u = umax - umin
        span_v = vmax - vmin
        thin = min(span_u, span_v) < 0.35
        long_u = span_u >= span_v
        concrete = name.split(".", 1)[0] == "concrete"
        for loop in face.loops:
            cu = loop[uvl].uv.x
            cv = loop[uvl].uv.y
            if concrete:
                # One game tile per meter. The long axis walks the 8 repeats
                # packed across the band. The short axis uses the band height.
                if span_u >= span_v:
                    along, across = cu, cv
                    along0, across0 = umin, vmin
                    across_span = span_v
                else:
                    along, across = cv, cu
                    along0, across0 = vmin, umin
                    across_span = span_u
                u = (along - along0) / 8.0
                across_tiles = across_span if across_span > 1.0 else 1.0
                t = 0.0 if across_tiles < 1e-6 else (across - across0) / across_tiles
                loop[uvl].uv.x = min(max(u, 0.0), 0.999)
                loop[uvl].uv.y = _band_v(band, t)
                continue
            if thin and long_u:
                u = _frac(cu)
                t = 0.5 if span_v < 1e-6 else (cv - vmin) / span_v
            elif thin:
                u = _frac(cv)
                t = 0.5 if span_u < 1e-6 else (cu - umin) / span_u
            else:
                u = _frac(cu)
                t = 0.18 + 0.64 * _frac(cv)
            loop[uvl].uv.x = u
            loop[uvl].uv.y = _band_v(band, t)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    print("uv remapped", len(BANDS), "bands")


def _load_raw(path):
    data = open(path, "rb").read()
    need = CONCRETE_TILE * CONCRETE_TILE * 3
    if len(data) != need:
        raise RuntimeError("%s is %s bytes, expected %s" % (path, len(data), need))
    return data


def _paint_concrete_band(buf, w, h):
    """Stamp sampled game concrete into band 0. Eight tiles across, one tile tall."""
    sources = (_load_raw(CONCRETE_A), _load_raw(CONCRETE_B))
    band_h = h // len(BANDS)
    y0 = int(band_h * 0.12)
    y1 = int(band_h * 0.88)
    usable = max(1, y1 - y0)
    tile = CONCRETE_TILE
    for y in range(band_h):
        yy = min(max(y, y0), y1 - 1)
        sy = min(tile - 1, int((yy - y0) / usable * tile))
        for x in range(w):
            pos = x * 8.0 / w
            tile_i = min(7, int(pos))
            sx = min(tile - 1, int((pos - tile_i) * tile))
            src = sources[tile_i & 1]
            si = (sy * tile + sx) * 3
            i = (y * w + x) * 4
            buf[i] = src[si] / 255.0
            buf[i + 1] = src[si + 1] / 255.0
            buf[i + 2] = src[si + 2] / 255.0
            buf[i + 3] = 1.0


def paint_png():
    w = h = 1024
    rng = random.Random(7)

    def grid(n):
        return [rng.random() for _ in range(n * n)]

    def sample(g, n, x, y):
        x0 = int(x) % n
        y0 = int(y) % n
        x1 = (x0 + 1) % n
        y1 = (y0 + 1) % n
        fx, fy = x - int(x), y - int(y)

        def at(ix, iy):
            return g[iy * n + ix]

        return (
            at(x0, y0) * (1 - fx) * (1 - fy)
            + at(x1, y0) * fx * (1 - fy)
            + at(x0, y1) * (1 - fx) * fy
            + at(x1, y1) * fx * fy
        )

    n1 = grid(64)
    buf = array.array("f", [0.0]) * (w * h * 4)
    band_h = h // len(BANDS)
    beam_names = {"blue", "blue_dark", "galvanized"}
    for y in range(h):
        b = min(len(BANDS) - 1, y // band_h)
        name, (cr, cg, cb) = BANDS[b]
        ny = (y - b * band_h) / band_h
        for x in range(w):
            f = sample(n1, 64, x / 4.0, y / 4.0)
            shade = 0.98 + 0.04 * f
            if name in beam_names:
                lit = max(0.0, 1.0 - ny / 0.42)
                shadow = max(0.0, (ny - 0.58) / 0.42)
                shade *= 1.0 + 0.22 * lit - 0.18 * shadow
            shade = min(max(shade, 0.0), 2.0)
            i = (y * w + x) * 4
            buf[i] = min(cr * shade, 1.0)
            buf[i + 1] = min(cg * shade, 1.0)
            buf[i + 2] = min(cb * shade, 1.0)
            buf[i + 3] = 1.0

    _paint_concrete_band(buf, w, h)

    img = bpy.data.images.get("loading_hopper_tex")
    if img is None or img.size[0] != w:
        if img:
            bpy.data.images.remove(img)
        img = bpy.data.images.new("loading_hopper_tex", w, h, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(buf)
    img.update()
    img.filepath_raw = PNG_PATH
    img.file_format = "PNG"
    img.save()
    return img


def assign_material(obj, img):
    mat = bpy.data.materials.get("hopper_diffuse")
    if mat is None:
        mat = bpy.data.materials.new("hopper_diffuse")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.92
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.extension = "REPEAT"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    for i, _slot in enumerate(obj.material_slots):
        obj.material_slots[i].material = mat


def export_fbx(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=FBX_PATH,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=False,
        add_leaf_bones=False,
        mesh_smooth_type="FACE",
        use_triangles=True,
        path_mode="AUTO",
        embed_textures=False,
    )
    print("fbx", os.path.getsize(FBX_PATH))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obj = import_obj()
    print("slots", [s.name.split(".")[0] for s in obj.material_slots])
    remap_uvs(obj)
    img = paint_png()
    assign_material(obj, img)
    export_fbx(obj)
    os.makedirs(os.path.dirname(TEX_DST), exist_ok=True)
    import shutil

    shutil.copy2(PNG_PATH, TEX_DST)
    print("texture", TEX_DST)
    # Slice the textured object already in the scene.
    runpy.run_path(SLICE, run_name="__main__")


if __name__ == "__main__":
    main()
