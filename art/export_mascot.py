"""Exports a Quaternius character (CC0, see art/BaseCharacter-LICENSE.txt) for the app.

blender -b chars/<Character>.blend -P art/export_mascot.py -- EchoBloom/Models/<Name>.usdz

All supported characters share one 23-bone skeleton and one set of animation actions,
so they export with the same clip timeline. USDZ carries a single timeline, so the
clips the game uses are laid end to end with NLA strips; the app slices them back out
with the CLIP table printed below (mirrored in MascotRig.Clip).

Materials keep the colors stored in the file (its viewport colors), so each character
looks in the app the way it looks in Blender, plus the big icon-style eyes from eyes.py.
"""
import bpy, sys, os

out = sys.argv[sys.argv.index("--") + 1]
scene = bpy.context.scene
arm = bpy.data.objects["CharacterArmature"]
body = bpy.data.objects["Body"]

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

# Big glossy eyes, matching the app icon (art/eyes.py). Added after the color pass so
# their own materials stay as authored; they join the Body mesh, skinned to the Head bone.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eyes import add_eyes
add_eyes()

CLIPS = ["Idle", "Walk", "Jump", "Victory", "Defeat", "RecieveHit"]
GAP = 2  # frames between clips so trims never bleed into a neighbour

ad = arm.animation_data or arm.animation_data_create()
ad.action = None
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
track = ad.nla_tracks.new()
start = 0
table = []
for name in CLIPS:
    act = bpy.data.actions[name]
    a0, a1 = act.frame_range
    strip = track.strips.new(name, int(start), act)
    strip.action_frame_start, strip.action_frame_end = a0, a1
    length = a1 - a0
    table.append((name, start, start + length))
    start += length + GAP

scene.frame_start = 0
scene.frame_end = int(start - GAP)
fps = scene.render.fps / scene.render.fps_base

# Select directly: some files open with a context where select_all() can't run.
for o in scene.objects:
    o.select_set(False)
for o in (arm, body):
    o.hide_viewport = False
    o.hide_set(False)
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.wm.usd_export(
    filepath=out,
    selected_objects_only=True,
    export_animation=True,
    export_armatures=True,
    only_deform_bones=True,
    export_materials=True,
    generate_preview_surface=True,
    export_textures=False,
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y",
)

print("FPS", fps)
for name, a, b in table:
    print(f"CLIP {name} {a / fps:.4f} {b / fps:.4f}")
