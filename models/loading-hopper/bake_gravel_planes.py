"""Bake thin gravel planes inside the hopper bin as per-cell 128x256 sprites.

Renders a flat gravel disc inside the bin mesh so the rim and near walls cut
the silhouette. Each plane height becomes a stock band; shimmer frames shift
the gravel UV with radial falloff so motion is strongest toward the outlet.

Run (Blender needs the GPU; outside the sandbox):
  blender --background --python bake_gravel_planes.py -- --planes hi --frames 1
  blender --background --python bake_gravel_planes.py -- --planes all --frames 3
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
GRAVEL_TEX = os.path.normpath(
    os.path.join(
        HERE,
        "../../Contents/mods/DumpTruckGravelMod/42.20/media/textures/Vehicles/vehicle_FE6Dump_gravel.png",
    )
)
OUT_DIR = os.path.join(HERE, "gravel_tiles")
RENDER_DIR = os.path.join(OUT_DIR, "_render")
MANIFEST = os.path.join(OUT_DIR, "manifest.txt")
LAYOUT_JSON = os.path.join(RENDER_DIR, "layout.json")

# Bin / funnel outer shell (generate_hopper.py), then plate + inset for cavity.
HOPPER_W = 2.95
HOPPER_D = 3.35
BIN_BOTTOM = 6.05
FUNNEL_BOTTOM = 4.30
OUTLET_W = 0.82
OUTLET_D = 0.82
FUNNEL_TOP_W = OUTLET_W + 0.08
FUNNEL_TOP_D = OUTLET_D + 0.08
PLATE = 0.07
CAVITY_INSET = 0.04

PLANE_Z = {
    "hi": 7.20,
    "mid": 6.70,
    "lo": 6.20,
    # Inside the funnel, just below the straight bin — nearly empty.
    "vlo": 5.65,
}


def cavity_size_at(z: float) -> tuple[float, float]:
    """Inner gravel disc size at height z — shrinks with the funnel so it stays inside the steel."""
    if z >= BIN_BOTTOM:
        outer_w, outer_d = HOPPER_W, HOPPER_D
    elif z <= FUNNEL_BOTTOM:
        outer_w, outer_d = FUNNEL_TOP_W, FUNNEL_TOP_D
    else:
        t = (BIN_BOTTOM - z) / (BIN_BOTTOM - FUNNEL_BOTTOM)
        outer_w = HOPPER_W + t * (FUNNEL_TOP_W - HOPPER_W)
        outer_d = HOPPER_D + t * (FUNNEL_TOP_D - HOPPER_D)
    return (
        max(0.2, outer_w - 2.0 * PLATE - CAVITY_INSET),
        max(0.2, outer_d - 2.0 * PLATE - CAVITY_INSET),
    )
# Cells that can own gravel pixels at fz=2 (mouth + ring).
RING_XY = [(gx, gy) for gx in range(-2, 2) for gy in range(-2, 2)]

RGB_SAMPLES = 24
POS_MARGIN_M = 0.5
PLANE_Z_EPS = 0.08
# UV shift (texture units) at the outlet for shimmer frames 1 and 2.
# Radial falloff in the shader keeps the rim nearly still.
SHIMMER_UV = (
    (0.0, 0.0),
    (0.07, -0.045),
    (-0.055, 0.06),
)


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


def setup_canvas_camera(x0: int, y0: int, w: int, h: int):
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


def gravel_material(uv_shift=(0.0, 0.0), name="gravel_mat", cavity_w=2.77, cavity_d=3.17):
    """Cool gray stone with UV shift strongest toward the outlet (world origin)."""
    if not os.path.isfile(GRAVEL_TEX):
        raise RuntimeError("missing gravel texture %s" % GRAVEL_TEX)
    img = bpy.data.images.load(GRAVEL_TEX)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    # Radial weight: 1 at XY origin (outlet), 0 at cavity rim.
    geo = nodes.new("ShaderNodeNewGeometry")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Position"], sep.inputs[0])
    # length(xy) / half_diag
    combine = nodes.new("ShaderNodeCombineXYZ")
    links.new(sep.outputs["X"], combine.inputs["X"])
    links.new(sep.outputs["Y"], combine.inputs["Y"])
    length = nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    links.new(combine.outputs[0], length.inputs[0])
    half_diag = 0.5 * math.sqrt(cavity_w * cavity_w + cavity_d * cavity_d)
    div = nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    div.inputs[1].default_value = max(half_diag, 1e-3)
    links.new(length.outputs["Value"], div.inputs[0])
    one_minus = nodes.new("ShaderNodeMath")
    one_minus.operation = "SUBTRACT"
    one_minus.inputs[0].default_value = 1.0
    links.new(div.outputs[0], one_minus.inputs[1])
    clamp = nodes.new("ShaderNodeClamp")
    clamp.inputs["Min"].default_value = 0.0
    clamp.inputs["Max"].default_value = 1.0
    links.new(one_minus.outputs[0], clamp.inputs["Value"])
    # Square falloff so the rim is almost still.
    power = nodes.new("ShaderNodeMath")
    power.operation = "POWER"
    power.inputs[1].default_value = 2.0
    links.new(clamp.outputs[0], power.inputs[0])

    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (3.2, 3.2, 1.0)
    # Base UV offset * radial weight.
    sx, sy = uv_shift
    mul_x = nodes.new("ShaderNodeMath")
    mul_x.operation = "MULTIPLY"
    mul_x.inputs[0].default_value = sx
    links.new(power.outputs[0], mul_x.inputs[1])
    mul_y = nodes.new("ShaderNodeMath")
    mul_y.operation = "MULTIPLY"
    mul_y.inputs[0].default_value = sy
    links.new(power.outputs[0], mul_y.inputs[1])
    combine_off = nodes.new("ShaderNodeCombineXYZ")
    links.new(mul_x.outputs[0], combine_off.inputs["X"])
    links.new(mul_y.outputs[0], combine_off.inputs["Y"])
    links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])
    links.new(combine_off.outputs[0], mapping.inputs["Location"])

    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    links.new(mapping.outputs["Vector"], tex.inputs["Vector"])

    # Contrast + cool gray so ForceAmbient still reads as speckled stone.
    bright = nodes.new("ShaderNodeBrightContrast")
    bright.inputs["Bright"].default_value = 0.08
    bright.inputs["Contrast"].default_value = 0.45
    links.new(tex.outputs["Color"], bright.inputs["Color"])
    rgb = nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (0.82, 0.84, 0.88, 1.0)
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs["Fac"].default_value = 0.35
    links.new(bright.outputs["Color"], mix.inputs["Color1"])
    links.new(rgb.outputs[0], mix.inputs["Color2"])

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.92
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.08
    links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def add_gravel_plane(z: float, mat, cavity_w: float, cavity_d: float):
    """Thin disc matching the cavity at this height, centred on the outlet."""
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.0, z))
    plane = bpy.context.active_object
    plane.name = "gravel_plane"
    plane.scale = (cavity_w, cavity_d, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if plane.data.materials:
        plane.data.materials[0] = mat
    else:
        plane.data.materials.append(mat)
    return plane


class RenderSettings:
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
    h, w = arr.shape[:2]
    out = np.full_like(arr, fill)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    if ys0 < ys1 and xs0 < xs1:
        out[ys0:ys1, xs0:xs1] = arr[ys0 + dy : ys1 + dy, xs0 + dx : xs1 + dx]
    return out


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
    # Hard alpha for object sprites.
    sprite[..., 3] = np.where(sprite[..., 3] >= 128, 255, 0)
    return sprite, int(np.count_nonzero(mask))


def parse_args(argv):
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    planes = ["hi", "mid", "lo", "vlo"]
    frames = 3
    if "--planes" in args:
        i = args.index("--planes")
        val = args[i + 1] if i + 1 < len(args) else "all"
        if val == "all":
            planes = ["hi", "mid", "lo", "vlo"]
        else:
            planes = [p.strip() for p in val.split(",") if p.strip() in PLANE_Z]
    if "--frames" in args:
        i = args.index("--frames")
        frames = max(1, min(3, int(args[i + 1])))
    return planes, frames


def gravel_owner_map(world, valid, plane_z: float, rgba: np.ndarray) -> np.ndarray:
    """Owner id per pixel for gravel surfaces that won the depth test."""
    own = np.full(valid.shape, -1, dtype=np.int64)
    ring_index = {(gx, gy): i for i, (gx, gy) in enumerate(RING_XY)}
    ys, xs = np.nonzero(valid & (rgba[..., 3] > 0))
    pts = world[ys, xs]
    for j, i, (x, y, z) in zip(ys, xs, pts):
        if abs(float(z) - plane_z) > PLANE_Z_EPS:
            continue
        gx = int(math.floor(float(x)))
        gy = int(math.floor(float(y)))
        oid = ring_index.get((gx, gy))
        if oid is None:
            continue
        own[j, i] = oid
    return own


def main():
    planes, n_frames = parse_args(sys.argv)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RENDER_DIR, exist_ok=True)
    for name in os.listdir(OUT_DIR):
        if name.endswith(".png") or name == "manifest.txt":
            os.remove(os.path.join(OUT_DIR, name))

    clear_scene()
    hopper = import_hopper()
    setup_world()
    scene = bpy.context.scene
    settings = RenderSettings(scene)

    minx, maxx, miny, maxy, minz, maxz = world_bounds(hopper)
    # Include plane Z in bounds for position encoding.
    minz = min(minz, min(PLANE_Z[p] for p in planes) - 0.2)
    maxz = max(maxz, max(PLANE_Z[p] for p in planes) + 0.2)
    bmin = (minx - POS_MARGIN_M, miny - POS_MARGIN_M, minz - POS_MARGIN_M)
    size = (
        maxx - minx + 2 * POS_MARGIN_M,
        maxy - miny + 2 * POS_MARGIN_M,
        maxz - minz + 2 * POS_MARGIN_M,
    )

    # Canvas covers the ring cells at fz=2.
    cells = [(gx, gy, 2) for gx, gy in RING_XY]
    x0, y0, w, h = pz_iso.canvas_layout(cells)
    print("gravel bake planes", planes, "frames", n_frames, "canvas", w, h)
    setup_canvas_camera(x0, y0, w, h)
    pos_mat = position_material(bmin, size, "pos_gravel")

    wrote = []
    for plane in planes:
        z = PLANE_Z[plane]
        cw, cd = cavity_size_at(z)
        print("plane", plane, "z", z, "cavity", round(cw, 3), round(cd, 3))
        for frame in range(n_frames):
            # Remove prior plane if any.
            old = bpy.data.objects.get("gravel_plane")
            if old is not None:
                bpy.data.objects.remove(old, do_unlink=True)

            mat = gravel_material(
                SHIMMER_UV[frame],
                name="gravel_%s_%d" % (plane, frame),
                cavity_w=cw,
                cavity_d=cd,
            )
            add_gravel_plane(z, mat, cw, cd)

            label = "%s_f%d" % (plane, frame)
            rgb_path = os.path.join(RENDER_DIR, label + ".png")
            pos_path = os.path.join(RENDER_DIR, label + "_pos.exr")
            settings.rgb(rgb_path)
            settings.position(pos_path, pos_mat)
            rgba = read_png(rgb_path)
            pos = read_exr(pos_path)
            world, valid = decode_world(pos, bmin, size)
            own = gravel_owner_map(world, valid, z, rgba)

            # Keep only gravel pixels in the RGB (steel already occluded them).
            gravel_rgba = rgba.copy()
            gravel_rgba[own < 0, 3] = 0

            write_png(os.path.join(RENDER_DIR, label + "_gravel.png"), gravel_rgba)
            np.save(os.path.join(RENDER_DIR, label + "_own.npy"), own.astype(np.int32))

            for oid, (gx, gy) in enumerate(RING_XY):
                left, top = pz_iso.sprite_rect(gx, gy, 2, x0, y0)
                sprite, owned = crop_sprite(gravel_rgba, own, oid, left, top)
                if sprite is None or owned < 8:
                    continue
                name = "hopper_gravel_%s_%d_%d_%d.png" % (plane, frame, gx, gy)
                # Encode plane/frame/gx/gy in a stable relative name; pack renumbers.
                write_png(os.path.join(OUT_DIR, name), sprite)
                wrote.append((plane, frame, gx, gy, 2, name, owned))
                print("wrote", name, "owned", owned)

    wrote.sort(key=lambda r: ({"hi": 0, "mid": 1, "lo": 2, "vlo": 3}[r[0]], r[1], r[3], r[2]))
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        handle.write("# plane frame gx gy fz filename\n")
        for plane, frame, gx, gy, fz, name, _owned in wrote:
            handle.write("%s %d %d %d %d %s\n" % (plane, frame, gx, gy, fz, name))
    with open(LAYOUT_JSON, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "x0": x0,
                "y0": y0,
                "w": w,
                "h": h,
                "bmin": bmin,
                "size": size,
                "planes": planes,
                "frames": n_frames,
                "plane_z": {p: PLANE_Z[p] for p in planes},
                "ring": RING_XY,
            },
            handle,
        )
    print("bake_gravel_planes done", len(wrote), "sprites ->", OUT_DIR)


if __name__ == "__main__":
    main()
