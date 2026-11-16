"""One-shot: render current vs over-rail conveyor paths for design discussion."""
import bpy
from mathutils import Vector
from pathlib import Path

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)
for c in list(bpy.data.curves):
    bpy.data.curves.remove(c)
for mat in list(bpy.data.materials):
    bpy.data.materials.remove(mat)

here = Path(__file__).resolve().parent
bpy.ops.wm.obj_import(filepath=str(here / "loading_hopper.obj"), forward_axis="Y", up_axis="Z")
o = [x for x in bpy.context.scene.objects if x.type == "MESH"][0]
o.name = "loading_hopper"

HX, WALK, DECK_Z, RAIL_H = 2.40, 0.82, 7.40, 1.05
ox = HX + WALK
rail_x = -ox
top_rail = DECK_Z + RAIL_H
clear = top_rail + 0.25
belt_y = 0.75
foot = Vector((rail_x - 7.6, belt_y, 0.35))
cur_head = Vector((-0.15, belt_y, DECK_Z + 0.55))
knee = Vector((rail_x, belt_y, clear))
dump = Vector((-0.15, belt_y, DECK_Z + 0.55))


def make_poly(name, points, radius, rgba):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, p in enumerate(points):
        spline.points[i].co = (p.x, p.y, p.z, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Emission Color"].default_value = rgba
    bsdf.inputs["Emission Strength"].default_value = 3.0
    obj.data.materials.append(mat)


make_poly("PATH_current", [foot, cur_head], 0.07, (1, 0.1, 0.05, 1))
make_poly("PATH_over_rail", [foot, knee, dump], 0.10, (0.1, 1.0, 0.2, 1))

for name, loc, col in [
    ("MARK_top_rail", (rail_x, belt_y, top_rail), (1, 1, 0, 1)),
    ("MARK_clear", (rail_x, belt_y, clear), (0, 1, 1, 1)),
]:
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=loc)
    s = bpy.context.active_object
    s.name = name
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Emission Color"].default_value = col
    bsdf.inputs["Emission Strength"].default_value = 4.0
    s.data.materials.append(mat)

cam_data = bpy.data.cameras.new("side")
cam = bpy.data.objects.new("side", cam_data)
bpy.context.collection.objects.link(cam)
bpy.context.scene.camera = cam
cam_data.type = "ORTHO"
cam_data.ortho_scale = 16
cam.location = (-4.0, -18.0, 5.0)
cam.rotation_euler = (1.5708, 0, 0)

scene = bpy.context.scene
scene.render.resolution_x = 1400
scene.render.resolution_y = 900
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "MATERIAL"

out = here / "preview_belt_over_rail.png"
scene.render.filepath = str(out)
bpy.ops.render.render(write_still=True)
print("wrote", out)

cam.location = (-14, -12, 9)
cam.rotation_euler = (1.1, 0, -0.9)
cam_data.ortho_scale = 22
out2 = here / "preview_belt_over_rail_3q.png"
scene.render.filepath = str(out2)
bpy.ops.render.render(write_still=True)
print("wrote", out2)
t = (rail_x - foot.x) / (cur_head.x - foot.x)
z_now = foot.z + t * (cur_head.z - foot.z)
print(f"current z@rail={z_now:.2f}  top_rail={top_rail:.2f} clear={clear:.2f}")
