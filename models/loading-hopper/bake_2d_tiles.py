"""Render per-cell PZ sprites from loading_hopper.fbx for the 2D rebuild.

One canvas camera (pz_iso IsoUtils projection, world origin on an integer
pixel) renders the uncut hopper twice:

  full   whole hopper
  under  surfaces at or above pz_iso.DECK_LAYER_Z are transparent to the
         camera (shader cut on the uncut mesh) and still cast shadows

Each render has a matching float EXR of world position. Every pixel is owned
by the cell that contains its surface point (pz_iso.point_owner). Deck sprites
(fz 3) are crops of `full`; lower sprites (fz 0..2) are crops of the merged
lower image (`full` where it shows a lower surface, `under` behind the deck).
Each sprite mask is dilated by pz_iso.MASK_PAD_PX into identical pixels of
its own source image.

Run (Blender needs the GPU, so run outside the sandbox):
  blender --background --python bake_2d_tiles.py
  blender --background --python bake_2d_tiles.py -- --fixture
  blender --background --python bake_2d_tiles.py -- --dig2
  blender --background --python bake_2d_tiles.py -- --dig3
  blender --background --python bake_2d_tiles.py -- --footing
"""

from __future__ import annotations

import json
import math
import os
import sys

import bpy
import numpy as np
import OpenImageIO as oiio
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import pz_iso  # noqa: E402

FBX_PATH = os.path.join(HERE, "loading_hopper.fbx")
OUT_DIR = os.path.join(HERE, "2d_tiles")
RENDER_DIR = os.path.join(OUT_DIR, "_render")
MANIFEST = os.path.join(OUT_DIR, "manifest.txt")
LAYOUT_JSON = os.path.join(RENDER_DIR, "layout.json")
RGB_SAMPLES = 16
FRINGE_PX = 2
POS_MARGIN_M = 0.5
KIND_CODES = ("object", "floor", "upper")


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_hopper():
    bpy.ops.import_scene.fbx(filepath=FBX_PATH)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    if not objs:
        raise RuntimeError("no mesh in fbx")
    obj = objs[0]
    obj.name = "loading_hopper"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=1e-4)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def add_sun():
    light_data = bpy.data.lights.new(name="sun", type="SUN")
    light_data.energy = 3.2
    light = bpy.data.objects.new("sun", light_data)
    bpy.context.scene.collection.objects.link(light)
    light.rotation_euler = (math.radians(50), math.radians(15), math.radians(45))


def setup_world():
    world = bpy.data.worlds.new("world")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.55, 0.58, 1.0)
    bg.inputs[1].default_value = 1.0


def world_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs = [v.x for v in corners]
    ys = [v.y for v in corners]
    zs = [v.z for v in corners]
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def all_cells(obj):
    minx, maxx, miny, maxy, _minz, maxz = world_bounds(obj)
    gx0 = int(math.floor(minx))
    gx1 = int(math.floor(maxx - 1e-6))
    gy0 = int(math.floor(miny))
    gy1 = int(math.floor(maxy - 1e-6))
    fz1 = int(math.floor((maxz - 1e-6) / pz_iso.FLOOR_M))
    cells = []
    for fz in range(0, fz1 + 1):
        for gx in range(gx0 - 1, gx1 + 2):
            for gy in range(gy0 - 1, gy1 + 2):
                cells.append((gx, gy, fz))
    return cells


def setup_canvas_camera(x0: int, y0: int, w: int, h: int):
    """Ortho camera that maps world (0,0,0) to canvas pixel corner (x0, y0)."""
    for obj in list(bpy.data.objects):
        if obj.type == "CAMERA":
            bpy.data.objects.remove(obj, do_unlink=True)
    right, up, forward = (Vector(v) for v in pz_iso.camera_basis_world())
    px_per_m = pz_iso.TILE_W / pz_iso.ORTHO_SCALE

    cam_data = bpy.data.cameras.new("pz_canvas_cam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = w / px_per_m
    cam_data.clip_start = 1.0
    cam_data.clip_end = 200.0
    cam = bpy.data.objects.new("pz_canvas_cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.matrix_world = Matrix(
        (
            (right.x, up.x, -forward.x, 0.0),
            (right.y, up.y, -forward.y, 0.0),
            (right.z, up.z, -forward.z, 0.0),
            (0.0, 0.0, 0.0, 1.0),
        )
    )
    a = (w * 0.5 - x0) / px_per_m
    b = (y0 - h * 0.5) / px_per_m
    cam.location = right * a + up * b - forward * 60.0
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    return cam


def above_deck_layer(nodes, links):
    """Shader factor: 1 where world z >= DECK_LAYER_Z."""
    geo = nodes.new("ShaderNodeNewGeometry")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    below = nodes.new("ShaderNodeMath")
    below.operation = "LESS_THAN"
    below.inputs[1].default_value = pz_iso.DECK_LAYER_Z
    above = nodes.new("ShaderNodeMath")
    above.operation = "SUBTRACT"
    above.inputs[0].default_value = 1.0
    links.new(geo.outputs["Position"], sep.inputs[0])
    links.new(sep.outputs["Z"], below.inputs[0])
    links.new(below.outputs[0], above.inputs[1])
    return above.outputs[0]


def surface_output(mat):
    return next(
        n for n in mat.node_tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output
    )


def hide_deck_layer(mat):
    """Deck level transparent to the camera; shadows stay opaque.

    The mesh stays uncut, so shading below the deck matches the full render.
    """
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    out = surface_output(mat)
    shader = out.inputs["Surface"].links[0].from_socket
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(above_deck_layer(nodes, links), mix.inputs[0])
    links.new(shader, mix.inputs[1])
    links.new(clear.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])
    mat.use_transparent_shadow = False


def position_material(bmin, size, name: str):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    geo = nodes.new("ShaderNodeNewGeometry")
    sub = nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = bmin
    div = nodes.new("ShaderNodeVectorMath")
    div.operation = "DIVIDE"
    div.inputs[1].default_value = size
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(geo.outputs["Position"], sub.inputs[0])
    links.new(sub.outputs[0], div.inputs[0])
    links.new(div.outputs[0], emit.inputs["Color"])
    links.new(emit.outputs[0], out.inputs["Surface"])
    return mat


class RenderSettings:
    """RGB look as the bake has always used; position pass overrides it."""

    def __init__(self, scene):
        self.scene = scene
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.film_transparent = True
        self.filter_size = scene.render.filter_size
        self.view_transform = scene.view_settings.view_transform
        self.look = scene.view_settings.look

    def rgb(self, path: str):
        scene = self.scene
        scene.eevee.taa_render_samples = RGB_SAMPLES
        scene.render.filter_size = self.filter_size
        scene.view_settings.view_transform = self.view_transform
        scene.view_settings.look = self.look
        bpy.context.view_layer.material_override = None
        settings = scene.render.image_settings
        settings.file_format = "PNG"
        settings.color_mode = "RGBA"
        settings.color_depth = "8"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    def position(self, path: str, mat):
        scene = self.scene
        scene.eevee.taa_render_samples = 1
        scene.render.filter_size = 0.0
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
        bpy.context.view_layer.material_override = mat
        settings = scene.render.image_settings
        settings.file_format = "OPEN_EXR"
        settings.color_mode = "RGBA"
        settings.color_depth = "32"
        settings.exr_codec = "ZIP"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        bpy.context.view_layer.material_override = None


def unassociated_spec():
    spec = oiio.ImageSpec()
    spec.attribute("oiio:UnassociatedAlpha", 1)
    return spec


def read_png(path: str) -> np.ndarray:
    inp = oiio.ImageInput.open(path, unassociated_spec())
    if inp is None:
        raise RuntimeError("cannot open %s: %s" % (path, oiio.geterror()))
    spec = inp.spec()
    arr = inp.read_image(0, 0, 0, 4, "uint8")
    inp.close()
    return np.ascontiguousarray(arr.reshape(spec.height, spec.width, 4))


def write_png(path: str, arr: np.ndarray):
    h, w, _c = arr.shape
    spec = oiio.ImageSpec(w, h, 4, "uint8")
    spec.attribute("oiio:UnassociatedAlpha", 1)
    out = oiio.ImageOutput.create(path)
    if out is None or not out.open(path, spec):
        raise RuntimeError("cannot write %s: %s" % (path, oiio.geterror()))
    out.write_image(np.ascontiguousarray(arr, dtype=np.uint8))
    out.close()


def read_exr(path: str) -> np.ndarray:
    inp = oiio.ImageInput.open(path)
    if inp is None:
        raise RuntimeError("cannot open %s: %s" % (path, oiio.geterror()))
    spec = inp.spec()
    arr = inp.read_image(0, 0, 0, 4, "float")
    inp.close()
    return np.ascontiguousarray(arr.reshape(spec.height, spec.width, 4))


def decode_world(pos: np.ndarray, bmin, size):
    valid = pos[..., 3] > 0.5
    world = np.asarray(bmin, dtype=np.float64) + pos[..., :3].astype(np.float64) * np.asarray(
        size, dtype=np.float64
    )
    return world, valid


class OwnerTable:
    """Integer ids for (gx, gy, fz, kind) sprite owners."""

    def __init__(self):
        self.keys = []
        self.index = {}

    def id_for(self, key) -> int:
        got = self.index.get(key)
        if got is None:
            got = len(self.keys)
            self.keys.append(key)
            self.index[key] = got
        return got

    def column(self, field: int) -> np.ndarray:
        return np.array([k[field] for k in self.keys], dtype=np.int64)


def owner_map(world, valid, table: OwnerTable) -> np.ndarray:
    own = np.full(valid.shape, -1, dtype=np.int64)
    ys, xs = np.nonzero(valid)
    pts = world[ys, xs]
    for j, i, (x, y, z) in zip(ys, xs, pts):
        own[j, i] = table.id_for(pz_iso.point_owner(float(x), float(y), float(z)))
    return own


def disk_offsets(radius: int):
    offs = [
        (dx, dy)
        for dy in range(-radius, radius + 1)
        for dx in range(-radius, radius + 1)
        if 0 < dx * dx + dy * dy <= radius * radius
    ]
    offs.sort(key=lambda o: (o[0] * o[0] + o[1] * o[1], o[1], o[0]))
    return offs


def shifted(arr: np.ndarray, dx: int, dy: int, fill):
    """out[j, i] = arr[j + dy, i + dx], fill outside."""
    h, w = arr.shape[:2]
    out = np.full_like(arr, fill)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    if ys0 < ys1 and xs0 < xs1:
        out[ys0:ys1, xs0:xs1] = arr[ys0 + dy : ys1 + dy, xs0 + dx : xs1 + dx]
    return out


def assign_fringe(own: np.ndarray, rgba: np.ndarray):
    """Alpha-only pixels take the owner of the nearest positioned pixel."""
    need = (rgba[..., 3] > 0) & (own < 0)
    out = own.copy()
    filled = 0
    for dx, dy in disk_offsets(FRINGE_PX):
        nb = shifted(own, dx, dy, -1)
        take = need & (out < 0) & (nb >= 0)
        out[take] = nb[take]
        filled += int(np.count_nonzero(take))
    left = int(np.count_nonzero(need & (out < 0)))
    return out, filled, left


RELOCATE = ((1, 1), (1, 0), (0, 1), (-1, -1), (-1, 0), (0, -1))


def relocate_out_of_rect(own: np.ndarray, table: OwnerTable, x0: int, y0: int):
    """Pixels outside their owner's sprite rect move to the neighbour cell whose rect holds them."""
    h, w = own.shape
    gx = table.column(0)
    gy = table.column(1)
    fz = table.column(2)
    ox = 64 * (gx - gy)
    oy = 32 * (gx + gy) - 192 * fz
    left_tab = x0 + ox - pz_iso.TILE_W // 2
    top_tab = y0 + oy - int(pz_iso.FOOTING * pz_iso.TILE_H)
    jj, ii = np.mgrid[0:h, 0:w]
    has = own >= 0
    safe = np.where(has, own, 0)
    left = left_tab[safe]
    top = top_tab[safe]
    inside = (ii >= left) & (ii < left + pz_iso.TILE_W) & (jj >= top) & (jj < top + pz_iso.TILE_H)
    bad = has & ~inside
    moved = 0
    dropped = 0
    for j, i in zip(*np.nonzero(bad)):
        cgx, cgy, cfz, kind = table.keys[own[j, i]]
        target = -1
        for dx, dy in RELOCATE:
            ngx, ngy = cgx + dx, cgy + dy
            l, t = pz_iso.sprite_rect(ngx, ngy, cfz, x0, y0)
            if l <= i < l + pz_iso.TILE_W and t <= j < t + pz_iso.TILE_H:
                nkind = "upper" if kind == "floor" else kind
                target = table.id_for((ngx, ngy, cfz, nkind))
                break
        if target < 0:
            own[j, i] = -1
            dropped += 1
        else:
            own[j, i] = target
            moved += 1
    return moved, dropped


def resolve_owners(rgba, pos, bmin, size, table, x0, y0, label):
    world, valid = decode_world(pos, bmin, size)
    own = owner_map(world, valid, table)
    own, filled, left = assign_fringe(own, rgba)
    moved, dropped = relocate_out_of_rect(own, table, x0, y0)
    print(
        "owners",
        label,
        "positioned",
        int(np.count_nonzero(valid)),
        "fringe_filled",
        filled,
        "fringe_unowned",
        left,
        "relocated",
        moved,
        "dropped",
        dropped,
    )
    return own, world, valid


def merge_layers(full, full_own, under, under_own, table):
    fz_tab = table.column(2)
    f_on = full[..., 3] > 0
    f_fz = np.where(full_own >= 0, fz_tab[np.maximum(full_own, 0)], -1)
    f_low = f_on & (f_fz >= 0) & (f_fz <= 2)
    f_deck = f_on & (f_fz == 3)
    u_ok = (under[..., 3] > 0) & (under_own >= 0)
    take_u = f_deck & u_ok

    lower = np.zeros_like(full)
    lower_own = np.full(full_own.shape, -1, dtype=np.int64)
    lower[f_low] = full[f_low]
    lower_own[f_low] = full_own[f_low]
    lower[take_u] = under[take_u]
    lower_own[take_u] = under_own[take_u]

    deck = np.zeros_like(full)
    deck_own = np.full(full_own.shape, -1, dtype=np.int64)
    deck[f_deck] = full[f_deck]
    deck_own[f_deck] = full_own[f_deck]
    unowned = int(np.count_nonzero(f_on & (f_fz < 0)))
    print(
        "layers lower_from_full",
        int(np.count_nonzero(f_low)),
        "lower_from_under",
        int(np.count_nonzero(take_u)),
        "deck",
        int(np.count_nonzero(f_deck)),
        "full_unowned",
        unowned,
    )
    return lower, lower_own, deck, deck_own


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    out = mask.copy()
    for dx, dy in disk_offsets(radius):
        out |= shifted(mask, dx, dy, False)
    return out


def crop_sprite(src, own, owner_id, left, top):
    tw, th = pz_iso.TILE_W, pz_iso.TILE_H
    win = src[top : top + th, left : left + tw]
    win_own = own[top : top + th, left : left + tw]
    mask = win_own == owner_id
    if not np.any(mask):
        return None, 0
    grown = dilate(mask, pz_iso.MASK_PAD_PX) & (win[..., 3] > 0)
    sprite = win.copy()
    sprite[..., 3] = np.where(grown, sprite[..., 3], 0)
    return sprite, int(np.count_nonzero(mask))


def parse_args(argv):
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    for flag, cells in (
        ("--footing", pz_iso.FOOTING_SEAM_CELLS),
        ("--dig3", pz_iso.DIG3_CELLS),
        ("--dig2", pz_iso.DIG2_CELLS),
        ("--fixture", pz_iso.FIXTURE_CELLS),
    ):
        if flag in args:
            return flag[2:], set(cells)
    return "full", None


def render_pair(settings, label, pos_mat):
    rgb_path = os.path.join(RENDER_DIR, label + ".png")
    pos_path = os.path.join(RENDER_DIR, label + "_pos.exr")
    settings.rgb(rgb_path)
    settings.position(pos_path, pos_mat)
    return read_png(rgb_path), read_exr(pos_path)


def main():
    mode, only = parse_args(sys.argv)
    clear_scene()
    src = import_hopper()
    # Ambient-only: no sun, so no cast shadows or fixed sun-facing shading are baked in.
    # Engine per-square lighting supplies time of day.
    setup_world()
    scene = bpy.context.scene
    settings = RenderSettings(scene)

    minx, maxx, miny, maxy, minz, maxz = world_bounds(src)
    bmin = (minx - POS_MARGIN_M, miny - POS_MARGIN_M, minz - POS_MARGIN_M)
    size = (
        maxx - minx + 2 * POS_MARGIN_M,
        maxy - miny + 2 * POS_MARGIN_M,
        maxz - minz + 2 * POS_MARGIN_M,
    )
    cells = all_cells(src)
    x0, y0, w, h = pz_iso.canvas_layout(cells)
    print(
        "hopper bounds",
        tuple(round(v, 3) for v in (minx, maxx, miny, maxy, minz, maxz)),
        "canvas",
        w,
        h,
        "origin",
        x0,
        y0,
        "deck_layer_z",
        pz_iso.DECK_LAYER_Z,
        "mode",
        mode,
    )
    os.makedirs(RENDER_DIR, exist_ok=True)
    for name in os.listdir(OUT_DIR):
        if name.endswith(".png") or name == "manifest.txt":
            os.remove(os.path.join(OUT_DIR, name))

    setup_canvas_camera(x0, y0, w, h)

    full, full_pos = render_pair(settings, "full", position_material(bmin, size, "pos_full"))

    for mat in src.data.materials:
        hide_deck_layer(mat)
    under_pos_mat = position_material(bmin, size, "pos_under")
    hide_deck_layer(under_pos_mat)
    under, under_pos = render_pair(settings, "under", under_pos_mat)

    table = OwnerTable()
    full_own, _fw, _fv = resolve_owners(full, full_pos, bmin, size, table, x0, y0, "full")
    under_own, _uw, _uv = resolve_owners(under, under_pos, bmin, size, table, x0, y0, "under")
    lower, lower_own, deck, deck_own = merge_layers(full, full_own, under, under_own, table)

    write_png(os.path.join(RENDER_DIR, "lower.png"), lower)
    write_png(os.path.join(RENDER_DIR, "deck.png"), deck)
    np.save(os.path.join(RENDER_DIR, "full_own.npy"), full_own.astype(np.int32))
    np.save(os.path.join(RENDER_DIR, "under_own.npy"), under_own.astype(np.int32))
    np.save(os.path.join(RENDER_DIR, "lower_own.npy"), lower_own.astype(np.int32))
    np.save(os.path.join(RENDER_DIR, "deck_own.npy"), deck_own.astype(np.int32))
    with open(LAYOUT_JSON, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "x0": x0,
                "y0": y0,
                "w": w,
                "h": h,
                "bmin": bmin,
                "size": size,
                "owners": [list(k) for k in table.keys],
            },
            handle,
        )

    wrote = []
    for owner_id, (gx, gy, fz, kind) in enumerate(table.keys):
        if only is not None and (gx, gy, fz) not in only:
            continue
        src_img, src_own = (deck, deck_own) if fz == 3 else (lower, lower_own)
        left, top = pz_iso.sprite_rect(gx, gy, fz, x0, y0)
        sprite, owned = crop_sprite(src_img, src_own, owner_id, left, top)
        if sprite is None:
            continue
        name = pz_iso.sprite_name(gx, gy, fz, kind)
        write_png(os.path.join(OUT_DIR, name), sprite)
        wrote.append((gx, gy, fz, pz_iso.manifest_kind(kind), name, owned))
        print("wrote", name, kind, "owned", owned)

    wrote.sort(key=lambda r: (r[2], r[1], r[0], r[4]))
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        handle.write("# gx gy fz kind filename\n")
        for gx, gy, fz, kind, name, _owned in wrote:
            handle.write("%d %d %d %s %s\n" % (gx, gy, fz, kind, name))
    small = sum(1 for r in wrote if r[5] < 64)
    print("bake_2d_tiles done", len(wrote), "sprites", "under_64_owned", small, "->", OUT_DIR)


if __name__ == "__main__":
    main()
