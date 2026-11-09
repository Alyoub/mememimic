"""Big glossy cartoon eyes, matching the app icon, for the Quaternius characters.

The characters ship with flat slit eyes painted on the head (the "Face" material). This
adds a cream eyeball over each one, with a black pupil and a shine, and binds them to the
Head bone so they move with every animation. Used by export_mascot.py and
character_preview.py.
"""
import bmesh
import bpy
from mathutils import Vector

RADIUS = 0.18          # eyeball radius; heads are ~1.0 wide
SEAT = 0.4             # how far (in radii) the eyeball sits behind the slit, inside the head


def _material(name, rgb, rough, emit=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        nt.nodes.clear()
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(b.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, 1)
    return m


def _sphere(name, center, scale, material):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + center
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    group = o.vertex_groups.new(name="Head")
    group.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    return o


def add_eyes(body_name="Body"):
    body = bpy.data.objects[body_name]
    me = body.data
    face = [i for i, m in enumerate(me.materials) if m and m.name == "Face"]
    mw = body.matrix_world
    verts = {v for p in me.polygons if p.material_index in face for v in p.vertices}
    points = [mw @ me.vertices[i].co for i in verts]
    if not points:
        return False

    # Linear-space colors: cream whites, near-black pupils, a white shine.
    white = _material("EyeWhite", (0.93, 0.87, 0.74), 0.12)
    pupil = _material("Pupil", (0.01, 0.01, 0.012), 0.08)
    shine = _material("EyeShine", (1.0, 1.0, 1.0), 0.1, emit=2.0)

    parts = []
    for side in (-1, 1):
        sel = [p for p in points if p.x * side > 0]
        if not sel:
            continue
        c = sum(sel, Vector()) / len(sel)
        r = RADIUS
        # Characters face -Y: push the ball back into the head so only the front shows.
        center = Vector((c.x, c.y + r * SEAT, c.z))
        front = center.y - r
        parts.append(_sphere("eyeball", center, (r, r, r * 1.08), white))
        # Pupils sit a touch toward the nose and up, for a bright, eager look.
        pc = Vector((center.x - side * r * 0.12, front + r * 0.06, center.z + r * 0.06))
        parts.append(_sphere("pupil", pc, (r * 0.46, r * 0.14, r * 0.5), pupil))
        sc = Vector((pc.x + r * 0.16, pc.y - r * 0.06, pc.z + r * 0.2))
        parts.append(_sphere("shine", sc, (r * 0.13, r * 0.06, r * 0.15), shine))

    # Join into the body so the eyes are skinned to the Head bone with the rest of it.
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    return True
