"""Exports a Quaternius character (CC0, see art/BaseCharacter-LICENSE.txt) for the web game.

blender -b chars/<Character>.blend -P art/export_web_glb.py -- sites/meme-mimic/dist/models/<Name>.glb

The web twin of export_mascot.py: same color pass, same big eyes (eyes.py), same six
clips. glTF keeps each action as its own named animation, so the clips are not laid
end to end; the web stage looks them up by name (Idle, Walk, Jump, Victory, Defeat,
RecieveHit).
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
        nt.nodes.clear()
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(b.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = 0.6

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eyes import add_eyes
add_eyes()

CLIPS = ["Idle", "Walk", "Jump", "Victory", "Defeat", "RecieveHit"]

# Only the clips the game plays: every other action is dropped so the file stays small.
for act in list(bpy.data.actions):
    if act.name not in CLIPS:
        bpy.data.actions.remove(act)

ad = arm.animation_data or arm.animation_data_create()
ad.action = None
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
# The exporter finds actions through NLA tracks; one muted track per clip.
for name in CLIPS:
    act = bpy.data.actions[name]
    track = ad.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(act.frame_range[0]), act)
    track.mute = True

for o in scene.objects:
    o.select_set(False)
for o in (arm, body):
    o.hide_viewport = False
    o.hide_set(False)
    o.select_set(True)
bpy.context.view_layer.objects.active = arm

os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=False,
    export_texcoords=False,
    export_normals=True,
    export_tangents=False,
    export_materials="EXPORT",
    export_image_format="NONE",
    export_skins=True,
    export_def_bones=True,
    export_morph=False,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_anim_single_armature=True,
    export_reset_pose_bones=True,
    export_force_sampling=True,
    export_optimize_animation_size=True,
    export_frame_step=2,
    export_lights=False,
    export_cameras=False,
)
print("EXPORTED", out, os.path.getsize(out))
