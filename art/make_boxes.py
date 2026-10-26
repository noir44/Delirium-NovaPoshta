# Blender (5.x) batch: vanilla parcel meshes -> our boxes.
#   blender -b --factory-startup --python make_boxes.py -- <vanilla_fbx_dir> <tex_dir> <out_dir>
# For each box: import the vanilla FBX, re-UV it to the atlas of
# make_box_texture.ps1, export <out>/models_X/WorldItems/<name>.fbx,
# re-import it and check the geometry matches the vanilla mesh, and render
# the inventory icon <out>/icons/<name>.png (256 px, downscaled later).
import bpy, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
VAN, TEX, OUT = args[0], args[1], args[2]

# box name -> (vanilla mesh, texture file)
BOXES = {
    'DelNP_Box5':  ('Parcel4_Text',     'tex5.png'),
    'DelNP_Box10': ('Parcel2_Text',     'tex10.png'),
    'DelNP_Box25': ('Parcel_Present_1', 'tex25.png'),
}

# atlas cell (col,row), cells are 1/3 x 1/2 of the texture, row 0 on top
def cell_uv(col, row, un, vn):
    return ((col + un) / 3.0, 1.0 - (row + (1.0 - vn)) / 2.0)

def face_map(n, p, lo, hi):
    sz = hi - lo
    q = [(p[i] - lo[i]) / sz[i] for i in range(3)]   # 0..1 in the box
    ax = max(range(3), key=lambda i: abs(n[i]))
    s = n[ax] > 0
    if ax == 0:   # looking at +X from outside, right is +Y; at -X right is -Y
        return cell_uv(0 if s else 1, 0, q[1] if s else 1 - q[1], q[2])
    if ax == 1:   # +Y: right is -X; -Y: right is +X
        return cell_uv(0 if s else 1, 1, 1 - q[0] if s else q[0], q[2])
    return cell_uv(2, 0 if s else 1, q[0], q[1] if s else 1 - q[1])

def import_mesh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before and o.type == 'MESH'][0]

def world_verts(o):
    return sorted(tuple(round(c, 5) for c in (o.matrix_world @ v.co)) for v in o.data.vertices)

def material(name, tex):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    img = nt.nodes.new('ShaderNodeTexImage')
    img.image = bpy.data.images.load(tex)
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 0.9
    nt.links.new(img.outputs['Color'], bsdf.inputs['Base Color'])
    return m

os.makedirs(os.path.join(OUT, 'models_X', 'WorldItems'), exist_ok=True)
os.makedirs(os.path.join(OUT, 'icons'), exist_ok=True)

for name, (van, texname) in BOXES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    o = import_mesh(os.path.join(VAN, van + '.fbx'))
    ref = world_verts(o)
    me = o.data
    lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
    uv = me.uv_layers.active
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = face_map(poly.normal, p, lo, hi)
    me.materials.clear()
    me.materials.append(material(name, os.path.join(TEX, texname)))
    o.name = name; me.name = name

    fbx = os.path.join(OUT, 'models_X', 'WorldItems', name + '.fbx')
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, object_types={'MESH'},
                             path_mode='STRIP', bake_anim=False)

    # round trip: geometry must be the vanilla one
    o2 = import_mesh(fbx)
    ok = world_verts(o2) == ref
    print('CHECK', name, 'geometry matches vanilla:', ok, 'dims', tuple(round(d, 4) for d in o2.dimensions))
    bpy.data.objects.remove(o2)

    # icon render: 3/4 view from above, transparent background
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'; sc.cycles.samples = 64
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new('w'); sc.world = w
    w.use_nodes = True; w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'
    corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
    ctr = sum(corners, Vector()) / 8
    d = max(o.dimensions)
    cam.location = ctr + Vector((-1.0, -1.35, 1.05)).normalized() * 3.0
    cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = d * 1.45
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    sun.data.energy = 3.0; sun.rotation_euler = (math.radians(40), math.radians(-25), math.radians(-30))
    sc.collection.objects.link(sun)
    sc.render.filepath = os.path.join(OUT, 'icons', name + '.png')
    bpy.ops.render.render(write_still=True)
