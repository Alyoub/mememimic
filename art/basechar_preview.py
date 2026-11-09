"""Preview renders of Quaternius' BaseCharacter (CC0) in game poses and player colors.

blender -b BaseCharacter.blend -P art/basechar_preview.py -- <out_dir>
"""
import bpy, sys, os, math
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
scene = bpy.context.scene
arm = bpy.data.objects["CharacterArmature"]
body = bpy.data.objects["Body"]

def srgb(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def pbr(name, rgb, rough=0.55):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(rgb), 1)
    b.inputs["Roughness"].default_value = rough
    return m

# Replace the flat viewport colors with lit materials (Skin is the tintable part).
face = bpy.data.materials["Face"]
skin = bpy.data.materials["Skin"]
for m, rgb in ((face, (0.98, 0.95, 0.86)), (skin, (0.2, 0.2, 0.22))):
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(rgb), 1)
    b.inputs["Roughness"].default_value = 0.55

for o in list(scene.objects):
    if o.type in {"LIGHT", "CAMERA"}:
        bpy.data.objects.remove(o)

world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
def area(loc, energy, size):
    l = bpy.data.lights.new("a", "AREA"); l.energy = energy; l.size = size
    o = bpy.data.objects.new("a", l); scene.collection.objects.link(o); o.location = loc
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = (Vector((0, 0, 1.3)) - Vector(loc)).to_track_quat("-Z", "Y")
area((-3, -4, 5), 1400, 3); area((4, -3, 2), 400, 4); area((2, 4, 4), 700, 2)

bpy.ops.mesh.primitive_plane_add(size=30)
floor = bpy.context.object
floor.is_shadow_catcher = True

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.lens = 60
cam.location = (3.2, -7.5, 2.6)
cam.rotation_mode = "QUATERNION"; cam.rotation_quaternion = (Vector((0, 0, 1.35)) - cam.location).to_track_quat("-Z", "Y")

scene.render.engine = "CYCLES"; scene.cycles.samples = 64; scene.cycles.use_denoising = True
scene.cycles.device = "GPU"
prefs = bpy.context.preferences.addons["cycles"].preferences; prefs.compute_device_type = "METAL"; prefs.get_devices()
for d in prefs.devices: d.use = True
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = 700, 900
scene.view_settings.view_transform = "AgX"

poses = [("Idle", 0, (0.2, 0.2, 0.22)), ("Idle", 0, (0.62, 0.9, 0.2)), ("Jump", 10, (1.0, 0.42, 0.72)),
         ("Victory", 22, (0.27, 0.7, 1.0)), ("Defeat", 45, (1.0, 0.56, 0.16))]
arm.animation_data_create()
for i, (action, frame, rgb) in enumerate(poses):
    arm.animation_data.action = bpy.data.actions[action]
    scene.frame_set(frame)
    skin.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb(rgb), 1)
    scene.render.filepath = os.path.join(out, f"{i}-{action.lower()}.png")
    bpy.ops.render.render(write_still=True)
