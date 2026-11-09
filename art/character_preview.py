"""Renders a Quaternius character exactly as its file colors it (material viewport colors).

blender -b chars/<Character>.blend -P art/character_preview.py -- <out.png> [action] [frame] [portrait]

portrait: a square head-and-shoulders render for the in-app character picker.
"""
import bpy, sys, os
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
action = args[1] if len(args) > 1 else "Idle"
frame = int(args[2]) if len(args) > 2 else 0
scene = bpy.context.scene

# The files store their look as viewport colors (no shader nodes). Turn each into a lit
# material with the same color so renders and exports match what Blender shows.
for m in bpy.data.materials:
    color = tuple(m.diffuse_color)
    m.use_nodes = True
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        # Some files carry a leftover node tree without a BSDF; rebuild a plain one.
        nt.nodes.clear()
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(b.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = 0.6

# Big glossy eyes, matching the app icon (art/eyes.py).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eyes import add_eyes
add_eyes()

for o in list(scene.objects):
    if o.type in {"LIGHT", "CAMERA"}:
        bpy.data.objects.remove(o)
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
def area(loc, energy, size):
    l = bpy.data.lights.new("a", "AREA"); l.energy = energy; l.size = size
    o = bpy.data.objects.new("a", l); scene.collection.objects.link(o); o.location = loc
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = (Vector((0, 0, 1.4)) - Vector(loc)).to_track_quat("-Z", "Y")
area((-3, -4, 5), 1400, 3); area((4, -3, 2), 400, 4); area((2, 4, 4), 700, 2)
bpy.ops.mesh.primitive_plane_add(size=30); bpy.context.object.is_shadow_catcher = True
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.lens = 55; cam.location = (3.0, -8.0, 2.4)
cam.rotation_mode = "QUATERNION"; cam.rotation_quaternion = (Vector((0, 0, 1.55)) - cam.location).to_track_quat("-Z", "Y")

arm = bpy.data.objects["CharacterArmature"]
arm.animation_data_create().action = bpy.data.actions[action]
scene.frame_set(frame)

scene.render.engine = "CYCLES"; scene.cycles.samples = 64; scene.cycles.use_denoising = True
scene.cycles.device = "GPU"
prefs = bpy.context.preferences.addons["cycles"].preferences; prefs.compute_device_type = "METAL"; prefs.get_devices()
for d in prefs.devices: d.use = True
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = 600, 900
if "portrait" in args:
    for o in scene.objects:
        if o.type == "MESH" and o.is_shadow_catcher:
            o.hide_render = True
    # Frame from the chest to the top of whatever the character wears (hats vary).
    top = bpy.data.objects["Body"].dimensions.z
    low = 1.05
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = (top - low) + 0.25
    centre = (top + low) / 2
    cam.location = (1.4, -8.0, centre + 0.2)
    cam.rotation_quaternion = (Vector((0, 0, centre)) - cam.location).to_track_quat("-Z", "Y")
    scene.render.resolution_x = scene.render.resolution_y = 360
scene.view_settings.view_transform = "Standard"
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
