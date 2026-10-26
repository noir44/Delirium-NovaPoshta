# Blender (5.x) batch: our box textures on the vanilla parcel meshes.
#   blender -b --factory-startup --python make_boxes.py -- <vanilla_fbx_dir> <tex_dir> <out_dir>
#
# The game uses the vanilla meshes as they are (no FBX of ours: a Blender
# export rendered as a flat icon in game). Our design is the 6-face atlas of
# make_box_texture.ps1; here it is baked into a texture laid out on the
# vanilla UVs:
#   out/textures/<name>.png      texture for the model script
#   out/icons/<name>.png         inventory icon, 256 px (downscale later)
#   out/check/<name>_back.png    render from the opposite side, to check that
#                                no side reads mirrored (vanilla opposite faces
#                                share one UV region)
import bpy, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
VAN, TEX, OUT = args[0], args[1], args[2]
SIZE = 512

# box name -> (vanilla mesh, atlas from make_box_texture.ps1)
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

for d in ('textures', 'icons', 'check'):
    os.makedirs(os.path.join(OUT, d), exist_ok=True)

for name, (van, texname) in BOXES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    o = import_mesh(os.path.join(VAN, van + '.fbx'))
    me = o.data
    vuv = me.uv_layers.active                  # vanilla UVs: bake target
    vname = vuv.name
    src = me.uv_layers.new(name='src')         # our atlas layout: bake source
    lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            src.data[li].uv = face_map(poly.normal, p, lo, hi)
    me.uv_layers.active = me.uv_layers[vname]

    # bake: emission from the atlas (via 'src') into an image on the vanilla UVs
    m = bpy.data.materials.new('bake')
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    uvn = nt.nodes.new('ShaderNodeUVMap'); uvn.uv_map = 'src'
    atlas = nt.nodes.new('ShaderNodeTexImage'); atlas.image = bpy.data.images.load(os.path.join(TEX, texname))
    emit = nt.nodes.new('ShaderNodeEmission')
    outn = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(uvn.outputs['UV'], atlas.inputs['Vector'])
    nt.links.new(atlas.outputs['Color'], emit.inputs['Color'])
    nt.links.new(emit.outputs['Emission'], outn.inputs['Surface'])
    img = bpy.data.images.new(name, SIZE, SIZE)
    target = nt.nodes.new('ShaderNodeTexImage'); target.image = img
    nt.nodes.active = target
    me.materials.clear(); me.materials.append(m)
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
    bpy.context.view_layer.objects.active = o
    sc.cycles.samples = 4
    sc.render.bake.margin = 8
    bpy.ops.object.bake(type='EMIT')
    img.filepath_raw = os.path.join(OUT, 'textures', name + '.png')
    img.file_format = 'PNG'
    img.save()

    # preview material: baked texture on the vanilla UVs (what the game will draw)
    me.uv_layers.remove(me.uv_layers['src'])
    pm = bpy.data.materials.new('preview')
    pn = pm.node_tree
    bsdf = pn.nodes['Principled BSDF']; bsdf.inputs['Roughness'].default_value = 0.9
    pt = pn.nodes.new('ShaderNodeTexImage'); pt.image = img
    pn.links.new(pt.outputs['Color'], bsdf.inputs['Base Color'])
    me.materials.clear(); me.materials.append(pm)

    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.view_settings.view_transform = 'Standard'
    sc.cycles.samples = 64
    w = bpy.data.worlds.new('w'); sc.world = w
    w.use_nodes = True; w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    sun.data.energy = 3.0
    sc.collection.objects.link(sun)
    corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
    ctr = sum(corners, Vector()) / 8
    cam.data.ortho_scale = max(o.dimensions) * 1.45

    def shot(direction, path):
        cam.location = ctr + Vector(direction).normalized() * 3.0
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sun.rotation_euler = (Vector(direction) + Vector((0.5, -0.3, 0.8))).to_track_quat('Z', 'Y').to_euler()
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)

    shot((-1.0, -1.35, 1.05), os.path.join(OUT, 'icons', name + '.png'))
    shot((1.0, 1.35, 1.05), os.path.join(OUT, 'check', name + '_back.png'))
    print('DONE', name)
