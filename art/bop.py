"""Bop: modeling, materials and preview renders.

blender -b -P art/bop.py -- <out_dir> [base|wide] [topology] [stage <app_screenshot.png>]

  wide      variant with eyes set further round the head (side-view tradeoff demo)
  topology  also render wireframe close-ups of the deformation cage
  stage     also render Bop on the app's stage with the turn-screen camera

Units are meters with Bop about 1.1 m tall (floor to ear tip), facing -Y.
Proportions are measured from the reference sheet (front view: 487 px from floor
to top of head; X = (px - 532) / 487, Z = (610 - py) / 487).
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
out_dir = args[0]
VARIANT = "wide" if "wide" in args else "base"
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ------------------------------------------------------------------ materials

def srgb(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def material(name, color, rough=0.5, coat=0.0, sss=0.0, bump=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(color), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.15
    if sss:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (1.0, 0.4, 0.25)
        b.inputs["Subsurface Scale"].default_value = 0.03
    if bump:
        # Very fine noise: a soft-touch vinyl feel, not a visible texture.
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 260
        noise.inputs["Detail"].default_value = 2
        bmp = nt.nodes.new("ShaderNodeBump")
        bmp.inputs["Strength"].default_value = bump
        bmp.inputs["Distance"].default_value = 0.0005
        nt.links.new(noise.outputs["Fac"], bmp.inputs["Height"])
        nt.links.new(bmp.outputs["Normal"], b.inputs["Normal"])
    return m

SKIN = material("skin", (0.5, 0.78, 0.58), rough=0.55, sss=0.12, bump=0.05)
MOUTH = material("mouthInside", (0.29, 0.09, 0.2), rough=0.6)
CREAM = material("eyeWhite", (0.99, 0.95, 0.86), rough=0.25, coat=0.6)
PLUM = material("pupil", (0.3, 0.1, 0.22), rough=0.15, coat=1.0)
BROW = material("brow", (0.33, 0.12, 0.25), rough=0.5)
GLINT = material("highlight", (1, 1, 1), rough=0.1)
GLINT.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 1, 1, 1)
GLINT.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0
TOOTH = material("tooth", (0.99, 0.96, 0.88), rough=0.3, coat=0.4)
TONGUE = material("tongue", (0.95, 0.47, 0.42), rough=0.45, sss=0.2)
COLLAR = material("collar", (0.93, 0.44, 0.38), rough=0.45, coat=0.3)
MEDAL = material("medallion", (0.98, 0.93, 0.8), rough=0.3, coat=0.5)

# ------------------------------------------------------------------ helpers

# Compact build: everything above the shoulder line drops by DROP while the torso
# and legs shorten and widen. (Head-to-height ratio: reference 0.55; measured from
# renders, the previous build was ~0.575, so the body needed width, not less length.)
DROP = 0.03

def px(x, y):
    """Reference-sheet pixel (front view) to world X, Z."""
    return (x - 532) / 487, (610 - y) / 487 - (DROP if y < 440 else 0.0)

def ellipsoid(name, loc, scale, seg=64, rings=32, shape=None, rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    for v in o.data.vertices:
        c = v.co.copy()
        if shape:
            c = shape(c)
        v.co = Vector((c.x * scale[0], c.y * scale[1], c.z * scale[2]))
    if rot:
        o.rotation_euler = rot
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o

def finish(o, m, sub=2):
    o.data.materials.clear()
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    if sub:
        s = o.modifiers.new("sub", "SUBSURF")
        s.levels = s.render_levels = sub
    return o

def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)

def union(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o

# ------------------------------------------------------------------ body volume
# Built from overlapping volumes, then fused by voxel remeshing into one surface
# and smoothed so joins become soft fillets instead of visible seams.

HEAD_C = Vector((0, 0.0, px(0, 256)[1]))      # head centre, z ≈ 0.727
HEAD = (0.395, 0.31, 0.29)                     # half extents: width, depth, height

def head_shape(c):
    # Bun shape: domed crown, broad cheeks, softly flattened jaw.
    z = c.z
    if z < 0:
        k = -z
        c.x *= 1.0 + 0.2 * k * (1.0 - 0.5 * k)   # broad cheeks low on the head
        c.y *= 1.0 + 0.04 * k
        c.z = -(k ** 1.2) * 1.06
    else:
        c.x *= 1.0 - 0.06 * z * z
        c.z *= 1.0 - 0.06 * z * z * z      # slightly flatter crown
        c.y *= 1.0 - 0.06 * z * z
    # Face is slightly flatter than the back of the head.
    if c.y < 0:
        c.y *= 0.94
    return c

head = ellipsoid("head", HEAD_C, HEAD, shape=head_shape)

def torso_shape(c):
    if c.z < 0:
        c.x *= 1.0 + 0.16 * (-c.z)   # pear: fuller hips
        c.y *= 1.0 + 0.12 * (-c.z)
    return c

torso = ellipsoid("torso", (0, 0.0, 0.295), (0.172, 0.148, 0.14), shape=torso_shape)
neck = ellipsoid("neck", (0, 0.0, 0.42), (0.125, 0.115, 0.07))

parts = [head, torso, neck]

SHOULDER_Z = 0.415 - DROP

# Arms in T-pose, tapering slightly toward the hands.
for s in (-1, 1):
    shoulder = Vector((s * 0.13, 0, SHOULDER_Z))
    hand_c = Vector((s * 0.49, 0, SHOULDER_Z))
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1, depth=1, location=(0, 0, 0), rotation=(0, math.pi / 2, 0))
    arm = bpy.context.object
    bm = bmesh.new(); bm.from_mesh(arm.data)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-4], cuts=12)
    bm.to_mesh(arm.data); bm.free()
    arm.location = (shoulder + hand_c) / 2
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    length = (hand_c - shoulder).length
    for v in arm.data.vertices:
        t = (v.co.x * s + 0.5)                      # 0 at shoulder, 1 at hand
        r = 0.06 - 0.012 * t
        v.co = Vector((v.co.x * length, v.co.y * r, v.co.z * r * 0.95))
    arm.name = f"arm{s}"
    parts.append(arm)
    # Hand: a soft palm, three fanned fingers and a raised thumb. The fan spacing keeps
    # ~2 cm between fingertips so voxel fusing doesn't web them together.
    palm = Vector((s * 0.505, -0.004, SHOULDER_Z))
    parts.append(ellipsoid(f"palm{s}", palm, (0.052, 0.04, 0.05), seg=32, rings=16))
    for j, deg in enumerate((-36, 0, 36)):
        th = math.radians(deg)
        d = Vector((s * math.cos(th), 0, math.sin(th)))
        parts.append(ellipsoid(f"finger{s}_{j}", palm + d * 0.058, (0.036, 0.021, 0.019), seg=24, rings=12, rot=(0, -s * th, 0)))
    parts.append(ellipsoid(f"thumb{s}", palm + Vector((-s * 0.012, -0.026, 0.05)), (0.019, 0.02, 0.031), seg=24, rings=12,
                           rot=(0.35, s * 0.25, 0)))

# Short legs and broad rounded feet with three soft toes.
for s in (-1, 1):
    parts.append(ellipsoid(f"leg{s}", (s * 0.095, 0.0, 0.12), (0.095, 0.09, 0.1), seg=32, rings=16))

    def foot_shape(c):
        if c.z < -0.2:
            c.z = -0.2 + (c.z + 0.2) * 0.25   # flat sole
        return c

    parts.append(ellipsoid(f"foot{s}", (s * 0.12, -0.045, 0.052), (0.115, 0.145, 0.064), seg=48, rings=24, shape=foot_shape))
    for j, dx in enumerate((-0.05, 0.0, 0.05)):
        parts.append(ellipsoid(f"toe{s}_{j}", (s * 0.12 + dx * 0.95, -0.15, 0.044), (0.032, 0.036, 0.032), seg=24, rings=12))

# Asymmetric ear lobes: the left stands tall, the right tips outward.
def ear_shape(c):
    # Rounded leaf: wider near the top, pinched toward the root.
    t = (c.z + 1) / 2
    c.x *= 0.85 + 0.25 * t       # rounder at the top, slightly narrower at the root
    if c.y < 0:
        c.y *= 0.75        # gently cupped front
    return c

ex, ez = px(437, 98)
parts.append(ellipsoid("earL", (ex, 0.03, ez), (0.095, 0.07, 0.115), shape=ear_shape, rot=(0.0, -0.22, -0.6)))
parts.append(ellipsoid("earLroot", (ex + 0.03, 0.03, ez - 0.1), (0.05, 0.04, 0.06)))
ex, ez = px(716, 165)
parts.append(ellipsoid("earR", (ex, 0.03, ez), (0.1, 0.07, 0.105), shape=ear_shape, rot=(0.0, 0.92, 0.6)))
parts.append(ellipsoid("earRroot", (ex - 0.06, 0.03, ez - 0.045), (0.06, 0.04, 0.05)))

body = union(parts, "Bop")
body.data.remesh_voxel_size = 0.0065
bpy.context.view_layer.objects.active = body
bpy.ops.object.voxel_remesh()
sm = body.modifiers.new("fillet", "SMOOTH")
sm.factor = 0.5
sm.iterations = 4
apply_mods(body)

# ------------------------------------------------------------------ face placement

def surface(x, z, from_y=-2.0):
    """First hit on the body's front, looking along +Y at world (x, z)."""
    hit, loc, normal, _ = body.ray_cast(Vector((x, from_y, z)), Vector((0, 1, 0)))
    if not hit:
        raise RuntimeError(f"no surface at {x:.3f}, {z:.3f}")
    return loc, normal

def clean_manifold(o):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bad = [e for e in bm.edges if not e.is_manifold]
    bmesh.ops.delete(bm, geom=list({f for e in bad for f in e.link_faces}), context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free()

# Clean quad topology for rigging. QuadriFlow needs a strictly manifold input; voxel
# output occasionally has a stray non-manifold edge at thin spots, so clean and retry.
bpy.context.view_layer.objects.active = body
before = len(body.data.polygons)
for attempt, voxel in enumerate((None, 0.008, 0.007)):
    if voxel:
        body.data.remesh_voxel_size = voxel
        bpy.ops.object.voxel_remesh()
        sm = body.modifiers.new("fillet", "SMOOTH"); sm.factor = 0.5; sm.iterations = 4
        apply_mods(body)
        before = len(body.data.polygons)
    clean_manifold(body)
    bpy.ops.object.quadriflow_remesh(target_faces=16000, use_mesh_symmetry=False, use_preserve_sharp=False, seed=3 + attempt)
    if len(body.data.polygons) < before * 0.5:
        break
else:
    raise RuntimeError("QuadriFlow could not remesh the body")
print("faces before/after quadriflow:", before, len(body.data.polygons))
relax = body.modifiers.new("relax", "SMOOTH"); relax.factor = 0.5; relax.iterations = 2
apply_mods(body)
# Keep the QuadriFlow cage for topology inspection (the future rig's deformation cage).
cage = body.copy(); cage.data = body.data.copy(); cage.name = "Bop_cage"
scene.collection.objects.link(cage)
cage.hide_render = True
sub = body.modifiers.new("sub", "SUBSURF"); sub.levels = 1
apply_mods(body)

# Mouth: a real cavity cut into the head, a "D" shape (flatter top, round bottom).
mx, mz = px(540, 330)
mouth_front, mouth_n = surface(mx, mz)
MOUTH_C = mouth_front + Vector((0, 0.06, 0.0))
MOUTH_S = (0.138, 0.1, 0.098)
TOP, SMILE = 0.55, 0.15          # flatter top edge; corners lifted into a smile

def mouth_r(x, z):
    """Normalised radius in the mouth's "D" shape: < 1 inside the opening."""
    u = (x - mx) / MW
    dz = (z - mz) - MH * SMILE * u * u
    w = dz / (MH * (TOP if dz > 0 else 1.0))
    return math.hypot(u, w)

def mouth_point(u, w):
    """Inverse of mouth_r on the (u, w) unit disc."""
    return mx + u * MW, mz + w * MH * (TOP if w > 0 else 1.0) + MH * SMILE * u * u

# Instead of a boolean (which leaves a ragged rim), press a smooth "D"-shaped cavity
# into the dense front surface. The rim stays soft and the topology stays clean for
# mouth blend shapes later.
MW, MH = MOUTH_S[0], MOUTH_S[2]
DEPTH = 0.11
body.data.materials.clear()
body.data.materials.append(SKIN)
body.data.materials.append(MOUTH)
pushed = {}
body.data.update()
for v in body.data.vertices:
    if v.co.y > mouth_front.y + 0.06 or v.co.y > 0:
        continue
    r = mouth_r(v.co.x, v.co.z)
    if r < 1.0:
        k = min(1.0, (1.0 - r) / 0.28)
        k = k * k * (3 - 2 * k)                    # smoothstep wall
        # Pressed straight back: following the surface normal folded the steep walls.
        v.co.y += DEPTH * k
        pushed[v.index] = DEPTH * k
for p in body.data.polygons:
    p.use_smooth = True
s = body.modifiers.new("sub", "SUBSURF")
s.levels = 1
s.render_levels = 2

# Mouth lining: a thin dark shell laid over the cavity wall, bounded by an exact
# ellipse so the lip line is smooth (per-face colouring would follow the mesh grid).
def mouth_lining(rings=14, segs=96, edge=0.965):
    verts, faces = [], []
    for i in range(rings + 1):
        r = edge * i / rings
        for j in range(segs):
            a = 2 * math.pi * j / segs
            x, z = mouth_point(r * math.cos(a), r * math.sin(a))
            hit, loc, n, _ = body.ray_cast(Vector((x, -2, z)), Vector((0, 1, 0)))
            verts.append(loc + n * 0.0015 if hit else Vector((x, mouth_front.y + DEPTH, z)))
    for i in range(rings):
        for j in range(segs):
            a0 = i * segs + j
            a1 = i * segs + (j + 1) % segs
            faces.append((a0, a1, a1 + segs, a0 + segs))
    me = bpy.data.meshes.new("mouthLining")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    o = bpy.data.objects.new("mouthLining", me)
    scene.collection.objects.link(o)
    return finish(o, MOUTH, sub=1)

mouth_lining()

# Tongue and the single rounded upper tooth inside the cavity.
finish(ellipsoid("tongue", (mx, mouth_front.y + 0.08, mz - 0.05), (0.092, 0.062, 0.044)), TONGUE)
tooth = ellipsoid("tooth", (mx, mouth_front.y + 0.03, mz + MH * TOP - 0.03), (0.04, 0.018, 0.034),
                  shape=lambda c: Vector((c.x, c.y, c.z * (0.55 if c.z > 0 else 1.0))))
finish(tooth, TOOTH)

def lid_curve(name, pts, radius=0.0085):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 6
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts):
        p.co = (*c, 1)
    sp.use_endpoint_u = True
    sp.order_u = 4
    tap = bpy.data.curves.new(name + "_taper", "CURVE")
    tsp = tap.splines.new("BEZIER")
    tsp.bezier_points.add(2)
    for bp, co in zip(tsp.bezier_points, ((0, 0.2, 0), (0.5, 1.0, 0), (1, 0.2, 0))):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    tobj = bpy.data.objects.new(name + "_taper", tap)
    scene.collection.objects.link(tobj)
    tobj.hide_render = True
    cu.taper_object = tobj
    cu.materials.append(BROW)
    o = bpy.data.objects.new(name, cu)
    scene.collection.objects.link(o)
    return o

# Eyes: cream ellipsoids set into the head, plum pupils looking at the viewer.
GAZE = Vector((0, -1, 0))
if VARIANT == "wide":
    EYE_POS, GAZE_W = (px(430, 262), px(652, 266)), 0.25   # further round the head
else:
    EYE_POS, GAZE_W = (px(452, 262), px(630, 266)), 0.8
for name, (ex, ez), inward in (("eyeL", EYE_POS[0], 1), ("eyeR", EYE_POS[1], -1)):
    loc, n = surface(ex, ez)
    n = (n + GAZE * GAZE_W).normalized()              # turned with the head's curve
    turn = Vector((0, -1, 0)).rotation_difference(n)
    centre = loc - n * 0.062                           # seated: ~2 cm of dome shows
    def oriented(nm, offset, size, mat, sub=2, seg=48, rings=24):
        o = ellipsoid(nm, (0, 0, 0), size, seg=seg, rings=rings)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = turn
        o.location = centre + turn @ Vector(offset)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        return finish(o, mat, sub)
    EYE = (0.12, 0.082, 0.112)
    oriented(name, (0, 0, 0), EYE, CREAM)
    # Pupils sit toward the nose so both eyes meet the viewer's gaze.
    oriented(name + "_pupil", (inward * 0.016, -0.076, 0.004), (0.068, 0.02, 0.073), PLUM, sub=1)
    oriented(name + "_glint", (inward * 0.016 + 0.028, -0.094, 0.032), (0.018, 0.006, 0.019), GLINT, sub=1, seg=24, rings=12)
    lid_pts = []
    for i in range(9):
        t = math.radians(18 + 144 * i / 8)
        # Walk inward from the eye's rim until the eye surface is in front of the skin:
        # that is the visible seam the lid line should follow.
        for r in [1.0 - 0.01 * k for k in range(50)]:
            lx, lz = math.cos(t) * EYE[0] * r, math.sin(t) * EYE[2] * r
            ly = -EYE[1] * math.sqrt(max(0.0, 1 - r * r))
            pt = centre + turn @ Vector((lx, ly, lz))
            hit, sk, _, _ = body.ray_cast(Vector((pt.x, -2, pt.z)), Vector((0, 1, 0)))
            if not hit or pt.y < sk.y - 0.001:
                break
        lid_pts.append(pt + turn @ Vector((0, -0.003, 0.004)))
    lid_curve(name + "_lid", lid_pts)
    oriented(name + "_glint2", (inward * 0.016 - 0.026, -0.092, -0.028), (0.008, 0.004, 0.008), GLINT, sub=1, seg=16, rings=8)

# Eyebrows: short plum arcs following the forehead.
def brow(name, x0, x1, z, lift):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.017
    cu.bevel_resolution = 6
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    pts = []
    for i in range(7):
        t = i / 6
        x = x0 + (x1 - x0) * t
        zz = z + lift * math.sin(math.pi * t)
        loc, n = surface(x, zz)
        pts.append(loc + n * 0.006)
    sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts):
        p.co = (*c, 1)
    sp.use_endpoint_u = True
    sp.order_u = 4
    o = bpy.data.objects.new(name, cu)
    scene.collection.objects.link(o)
    cu.materials.append(BROW)
    # Taper both ends.
    tap = bpy.data.curves.new(name + "_taper", "CURVE")
    tsp = tap.splines.new("BEZIER")
    tsp.bezier_points.add(2)
    for bp, co in zip(tsp.bezier_points, ((0, 0.45, 0), (0.5, 1.0, 0), (1, 0.45, 0))):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    tobj = bpy.data.objects.new(name + "_taper", tap)
    scene.collection.objects.link(tobj)
    tobj.hide_render = True
    cu.taper_object = tobj
    return o

brow("browL", *[px(416, 0)[0], px(474, 0)[0]], px(0, 172)[1], 0.022)
brow("browR", *[px(618, 0)[0], px(676, 0)[0]], px(0, 178)[1], 0.022)

# Collar with a cream medallion.
cz = px(0, 410)[1]
# Measure the neck front-to-back (a side ray would hit the T-posed arms) and keep the
# collar's footprint proportional to the torso.
ry = -body.ray_cast(Vector((0, -2, cz)), Vector((0, 1, 0)))[1].y
rx = ry * 1.12
bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.026 / rx, major_segments=96, minor_segments=24,
                                 location=(0, 0.0, cz))
collar = bpy.context.object
collar.name = "collar"
collar.scale = (rx + 0.004, ry + 0.004, rx * 0.9)
bpy.ops.object.transform_apply(scale=True)
finish(collar, COLLAR, sub=1)
cfront, _ = surface(0, px(0, 412)[1])
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.045, depth=0.022, location=(0, -(ry + 0.004) - 0.03, px(0, 427)[1]),
                                    rotation=(math.pi / 2, 0, 0))
medal = bpy.context.object
medal.name = "medallion"
bev = medal.modifiers.new("bevel", "BEVEL")
bev.width = 0.008
bev.segments = 6
bev.harden_normals = True
medal.data.materials.append(MEDAL)
for p in medal.data.polygons:
    p.use_smooth = True

# ------------------------------------------------------------------ studio + renders

world = bpy.data.worlds.new("studio")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.2

def area(name, loc, energy, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, "AREA")
    l.energy, l.size, l.color = energy, size, color
    o = bpy.data.objects.new(name, l)
    scene.collection.objects.link(o)
    o.location = loc
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = (Vector((0, 0, 0.55)) - Vector(loc)).to_track_quat("-Z", "Y")

# Key-to-fill around 5:1 so the head, cheeks and limbs read as round forms.
area("key", (-2.3, -1.9, 2.3), 165, 1.5, (1, 0.97, 0.93))
area("fill", (2.4, -2.4, 0.8), 32, 3.0, (0.93, 0.96, 1))
area("rim", (1.4, 2.3, 2.2), 140, 1.2)
area("bounce", (0, -1.5, -0.6), 12, 2.0, (1, 0.98, 0.95))

# Seamless white cyclorama floor so the character grounds with a soft shadow.
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
floor = bpy.context.object
floor.data.materials.append(material("floor", (0.97, 0.97, 0.97), rough=0.8))
floor.is_shadow_catcher = True

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.cycles.device = "GPU"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
prefs.get_devices()
for d in prefs.devices:
    d.use = True
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "Medium Contrast"
scene.view_settings.exposure = -0.1
scene.render.film_transparent = True

def shot(name, loc, target=(0, 0, 0.55), ortho=None, res=(1000, 1000), lens=85):
    cam.location = loc
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y")
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)

shot("front", (0.006, -6, 0.565), target=(0.006, 0, 0.565), ortho=570 / 487)
shot("side", (-6, 0, 0.565), target=(0, 0, 0.565), ortho=570 / 487)
shot("threequarter", (1.7, -3.4, 1.15), target=(0, 0, 0.56), lens=55, res=(1000, 1100))
shot("face", (0.02, -6, 0.75), target=(0.02, 0, 0.75), ortho=0.92, res=(1000, 700))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "bop.blend"))
print("BOP_STATS", len(body.data.vertices), len(body.data.polygons))

# ------------------------------------------------------------------ topology inspection

def flat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*srgb(rgb), 1)
    return m

def wire_of(src, name, thickness):
    w = src.copy(); w.data = src.data.copy(); w.name = name
    scene.collection.objects.link(w)
    for mod in list(w.modifiers):
        w.modifiers.remove(mod)
    w.data.materials.clear(); w.data.materials.append(flat(name + "_m", (0.08, 0.05, 0.12)))
    wm = w.modifiers.new("wire", "WIREFRAME"); wm.thickness = thickness; wm.use_even_offset = True
    w.hide_render = False
    return w

if "topology" in args:
    topo_dir = os.path.join(out_dir, "topology"); os.makedirs(topo_dir, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.film_transparent = False
    world.color = (1, 1, 1)
    SKIN.diffuse_color = (*srgb((0.62, 0.86, 0.7)), 1)
    for m, c in ((CREAM, (0.99, 0.95, 0.86)), (PLUM, (0.3, 0.1, 0.22)), (BROW, (0.33, 0.12, 0.25)),
                 (MOUTH, (0.29, 0.09, 0.2)), (TONGUE, (0.95, 0.47, 0.42)), (TOOTH, (0.99, 0.96, 0.88)),
                 (COLLAR, (0.93, 0.44, 0.38)), (MEDAL, (0.98, 0.93, 0.8))):
        m.diffuse_color = (*srgb(c), 1)
    floor.hide_render = True
    cage_wire = wire_of(cage, "cage_wire", 0.0011)
    final_wire = wire_of(body, "final_wire", 0.0005)

    def topo(name, show, loc, target, scale, res=(1200, 1200)):
        for o in (body, cage, cage_wire, final_wire):
            o.hide_render = o not in show
        shot(name, loc, target=target, ortho=scale, res=res)
        os.replace(os.path.join(out_dir, name + ".png"), os.path.join(topo_dir, name + ".png"))

    fz = px(0, 262)[1]
    topo("cage-face", (cage, cage_wire), (0, -6, fz), (0, 0, fz - 0.05), 0.75)
    topo("final-mouth", (body, final_wire), (mx, -6, mz + 0.03), (mx, 0, mz + 0.03), 0.42)
    topo("cage-shoulder", (cage, cage_wire), (0.25, -6, SHOULDER_Z), (0.25, 0, SHOULDER_Z), 0.42)
    topo("cage-hip", (cage, cage_wire), (1.6, -5.2, 0.5), (0.05, 0, 0.16), 0.5)
    topo("cage-side-head", (cage, cage_wire), (-6, 0, fz), (0, 0, fz), 0.8)
    for o in (cage_wire, final_wire):
        o.hide_render = True
    cage.hide_render = True
    body.hide_render = False

# ------------------------------------------------------------------ stage preview
# Rebuilds the app's stage (StageDirector.swift) and turn-screen camera so Bop can be
# judged at the size it will appear in play. App coords (y up, +z to camera) map to
# Blender as (x, -z, y).

if "stage" in args:
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.render.film_transparent = False
    floor.hide_render = True
    for o in scene.objects:
        if o.type == "LIGHT":
            o.hide_render = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb((0.27, 0.19, 0.43)), 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

    rig = bpy.data.objects.new("BopRig", None); scene.collection.objects.link(rig)
    for o in list(scene.objects):
        if o.type in {"MESH", "CURVE"} and o not in {floor, cage} and o.parent is None and not o.name.endswith("_taper"):
            o.parent = rig
    rig.location = (0, -0.25, 0)
    rig.scale = (1.0, 1.0, 1.0)         # same on-screen height as Pip in the turn screen

    stage_m = material("stage", (0.16, 0.1, 0.3), rough=0.45, coat=0.3)
    top_m = material("stageTop", (0.36, 0.31, 0.46), rough=0.55, coat=0.15)
    bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=1.9, depth=0.3, location=(0, 0, -0.16))
    finish(bpy.context.object, stage_m, sub=0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=1.45, depth=0.04, location=(0, 0, 0.0))
    finish(bpy.context.object, top_m, sub=0)
    ring_m = material("ring", (0.62, 0.9, 0.2))
    ring_m.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (*srgb((0.62, 0.9, 0.2)), 1)
    ring_m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3
    bpy.ops.mesh.primitive_torus_add(major_radius=1.62, minor_radius=0.022, major_segments=128, location=(0, 0, 0.0))
    finish(bpy.context.object, ring_m, sub=0)

    sun = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN")); scene.collection.objects.link(sun)
    sun.data.energy = 3.2; sun.data.color = (1, 0.95, 0.9); sun.data.angle = math.radians(6)
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = (Vector((0, 0, 0.4)) - Vector((1.6, -3, 4))).to_track_quat("-Z", "Y")
    for nm, loc, col, w in (("rimP", (-1.8, 2.2, 2.2), (0.55, 0.35, 1), 300), ("fillC", (2.4, 1.2, 1.2), (0.3, 0.85, 1), 150)):
        l = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "POINT")); scene.collection.objects.link(l)
        l.location = loc; l.data.color = col; l.data.energy = w; l.data.shadow_soft_size = 0.3

    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(38)
    cam.location = (0, -6.0, 1.2)
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector((0, 0, 0.02)) - cam.location).to_track_quat("-Z", "Y")
    cam.data.dof.use_dof = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.render.resolution_x, scene.render.resolution_y = 1206, 2622
    scene.render.filepath = os.path.join(out_dir, "stage-raw.png")
    bpy.ops.render.render(write_still=True)
