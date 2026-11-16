"""Build custom hopper-bin FBX/tileset and regenerate the vanilla stamp lua.

Run:
  blender --background --python models/loading-hopper/bake_bin.py
"""

from __future__ import annotations

import os
import runpy
import struct

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = "/Users/jamesrutledge/pz-modding/mods/DumpTruckGravelMod/Contents/mods/DumpTruckGravelMod"
MESH_DIR = os.path.join(REPO, "42.20/media/models_X/IsoObject")
SCRIPT_PATH = os.path.join(REPO, "42.20/media/scripts/loading_hopper_bin.txt")
TILES_PATH = os.path.join(REPO, "42.20/media/loading_hopper_bin.tiles")
SPRITE_MODELS = os.path.join(REPO, "common/media/spriteModels.txt")
TEX_DIR = os.path.join(REPO, "42.20/media/textures/IsoObject")
OBJ_PATH = os.path.join(HERE, "loading_hopper_bin.obj")
FLOOR_M = 2.44949

BANDS = {
    "concrete": (0.50, 0.47, 0.42),
    "deck": (0.26, 0.25, 0.23),
    "galvanized": (0.58, 0.57, 0.53),
    "hopper": (0.35, 0.32, 0.28),
}


def clear_meshes():
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


def import_obj():
    runpy.run_path(os.path.join(HERE, "generate_bin.py"), run_name="__main__")
    bpy.ops.wm.obj_import(filepath=OBJ_PATH)
    obj = bpy.context.selected_objects[0]
    obj.name = "loading_hopper_bin"
    return obj


def paint_uvs(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    uv_lay = bm.loops.layers.uv.verify()
    # Cube project via ops
    bpy.ops.uv.cube_project(cube_size=1.0)
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Assign material colors into a simple atlas strip via vertex colors skip —
    # solid materials are enough for bin silhouette.
    for name, color in BANDS.items():
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        if mat.name not in obj.data.materials:
            obj.data.materials.append(mat)


def export_fbx(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=False,
        use_mesh_modifiers=True,
        mesh_smooth_type="OFF",
        use_triangles=True,
    )


def write_tiles(n_pieces: int):
    def s(text):
        return text.encode("utf-8") + b"\n"

    body = bytearray()
    body += s("loading_hopper_bin")
    body += s("loading_hopper_bin")
    cols = 8
    rows = max(1, (n_pieces + cols - 1) // cols)
    body += struct.pack("<iiii", cols, rows, 1, n_pieces)
    for i in range(n_pieces):
        props = [("alwaysDraw", "")]
        if i == 0:
            props.append(("CustomName", "Loading Hopper"))
        else:
            props.append(("invisible", ""))
        body += struct.pack("<i", len(props))
        for key, val in props:
            body += s(key)
            body += s(val)
    out = bytearray()
    out += b"tdef"
    out += struct.pack("<ii", 1, 1)
    out += body
    os.makedirs(os.path.dirname(TILES_PATH), exist_ok=True)
    with open(TILES_PATH, "wb") as handle:
        handle.write(out)


def write_scripts():
    lines = [
        "module Base",
        "{",
        "    model LoadingHopperBin_0",
        "    {",
        "        mesh = IsoObject/loading_hopper_bin_0,",
        "        static = TRUE,",
        "        scale = 1.0,",
        "    }",
        "    model LoadingHopperBin_1",
        "    {",
        "        mesh = IsoObject/loading_hopper_bin_1,",
        "        static = TRUE,",
        "        scale = 1.0,",
        "    }",
        "}",
    ]
    os.makedirs(os.path.dirname(SCRIPT_PATH), exist_ok=True)
    with open(SCRIPT_PATH, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def write_sprite_models():
    os.makedirs(os.path.dirname(SPRITE_MODELS), exist_ok=True)
    text = """spriteModel
{
    VERSION = 1,

    tileset
    {
        name = loading_hopper_bin,

        tile
        {
            xy = 0 0,
            modelScript = Base.LoadingHopperBin_0,
            translate = 0.0000 0.0000 0.0000,
            rotate = 0.0000 0.0000 0.0000,
            scale = 1.0000,
        }

        tile
        {
            xy = 1 0,
            modelScript = Base.LoadingHopperBin_1,
            translate = 0.0000 0.0000 0.0000,
            rotate = 0.0000 0.0000 0.0000,
            scale = 1.0000,
        }
    }
}
"""
    with open(SPRITE_MODELS, "w", encoding="utf-8") as handle:
        handle.write(text)


def make_stub():
    mesh = bpy.data.meshes.new("stub")
    mesh.from_pydata(
        [(-0.05, -0.05, 0.01), (0.05, -0.05, 0.01), (0.0, 0.05, 0.01)],
        [],
        [(0, 1, 2)],
    )
    obj = bpy.data.objects.new("loading_hopper_bin_0", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def main():
    clear_meshes()
    os.makedirs(MESH_DIR, exist_ok=True)
    for name in os.listdir(MESH_DIR):
        if name.startswith("loading_hopper") and name.endswith(".fbx"):
            os.remove(os.path.join(MESH_DIR, name))

    stub = make_stub()
    export_fbx(stub, os.path.join(MESH_DIR, "loading_hopper_bin_0.fbx"))

    src = import_obj()
    paint_uvs(src)
    # Origin at bin tile center (world −1,0 → blender cell center 0.5, 0.5), z = stamp floor 2.
    src.location = (0.5, 0.5, 2.0 * FLOOR_M)
    bpy.context.view_layer.objects.active = src
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    export_fbx(src, os.path.join(MESH_DIR, "loading_hopper_bin_1.fbx"))

    write_tiles(2)
    write_scripts()
    write_sprite_models()
    runpy.run_path(os.path.join(HERE, "write_vanilla_stamp.py"), run_name="__main__")
    print("bake_bin done")


main()
