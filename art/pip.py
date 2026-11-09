"""Builds Pip, renders a preview, and exports a USDZ for RealityKit.
blender -b -P pip.py -- <preview.png> <Pip.usdz>
"""
import bpy, bmesh, math, sys
from mathutils import Vector

preview, usdz = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def mat(name, color, rough=0.6, coat=0.0, emit=0.0, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Sheen Weight"].default_value = sheen
    b.inputs["Sheen Roughness"].default_value = 0.4
    if emit:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m

FUR = mat("fur", (0.06, 0.4, 0.42), 0.8, sheen=0.5)
CREAM = mat("furLight", (0.5, 0.8, 0.78), 0.85, sheen=0.5)
EYE = mat("eye", (0.05, 0.03, 0.025), 0.08, coat=1.0)
GLINT = mat("glint", (1, 1, 1), 0.2, emit=4)
NOSE = mat("nose", (0.08, 0.05, 0.06), 0.25, coat=0.8)
MOUTH = mat("mouth", (0.3, 0.06, 0.1), 0.5)
BOW = mat("bow", (0.55, 0.58, 0.66), 0.3, coat=0.6)

fuzz_tex = bpy.data.textures.new("fuzz", "CLOUDS")
fuzz_tex.noise_scale = 0.022
fuzz_tex.noise_depth = 2

def fur_nodes():
    """Scatter small tapered fur clumps over the surface, leaning with the surface and a little random."""
    if "FurClumps" in bpy.data.node_groups:
        return bpy.data.node_groups["FurClumps"]
    g = bpy.data.node_groups.new("FurClumps", "GeometryNodeTree")
    g.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    g.interface.new_socket("Length", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Density", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Material", in_out="INPUT", socket_type="NodeSocketMaterial")
    g.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N = g.nodes; L = g.links
    gi = N.new("NodeGroupInput"); go = N.new("NodeGroupOutput")
    dist = N.new("GeometryNodeDistributePointsOnFaces"); dist.distribute_method = "POISSON"
    dist.inputs["Distance Min"].default_value = 0.0075
    clump = N.new("GeometryNodeMeshCone"); clump.inputs["Vertices"].default_value = 5
    clump.inputs["Radius Top"].default_value = 0.0; clump.inputs["Radius Bottom"].default_value = 0.0075
    clump.inputs["Depth"].default_value = 1.0
    shift = N.new("GeometryNodeTransform"); shift.inputs["Translation"].default_value = (0, 0, 0.45)
    align = N.new("FunctionNodeAlignEulerToVector"); align.axis = "Z"
    rnd = N.new("FunctionNodeRandomValue"); rnd.data_type = "FLOAT_VECTOR"
    rnd.inputs["Min"].default_value = (-0.25, -0.25, -3.14); rnd.inputs["Max"].default_value = (0.25, 0.25, 3.14)
    rot_add = N.new("ShaderNodeVectorMath"); rot_add.operation = "ADD"
    scl = N.new("FunctionNodeRandomValue"); scl.data_type = "FLOAT"
    scl.inputs[2].default_value = 0.7; scl.inputs[3].default_value = 1.2
    mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
    comb = N.new("ShaderNodeCombineXYZ")
    inst = N.new("GeometryNodeInstanceOnPoints")
    real = N.new("GeometryNodeRealizeInstances")
    join = N.new("GeometryNodeJoinGeometry")
    L.new(gi.outputs["Geometry"], dist.inputs["Mesh"])
    L.new(gi.outputs["Density"], dist.inputs["Density Max"])
    L.new(clump.outputs["Mesh"], shift.inputs["Geometry"])
    # Comb the fur slightly downward so it lies like a pelt instead of bristling.
    comb_dir = N.new("ShaderNodeVectorMath"); comb_dir.operation = "ADD"
    comb_dir.inputs[1].default_value = (0, 0, -0.55)
    L.new(dist.outputs["Normal"], comb_dir.inputs[0]); L.new(comb_dir.outputs["Vector"], align.inputs["Vector"])
    # Only grow where the mesh's "fur" attribute is set (keeps the face clear).
    mask = N.new("GeometryNodeInputNamedAttribute"); mask.data_type = "FLOAT"; mask.inputs["Name"].default_value = "fur"
    gt = N.new("FunctionNodeCompare"); gt.data_type = "FLOAT"; gt.operation = "GREATER_THAN"; gt.inputs[1].default_value = 0.5
    L.new(mask.outputs["Attribute"], gt.inputs[0]); L.new(gt.outputs["Result"], dist.inputs["Selection"])
    setmat = N.new("GeometryNodeSetMaterial")
    L.new(align.outputs["Rotation"], rot_add.inputs[0]); L.new(rnd.outputs["Value"], rot_add.inputs[1])
    L.new(dist.outputs["Points"], inst.inputs["Points"]); L.new(shift.outputs["Geometry"], inst.inputs["Instance"])
    L.new(rot_add.outputs["Vector"], inst.inputs["Rotation"])
    L.new(scl.outputs[1], mul.inputs[0]); L.new(gi.outputs["Length"], mul.inputs[1])
    L.new(mul.outputs[0], comb.inputs["Z"]); comb.inputs["X"].default_value = 1; comb.inputs["Y"].default_value = 1
    L.new(comb.outputs["Vector"], inst.inputs["Scale"])
    L.new(inst.outputs["Instances"], real.inputs["Geometry"])
    L.new(real.outputs["Geometry"], setmat.inputs["Geometry"]); L.new(gi.outputs["Material"], setmat.inputs["Material"])
    L.new(gi.outputs["Geometry"], join.inputs["Geometry"]); L.new(setmat.outputs["Geometry"], join.inputs["Geometry"])
    L.new(join.outputs["Geometry"], go.inputs["Geometry"])
    return g

def finish(o, m, sub=2, fuzz=0.0):
    o.data.materials.clear(); o.data.materials.append(m)
    for p in o.data.polygons: p.use_smooth = True
    if sub:
        s = o.modifiers.new("sub", "SUBSURF"); s.levels = s.render_levels = min(sub, 1) if fuzz else sub
    if fuzz:
        a = o.data.attributes.new("fur", "FLOAT", "POINT")
        a.data.foreach_set("value", [1.0] * len(o.data.vertices))
        mod = o.modifiers.new("fur", "NODES"); mod.node_group = fur_nodes()
        ident = {i.name: i.identifier for i in mod.node_group.interface.items_tree if i.in_out == "INPUT"}
        mod[ident["Length"]] = fuzz * 1.9
        mod[ident["Density"]] = 6000.0
        mod[ident["Material"]] = m
    return o

def blob(name, loc, scale, m, sub=2, fuzz=0.0, seg=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, m, sub, fuzz)

def cone(name, base, tip_offset, r, m, fuzz=0.0, squash=1.0):
    """A soft, rounded cone from `base` toward `base + tip_offset` (ears, tufts)."""
    length = tip_offset.length
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r, radius2=r * 0.12, depth=length, location=(0, 0, 0))
    o = bpy.context.object; o.name = name
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-4], cuts=6)
    for v in bm.verts:
        t = min(1.0, max(0.0, (v.co.z + length / 2) / length))
        v.co.y *= squash
        v.co.x *= 1 + 0.4 * math.sin(math.pi * t ** 0.8)  # bulge the middle like a fluffy ear
        v.co.z += length / 2
    bm.to_mesh(o.data); bm.free()
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(tip_offset.normalized())
    o.location = base
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return finish(o, m, 2, fuzz)

def group(name, pivot, children, parent=None):
    """An empty at the joint, holding its parts, so the app can rotate around the joint."""
    e = bpy.data.objects.new(name, None); scene.collection.objects.link(e)
    e.location = pivot
    bpy.context.view_layer.update()
    for c in children:
        c.parent = e
        c.matrix_parent_inverse = e.matrix_world.inverted()
    if parent:
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    return e

# --------------------------------------------------------------- body + legs
torso = blob("torso", (0, 0, 0.31), (0.19, 0.17, 0.2), FUR, fuzz=0.012)
for v in torso.data.vertices:  # pear: fuller hips
    if v.co.z < 0: v.co.x *= 1.08; v.co.y *= 1.06
belly = blob("belly", (0, -0.115, 0.29), (0.12, 0.07, 0.14), CREAM, fuzz=0.008)
bow_parts = [
    blob("bowL", (-0.045, -0.165, 0.47), (0.045, 0.02, 0.03), BOW, sub=1),
    blob("bowR", (0.045, -0.165, 0.47), (0.045, 0.02, 0.03), BOW, sub=1),
    blob("bowKnot", (0, -0.18, 0.47), (0.018, 0.015, 0.018), BOW, sub=1),
]

legs = []
for side, label in ((-1, "L"), (1, "R")):
    leg = blob(f"leg{label}_mesh", (side * 0.085, -0.01, 0.1), (0.07, 0.075, 0.1), FUR, fuzz=0.01)
    foot = blob(f"foot{label}_mesh", (side * 0.09, -0.04, 0.03), (0.075, 0.09, 0.04), FUR, fuzz=0.006)
    legs.append(group(f"leg{label}", (side * 0.085, 0, 0.17), [leg, foot]))

# --------------------------------------------------------------- arms
arms = []
for side, label in ((-1, "L"), (1, "R")):
    arm = blob(f"arm{label}_mesh", (side * 0.2, -0.01, 0.3), (0.05, 0.05, 0.11), FUR, fuzz=0.01)
    arm.rotation_euler = (0, side * -0.35, 0)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    paw = blob(f"paw{label}_mesh", (side * 0.235, -0.015, 0.205), (0.05, 0.045, 0.045), FUR, fuzz=0.006)
    arms.append(group(f"arm{label}", (side * 0.165, 0, 0.4), [arm, paw]))

# --------------------------------------------------------------- tail
tail_parts = [
    blob("tail1", (0, 0.2, 0.2), (0.1, 0.11, 0.1), FUR, fuzz=0.016),
    blob("tail2", (0, 0.3, 0.29), (0.13, 0.12, 0.13), FUR, fuzz=0.018),
    blob("tail3", (0, 0.33, 0.42), (0.1, 0.1, 0.1), CREAM, fuzz=0.016),
]
tail = group("tail", (0, 0.15, 0.2), tail_parts)

# --------------------------------------------------------------- head
skull = blob("skull", (0, 0, 0.67), (0.25, 0.22, 0.22), FUR, fuzz=0.014)
for v in skull.data.vertices:  # wider cheeks, softer chin
    if v.co.z < 0.0: v.co.x *= 1.0 + 0.12 * (-v.co.z / 0.22)
# Keep the face bare so the eyes, nose and mouth read clearly.
fa = skull.data.attributes["fur"]
fa.data.foreach_set("value", [0.0 if (v.co.y < -0.1 and abs(v.co.x) < 0.17 and -0.12 < v.co.z < 0.14) else 1.0 for v in skull.data.vertices])
cheeks = [cone(f"cheek{s}", Vector((s * 0.2, -0.02, 0.6)), Vector((s * 0.12, -0.02, -0.05)), 0.07, FUR, fuzz=0.01, squash=0.6)
          for s in (-1, 1)]
muzzle = blob("muzzle", (0, -0.165, 0.6), (0.11, 0.07, 0.075), CREAM, fuzz=0.006)
nose = blob("nose", (0, -0.232, 0.632), (0.032, 0.022, 0.022), NOSE, sub=1)
mouth = blob("mouth", (0, -0.225, 0.578), (0.035, 0.012, 0.016), MOUTH, sub=1)
brows = [blob(f"brow{s}", (s * 0.095, -0.19, 0.78), (0.035, 0.012, 0.014), CREAM, sub=1) for s in (-1, 1)]

eyes = []
for side, label in ((-1, "L"), (1, "R")):
    ball = blob(f"eye{label}_ball", (side * 0.095, -0.19, 0.69), (0.052, 0.03, 0.058), EYE, sub=1)
    g1 = blob(f"eye{label}_glint", (side * 0.095 - 0.016, -0.22, 0.71), (0.014, 0.006, 0.016), GLINT, sub=1)
    g2 = blob(f"eye{label}_glint2", (side * 0.095 + 0.014, -0.219, 0.672), (0.006, 0.004, 0.006), GLINT, sub=1)
    eyes.append(group(f"eye{label}", (side * 0.095, -0.19, 0.69), [ball, g1, g2]))

ears = []
for side, label in ((-1, "L"), (1, "R")):
    base = Vector((side * 0.13, 0.0, 0.82))
    tip = Vector((side * 0.17, 0.02, 0.33))
    outer = cone(f"ear{label}_outer", base, tip, 0.14, FUR, fuzz=0.012, squash=0.42)
    inner = cone(f"ear{label}_inner", base + Vector((side * 0.008, -0.035, 0.03)), tip * 0.8, 0.095, CREAM, fuzz=0.008, squash=0.28)
    tuft = cone(f"ear{label}_tuft", base + tip * 0.78, Vector((side * 0.02, 0, 0.12)), 0.03, FUR, fuzz=0.004, squash=0.6)
    ears.append(group(f"ear{label}", base, [outer, inner, tuft]))

mouth_g = group("mouth", (0, -0.225, 0.578), [mouth])
head = group("head", (0, 0, 0.47), [skull, muzzle, nose, *cheeks, *brows])
for c in [*eyes, *ears, mouth_g]:
    c.parent = head; c.matrix_parent_inverse = head.matrix_world.inverted()

body = group("body", (0, 0, 0.12), [torso, belly, *bow_parts])
for c in [head, *arms, tail]:
    c.parent = body; c.matrix_parent_inverse = body.matrix_world.inverted()
root = group("Pip", (0, 0, 0), [])
for c in [body, *legs]:
    c.parent = root; c.matrix_parent_inverse = root.matrix_world.inverted()

# --------------------------------------------------------------- preview render
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.93, 0.93, 0.95, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
def light(loc, energy, size, color=(1, 1, 1)):
    l = bpy.data.lights.new("l", "AREA"); l.energy = energy; l.size = size; l.color = color
    o = bpy.data.objects.new("l", l); scene.collection.objects.link(o); o.location = loc
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = (Vector((0, 0, 0.6)) - Vector(loc)).to_track_quat("-Z", "Y")
light((-1.5, -2, 2.2), 260, 2, (1, 0.96, 0.9)); light((1.6, 1.5, 1.8), 220, 1.2, (0.8, 0.9, 1))
bpy.ops.mesh.primitive_plane_add(size=10); finish(bpy.context.object, mat("floor", (0.9, 0.9, 0.92), 0.8), sub=0)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.lens = 70; cam.location = (1.1, -3.4, 1.0)
cam.rotation_mode = "QUATERNION"; cam.rotation_quaternion = (Vector((0, 0, 0.55)) - cam.location).to_track_quat("-Z", "Y")
scene.render.engine = "CYCLES"; scene.cycles.samples = 64; scene.cycles.use_denoising = True
scene.cycles.device = "GPU"
prefs = bpy.context.preferences.addons["cycles"].preferences; prefs.compute_device_type = "METAL"; prefs.get_devices()
for d in prefs.devices: d.use = True
scene.render.resolution_x, scene.render.resolution_y = 800, 1000
scene.view_settings.view_transform = "AgX"
scene.render.filepath = preview
bpy.ops.render.render(write_still=True)

# --------------------------------------------------------------- export (Pip hierarchy only)
for o in list(scene.objects):
    o.select_set(False)
def select_tree(o):
    o.select_set(True)
    for c in o.children: select_tree(c)
select_tree(root)
bpy.ops.wm.usd_export(filepath=usdz, selected_objects_only=True, export_materials=True, evaluation_mode="RENDER",
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
                      export_lights=False, export_cameras=False)
