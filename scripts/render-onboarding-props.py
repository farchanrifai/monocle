"""Clay prop renders for the Ankka onboarding, in Blender.
Usage: /Applications/Blender.app/Contents/MacOS/Blender -b -P scripts/render-onboarding-props.py -- <slot> <out.png> [dark]
Output goes into Ankka/Resources/Assets.xcassets/Onboarding/<slot>.imageset (<slot>.png, <slot>-dark.png).

Tone-on-tone by construction: every surface's lighting is mapped through the step's palette ramp
(deep → side → mid → face → light → hi), so shading only ever uses the palette's own colours."""
import bpy, bmesh, math, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
SLOT, OUT = argv[0], argv[1]
DARK = len(argv) > 2 and argv[2] == 'dark'
FONT = '/Library/Fonts/SF-Pro-Rounded-Black.otf'

# hi, light, base (face), mid, shade (side), deep, shadow — from IntroPalette.
PALETTES = {
    (1, False): ['FFD4C7', 'FEA48C', 'FF7F62', 'EB553C', 'C7372B', '930C18', '4B020B'],
    (1, True): ['E2714E', 'A0381B', '761B05', '5F0D01', '440101', '2C0002', '070000'],
    (2, False): ['FFF6E4', 'FFE1AC', 'FFC561', 'EAA40F', 'C78711', '98620B', '603901'],
    (2, True): ['CE8B32', '8B5606', '633A03', '4F2C02', '381C01', '260F00', '050100'],
    (3, False): ['EBF9CE', 'C1DF87', 'A7CC66', '87B147', '669432', '3D6C1A', '1B3D0C'],
    (3, True): ['70AE69', '3D7231', '275115', '1B4001', '152B00', '0E1A00', '010200'],
    (4, False): ['E4F4FF', 'A3D8FE', '79C4FC', '5CA7E2', '4788C1', '2E6093', '183354'],
    (4, True): ['5D9FC9', '28658C', '114567', '023455', '00223D', '00132A', '000207'],
    (5, False): ['EFE7FF', 'D1BFFE', 'BDA6FB', '9F8AE0', '7E6FBF', '554D91', '2A2752'],
    (5, True): ['A088CC', '66528E', '463669', '352757', '221742', '120B2F', '02000D'],
    (6, False): ['E79B88', 'D0503C', 'B1281E', '90080E', '6D0410', '4A010B', '140001'],
    (6, True): ['CD5F48', '8B2516', '620402', '490003', '2C0002', '150001', '070000'],
}

def lin(hex6):
    c = [int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1]

# ---------------------------------------------------------------- scene

def reset(width, height):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    try:
        scene.eevee.taa_render_samples = 64
        scene.eevee.use_shadows = True
        scene.eevee.shadow_ray_count = 3
        scene.eevee.shadow_step_count = 12
    except AttributeError:
        pass
    world = bpy.data.worlds.new('w')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (1, 1, 1, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.06
    scene.world = world
    # One light rig for every prop: big soft key from the top left, 30% fill from the right, rim from the back right.
    for name, rot, strength, angle in (('key', (60, 0, -35), 3.3, 28), ('fill', (70, 0, 75), 0.35, 50), ('rim', (110, 0, 150), 1.3, 15)):
        light = bpy.data.lights.new(name, 'SUN')
        light.energy = strength
        light.angle = math.radians(angle)
        obj = bpy.data.objects.new(name, light)
        obj.rotation_euler = [math.radians(a) for a in rot]
        scene.collection.objects.link(obj)
    return scene

def clay(pal, name='clay', base=2, gloss=0.35, bump=None, tone=1.0, soft=False):
    """Lighting → palette ramp, plus a satin highlight lifted toward the hi tone."""
    hi, lt, face, mid, side, deep, _ = pal
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    n, links = nt.nodes, nt.links
    n.clear()
    out = n.new('ShaderNodeOutputMaterial')
    diffuse = n.new('ShaderNodeBsdfDiffuse')
    to_rgb = n.new('ShaderNodeShaderToRGB')
    bw = n.new('ShaderNodeRGBToBW')
    ao = n.new('ShaderNodeAmbientOcclusion'); ao.inputs['Distance'].default_value = 0.25
    mul = n.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'
    aomix = n.new('ShaderNodeMapRange'); aomix.inputs['To Min'].default_value = 0.4
    ramp = n.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'B_SPLINE'
    stops = [(0.0, mid), (0.4, face), (0.72, lt), (1.0, hi)] if soft else [(0.0, deep), (0.18, side), (0.36, mid), (0.54, face), (0.7, lt), (0.9, hi)]
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], lin(stops[0][1])
    els[1].position, els[1].color = stops[-1][0], lin(stops[-1][1])
    for pos, col in stops[1:-1]:
        e = els.new(pos); e.color = lin(col)
    glossy = n.new('ShaderNodeBsdfGlossy'); glossy.inputs['Roughness'].default_value = 0.32
    g_rgb = n.new('ShaderNodeShaderToRGB')
    g_bw = n.new('ShaderNodeRGBToBW')
    g_map = n.new('ShaderNodeMapRange')
    g_map.inputs['From Min'].default_value, g_map.inputs['From Max'].default_value = 0.35, 1.2
    g_map.inputs['To Max'].default_value = gloss
    add = n.new('ShaderNodeMix'); add.data_type = 'RGBA'; add.blend_type = 'ADD'
    emit = n.new('ShaderNodeEmission')
    if bump:
        bump_node = bump(n, links)
        links.new(bump_node.outputs['Normal'], diffuse.inputs['Normal'])
        links.new(bump_node.outputs['Normal'], glossy.inputs['Normal'])
    links.new(diffuse.outputs[0], to_rgb.inputs[0])
    links.new(to_rgb.outputs['Color'], bw.inputs[0])
    links.new(ao.outputs['AO'], aomix.inputs['Value'])
    links.new(bw.outputs[0], mul.inputs[0])
    links.new(aomix.outputs[0], mul.inputs[1])
    toned = n.new('ShaderNodeMath'); toned.operation = 'MULTIPLY'; toned.inputs[1].default_value = tone; toned.use_clamp = True
    links.new(mul.outputs[0], toned.inputs[0])
    links.new(toned.outputs[0], ramp.inputs['Fac'])
    links.new(glossy.outputs[0], g_rgb.inputs[0])
    links.new(g_rgb.outputs['Color'], g_bw.inputs[0])
    links.new(g_bw.outputs[0], g_map.inputs['Value'])
    links.new(g_map.outputs[0], add.inputs['Factor'])
    links.new(ramp.outputs['Color'], add.inputs['A'])
    add.inputs['B'].default_value = lin(hi)
    links.new(add.outputs['Result'], emit.inputs['Color'])
    links.new(emit.outputs[0], out.inputs['Surface'])
    return mat

def reeds(count=90, strength=0.6):
    """Bump for a reeded coin edge: ridges around the circumference, only where the surface faces sideways."""
    def build(n, links):
        coord = n.new('ShaderNodeTexCoord')
        sep = n.new('ShaderNodeSeparateXYZ')
        atan = n.new('ShaderNodeMath'); atan.operation = 'ARCTAN2'
        scale = n.new('ShaderNodeMath'); scale.operation = 'MULTIPLY'; scale.inputs[1].default_value = count
        sine = n.new('ShaderNodeMath'); sine.operation = 'SINE'
        geo = n.new('ShaderNodeNewGeometry')
        nsep = n.new('ShaderNodeSeparateXYZ')
        absz = n.new('ShaderNodeMath'); absz.operation = 'ABSOLUTE'
        side = n.new('ShaderNodeMath'); side.operation = 'LESS_THAN'; side.inputs[1].default_value = 0.3
        mask = n.new('ShaderNodeMath'); mask.operation = 'MULTIPLY'
        bump = n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = strength; bump.inputs['Distance'].default_value = 0.02
        links.new(coord.outputs['Object'], sep.inputs[0])
        links.new(sep.outputs['Y'], atan.inputs[0]); links.new(sep.outputs['X'], atan.inputs[1])
        links.new(atan.outputs[0], scale.inputs[0]); links.new(scale.outputs[0], sine.inputs[0])
        links.new(geo.outputs['Normal'], nsep.inputs[0])
        vt = n.new('ShaderNodeVectorTransform'); vt.vector_type = 'NORMAL'; vt.convert_from = 'WORLD'; vt.convert_to = 'OBJECT'
        links.new(geo.outputs['Normal'], vt.inputs[0]); links.new(vt.outputs[0], nsep.inputs[0])
        links.new(nsep.outputs['Z'], absz.inputs[0]); links.new(absz.outputs[0], side.inputs[0])
        links.new(sine.outputs[0], mask.inputs[0]); links.new(side.outputs[0], mask.inputs[1])
        links.new(mask.outputs[0], bump.inputs['Height'])
        return bump
    return build

# ---------------------------------------------------------------- geometry helpers

def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj

def smooth(obj, angle=40):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for p in obj.data.polygons:
        p.use_smooth = True
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        pass
    obj.select_set(False)

def text(body, size=1, extrude=0.12, bevel=0.045, res=6):
    curve = bpy.data.curves.new('t', 'FONT')
    curve.body = body
    curve.font = bpy.data.fonts.load(FONT)
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = bevel
    curve.bevel_resolution = res
    curve.align_x, curve.align_y = 'CENTER', 'CENTER'
    curve.resolution_u = 24
    obj = link(bpy.data.objects.new('t', curve))
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    smooth(obj)
    return obj

def bevelled(obj, width, segments=5):
    mod = obj.modifiers.new('bevel', 'BEVEL')
    mod.width, mod.segments, mod.limit_method = width, segments, 'ANGLE'
    smooth(obj)
    return obj

def cylinder(radius, depth, verts=128):
    mesh = bpy.data.meshes.new('cyl')
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius, depth=depth)
    bm.to_mesh(mesh); bm.free()
    return link(bpy.data.objects.new('cyl', mesh))

def torus(major, minor, z=0):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=128, minor_segments=24, location=(0, 0, z))
    obj = bpy.context.active_object
    smooth(obj)
    return obj

def boolean(target, cutter, op='DIFFERENCE'):
    mod = target.modifiers.new('bool', 'BOOLEAN')
    mod.operation, mod.object = op, cutter
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter)

def join(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return objs[0]

def material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)

# ---------------------------------------------------------------- props

def coin(pal, glyph='a', tilt=55, tone=1.0):
    """Reeded coin with a raised rim, an engraved groove and an embossed glyph; `tilt` degrees back from face-on."""
    body = bevelled(cylinder(1, 0.2), 0.035)
    rim = torus(0.93, 0.05, 0.1)
    groove = torus(0.74, 0.028, 0.105)
    boolean(body, groove)
    parts = [body, rim]
    if glyph:
        mark = text(glyph, size=1.2, extrude=0.045, bevel=0.022, res=5)
        mark.location = (0, 0.04 if glyph == 'a' else 0, 0.1)
        parts.append(mark)
    obj = join(parts)
    material(obj, clay(pal, gloss=0.5, bump=reeds(), tone=tone))
    obj.rotation_euler = (math.radians(90 - tilt), 0, 0)
    return [obj]

def coin_stack(pal):
    objs = []
    for i, (dx, dy) in enumerate([(0.05, 0), (-0.06, 0.02), (0.02, -0.01)]):
        c = coin(pal, glyph='a' if i == 2 else None)[0]
        c.location = (dx, 0, i * 0.24)
        c.rotation_euler = (0, 0, 0)
        objs.append(c)
    group = join(objs)
    group.rotation_euler = (math.radians(35), 0, 0)
    return [group]

def numeral(pal, glyph):
    obj = text(glyph, size=1.6, extrude=0.15, bevel=0.032, res=8)
    material(obj, clay(pal, gloss=0.3))
    obj.rotation_euler = (math.radians(90), 0, math.radians(26))
    return [obj]


def rounded_rect(w, h, r, depth, n=10):
    """A rounded-rectangle slab in the XY plane, `depth` thick along Z."""
    pts = []
    for cx, cy, a0 in ((w/2 - r, h/2 - r, 0), (-w/2 + r, h/2 - r, 90), (-w/2 + r, -h/2 + r, 180), (w/2 - r, -h/2 + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), -depth / 2))
    mesh = bpy.data.meshes.new('rr')
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in pts]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=(0, 0, depth), verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    return link(bpy.data.objects.new('rr', mesh))

def box(w, h, d, loc=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.scale = (w, h, d)
    bpy.ops.object.transform_apply(scale=True)
    return o

def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o

def tube(points, radius, closed=False, res=6):
    curve = bpy.data.curves.new('tube', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth, curve.bevel_resolution = radius, res
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    spline.use_cyclic_u = closed
    o = link(bpy.data.objects.new('tube', curve))
    bpy.context.view_layer.objects.active = o
    o.select_set(True); bpy.ops.object.convert(target='MESH'); o.select_set(False)
    smooth(o)
    return o

def blob(balls, cut_below=None, res=0.04):
    mb = bpy.data.metaballs.new('mb')
    mb.resolution = mb.render_resolution = res
    for (x, y, z, r) in balls:
        e = mb.elements.new(); e.co = (x, y, z); e.radius = r
    o = link(bpy.data.objects.new('mb', mb))
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True); bpy.ops.object.convert(target='MESH')
    o = [ob for ob in bpy.context.scene.objects if ob.type == 'MESH'][-1]
    bpy.ops.object.select_all(action='DESELECT')
    smooth(o, 60)
    if cut_below is not None:
        boolean(o, box(20, 20, 10, (0, 0, cut_below - 5)))
    return o

def painted(o, pal, **kw):
    material(o, clay(pal, **kw))
    return o

def boarding_pass(pal):
    slab = rounded_rect(4.2, 1.9, 0.24, 0.07)
    for y in (0.95, -0.95):
        notch = cylinder(0.17, 1); notch.location = (1.05, y, 0); boolean(slab, notch)
    bevelled(slab, 0.025, 4)
    painted(slab, pal, tone=1.15, gloss=0.2)
    ink = clay(pal, tone=0.12, gloss=0.05)
    parts = [slab]
    label = text('CGK ✈ HND', size=0.66, extrude=0.012, bevel=0.004, res=2); label.location = (-0.45, 0.35, 0.04)
    material(label, ink); parts.append(label)
    for (x, y, w) in ((-1.25, -0.3, 0.9), (-0.05, -0.3, 0.6), (-1.1, -0.58, 1.2)):
        b = rounded_rect(w, 0.12, 0.06, 0.03); b.location = (x, y, 0.045); material(b, clay(pal, tone=0.55, gloss=0.1)); parts.append(b)
    for i in range(8):
        d = cylinder(0.05, 0.05, 16); d.location = (1.05, -0.63 + i * 0.18, 0.04); material(d, ink); parts.append(d)
    x, unit = 1.36, 0.021
    for w, gap in ((2, 1), (1, 1), (3, 2), (1, 1), (1, 2), (2, 1), (1, 1), (3, 1), (1, 2), (2, 1), (1, 1)):
        bar = box(unit * w, 1.15, 0.012, (x + unit * w / 2, 0, 0.04)); material(bar, ink); parts.append(bar)
        x += unit * (w + gap)
    o = join(parts)
    o.rotation_euler = (math.radians(70), 0, math.radians(-8))
    return [o]

def sunglasses(pal):
    hi, lt, face, mid, side, deep, shd = pal
    frame = clay(pal, tone=1.1, gloss=0.6)
    lens = clay([lt, face, mid, side, deep, deep, shd], tone=1.05 if DARK else 0.75, gloss=0.9)
    shine = clay(pal, tone=1.4, gloss=0.2)
    parts = []
    for x in (-0.62, 0.62):
        ring = tube([(x + 0.5 * math.cos(a), 0, 0.38 * math.sin(a)) for a in [i * math.pi / 8 for i in range(16)]], 0.075, closed=True)
        material(ring, frame); parts.append(ring)
        glass = cylinder(0.47, 0.04, 64); glass.scale = (1, 0.78, 1); glass.rotation_euler = (math.radians(90), 0, 0); glass.location = (x, 0.01, 0)
        apply_scale(glass); smooth(glass); material(glass, lens); parts.append(glass)
        for dx, w in ((-0.14, 0.07), (0.04, 0.035)):
            streak = rounded_rect(w, 0.5, w / 2, 0.02); streak.rotation_euler = (math.radians(90), math.radians(-35), 0); streak.location = (x + dx, -0.02, 0.02)
            material(streak, shine); parts.append(streak)
    bridge = tube([(-0.16, 0, 0.18), (0, 0, 0.27), (0.16, 0, 0.18)], 0.06); material(bridge, frame); parts.append(bridge)
    for sx in (-1, 1):
        arm = tube([(sx * 1.08, 0, 0.12), (sx * 1.14, 0.45, 0.1), (sx * 1.1, 0.9, 0.02)], 0.05); material(arm, frame); parts.append(arm)
    o = join(parts)
    o.rotation_euler = (math.radians(12), 0, math.radians(-6))
    return [o]

def apply_scale(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.select_set(False)

def cone(r1, r2, depth, z=0, verts=96):
    mesh = bpy.data.meshes.new('cone'); bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r1, radius2=r2, depth=depth)
    bm.to_mesh(mesh); bm.free()
    o = link(bpy.data.objects.new('cone', mesh)); o.location = (0, 0, z)
    return o

def kopi_cup(pal, steam=True):
    cupm = clay(pal, tone=1.05, gloss=0.25)
    sleevem = clay(pal, tone=0.62, gloss=0.2)
    parts = []
    cup = bevelled(cone(0.62, 0.86, 2.2, 0), 0.05); material(cup, cupm); parts.append(cup)
    sleeve = bevelled(cone(0.735, 0.83, 0.75, 0.1), 0.04); sleeve.scale = (1.03, 1.03, 1); apply_scale(sleeve); material(sleeve, sleevem); parts.append(sleeve)
    rim = bevelled(cylinder(0.95, 0.18), 0.06); rim.location = (0, 0, 1.15); material(rim, cupm); parts.append(rim)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.86, segments=64, ring_count=32, location=(0, 0, 1.2))
    dome = bpy.context.active_object; dome.scale = (1, 1, 0.42); apply_scale(dome); boolean(dome, box(4, 4, 2, (0, 0, 0.2)))
    smooth(dome); material(dome, cupm); parts.append(dome)
    sip = cylinder(0.11, 0.3, 32); sip.location = (0.35, -0.3, 1.5); material(sip, sleevem); parts.append(sip)
    if steam:
        for dx in (-0.25, 0.25):
            wisp = tube([(dx, 0, 1.7), (dx + 0.18, 0, 2.05), (dx - 0.1, 0, 2.4), (dx + 0.12, 0, 2.75)], 0.07)
            material(wisp, clay(pal, tone=1.3, gloss=0.1)); parts.append(wisp)
    o = join(parts)
    o.rotation_euler = (0, 0, math.radians(15))
    return o

def receipt(pal):
    paperm = clay(pal, tone=1.25, gloss=0.15)
    ink = clay(pal, tone=0.6, gloss=0.1)
    pts = [(-0.7, 1.2), (0.7, 1.2)]
    zig = [(0.7 - i * 0.14, -1.2 + (0.12 if i % 2 else 0)) for i in range(11)]
    poly = pts + zig
    mesh = bpy.data.meshes.new('paper'); bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x, y, 0)) for x, y in poly])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=(0, 0, 0.04), verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(mesh); bm.free()
    paper = bevelled(link(bpy.data.objects.new('paper', mesh)), 0.012, 3); material(paper, paperm)
    parts = [paper]
    roll = bevelled(cylinder(0.3, 1.6), 0.05); roll.rotation_euler = (0, math.radians(90), 0); roll.location = (0, 1.25, 0.25); material(roll, paperm); parts.append(roll)
    for i, w in enumerate((0.9, 0.7, 1.0)):
        b = rounded_rect(w, 0.09, 0.04, 0.02); b.location = (-0.55 + w / 2, 0.6 - i * 0.3, 0.04); material(b, ink); parts.append(b)
    amt = text('28rb', size=0.45, extrude=0.02, bevel=0.008, res=3); amt.location = (0.1, -0.45, 0.05); material(amt, ink); parts.append(amt)
    o = join(parts)
    o.rotation_euler = (math.radians(65), 0, math.radians(8))
    return [o]

def beans(pal):
    m = clay(pal, tone=0.95, gloss=0.55)
    parts = []
    for (x, y, sc, rz) in ((-0.45, 0, 1.0, -28), (0.55, 0.35, 0.8, 22)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=48, ring_count=24)
        b = bpy.context.active_object; b.scale = (0.72 * sc, 1.0 * sc, 0.48 * sc); apply_scale(b)
        smooth(b); material(b, m)
        crease = tube([(0.02 * sc, -0.4 * sc, 0.2 * sc), (0.08 * sc, 0, 0.245 * sc), (0.02 * sc, 0.4 * sc, 0.2 * sc)], 0.025 * sc)
        material(crease, clay(pal, tone=0.35, gloss=0.1))
        b = join([b, crease]); b.location = (x, y, 0); b.rotation_euler = (0, 0, math.radians(rz)); parts.append(b)
    o = join(parts)
    o.rotation_euler = (math.radians(55), 0, 0)
    return [o]

def kopi_chip(pal):
    tile = bevelled(rounded_rect(2.4, 2.4, 0.72, 0.3), 0.08); material(tile, clay(pal, tone=1.3, gloss=0.2))
    cup = kopi_cup(pal, steam=False); cup.scale = (0.5, 0.5, 0.5); cup.location = (0, -0.12, 0.55)
    cup.rotation_euler = (math.radians(-90), 0, 0)
    o = join([tile, cup])
    o.rotation_euler = (math.radians(90), 0, 0)
    return [o]

def cloud(pal, small=False):
    if small:
        balls = [(-0.55, 0, 0.0, 0.55), (0.1, 0, 0.25, 0.7), (0.7, 0, 0.02, 0.5), (0.05, 0, -0.18, 0.62)]
    else:
        balls = [(-1.05, 0, -0.05, 0.5), (-0.45, 0, 0.3, 0.7), (0.25, 0, 0.5, 0.82), (0.95, 0, 0.15, 0.6), (1.4, 0, -0.08, 0.42),
                 (-0.5, 0, -0.25, 0.6), (0.35, 0, -0.25, 0.65), (1.0, 0, -0.22, 0.45)]
    o = blob(balls, res=0.02)
    o.scale = (1, 0.8, 1)
    painted(o, pal, tone=1.15, gloss=0.02, soft=True)
    o.rotation_euler = (math.radians(8), 0, 0)
    return [o]

def paper_plane(pal):
    wing = clay(pal, tone=1.3, gloss=0.2); keel = clay(pal, tone=0.7, gloss=0.2)
    def tri(pts, m):
        mesh = bpy.data.meshes.new('tri'); bm = bmesh.new()
        bm.faces.new([bm.verts.new(p) for p in pts]); bm.to_mesh(mesh); bm.free()
        o = link(bpy.data.objects.new('tri', mesh)); so = o.modifiers.new('s', 'SOLIDIFY'); so.thickness = 0.03; apply_mods(o); bevelled(o, 0.01, 2); material(o, m); return o
    nose, tail = (1.6, 0, 0), -1.2
    parts = [tri([nose, (tail, 0.95, 0.42), (tail + 0.3, 0, 0)], wing), tri([nose, (tail, -0.95, 0.42), (tail + 0.3, 0, 0)], clay(pal, tone=0.95, gloss=0.2)),
             tri([nose, (tail + 0.3, 0, 0), (tail + 0.15, 0, -0.55)], keel)]
    o = join(parts)
    o.rotation_euler = (math.radians(18), math.radians(-18), math.radians(24))
    return [o]

def padlock(pal):
    bodym = clay(pal, tone=1.0, gloss=0.4); shacklem = clay(pal, tone=1.2, gloss=0.6); holem = clay(pal, tone=0.3, gloss=0.1)
    body = bevelled(rounded_rect(1.8, 1.45, 0.35, 0.75), 0.12, 6); body.rotation_euler = (math.radians(90), 0, 0); apply_scale(body); material(body, bodym)
    shackle = tube([(-0.55, 0, 0.6), (-0.55, 0, 1.15), (0, 0, 1.6), (0.55, 0, 1.15), (0.55, 0, 0.6)], 0.16); material(shackle, shacklem)
    key = cylinder(0.15, 0.2, 32); key.rotation_euler = (math.radians(90), 0, 0); key.location = (0, -0.33, 0.1); material(key, holem)
    slot = box(0.12, 0.2, 0.38, (0, -0.33, -0.15)); material(slot, holem)
    o = join([body, shackle, key, slot])
    o.rotation_euler = (0, 0, math.radians(-14))
    return [o]

def door_key(pal):
    m = clay(pal, tone=1.05, gloss=0.45)
    bow = bevelled(cylinder(0.55, 0.22, 64), 0.06); hole = cylinder(0.2, 1, 32); boolean(bow, hole); bow.location = (-1.0, 0, 0)
    shaft = bevelled(box(1.7, 0.26, 0.2, (0.3, 0, 0)), 0.05)
    t1 = bevelled(box(0.16, 0.38, 0.2, (0.8, -0.28, 0)), 0.04); t2 = bevelled(box(0.14, 0.26, 0.2, (1.05, -0.22, 0)), 0.04)
    o = join([bow, shaft, t1, t2]); material(o, m); smooth(o)
    o.rotation_euler = (math.radians(55), 0, math.radians(-8))
    return [o]

PROPS = {
    'prop-clay-8': (1, (396, 489), lambda p: numeral(p, '8')),
    'prop-clay-2': (1, (252, 312), lambda p: numeral(p, '2')),
    'prop-coin-tilt': (1, (258, 198), lambda p: coin(p)),
    'prop-coin-stack': (1, (234, 240), coin_stack),
    'prop-coin-face': (1, (96, 96), lambda p: coin(p, tilt=20, tone=0.84)),
    'prop-coin-tilt-marigold': (2, (192, 147), lambda p: coin(p)),
    'prop-coin-yen': (4, (138, 138), lambda p: coin(p, glyph='¥', tilt=15, tone=0.84)),
    'prop-boarding-pass': (2, (600, 297), boarding_pass),
    'prop-sunglasses': (2, (450, 225), sunglasses),
    'prop-kopi-cup': (3, (276, 390), lambda p: [kopi_cup(p)]),
    'prop-receipt-curl': (3, (204, 276), receipt),
    'prop-coffee-beans': (3, (174, 129), beans),
    'prop-kopi-chip': (3, (120, 120), kopi_chip),
    'prop-cloud': (4, (372, 213), lambda p: cloud(p)),
    'prop-cloud-small': (4, (252, 144), lambda p: cloud(p, small=True)),
    'prop-paper-plane': (4, (138, 102), paper_plane),
    'prop-padlock': (6, (216, 267), padlock),
    'prop-key': (6, (318, 165), door_key),
    'prop-clay-percent': (5, (228, 282), lambda p: numeral(p, '%')),
    'prop-coin-tilt-lilac': (5, (192, 147), lambda p: coin(p)),
}

# ---------------------------------------------------------------- camera and render

def frame(scene, objs, padding=0.06):
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam = bpy.data.objects.new('cam', cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    elevation = math.radians(15)
    cam.rotation_euler = (math.radians(90) - elevation, 0, 0)
    cam.location = (0, -20 * math.cos(elevation), 20 * math.sin(elevation))
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    pts = []
    for o in objs:
        dg = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
        for v in dg.to_mesh().vertices:
            pts.append(inv @ (o.matrix_world @ v.co))
        dg.to_mesh_clear()
    xs, ys = [p.x for p in pts], [p.y for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    ex, ey = max(xs) - min(xs), max(ys) - min(ys)
    rx, ry = scene.render.resolution_x, scene.render.resolution_y
    cam_data.ortho_scale = max(ex, ey * rx / ry) * (1 + 2 * padding) if rx >= ry else max(ex * ry / rx, ey) * (1 + 2 * padding)
    cam.location += cam.matrix_world.to_3x3() @ Vector((cx, cy, 0))

step, (w, h), build = PROPS[SLOT]
scene = reset(w, h)
objs = build(PALETTES[(step, DARK)])
frame(scene, objs)
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print('rendered', SLOT, OUT)
