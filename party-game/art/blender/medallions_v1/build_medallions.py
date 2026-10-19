"""Original Sunny Loop medallion kit. Blender 4.5; dimensions in studs, exported at .28m/stud.
Creates only this version's new directory; refuses to overwrite a saved source.
"""
import bpy, bmesh, math, json, os, sys, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(sys.argv[sys.argv.index('--')+1])
SOURCE=ROOT/'art/blender/medallions_v1'
OUT=ROOT/'art/export/medallions_v1'
SOURCE.mkdir(parents=True,exist_ok=True); OUT.mkdir(parents=True,exist_ok=True)
assert not (SOURCE/'SunnyLoop_Medallions_v1.blend').exists(), 'Version already exists'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
STUD=.28
palette=[(.70,.58,.41,1),(.82,.72,.55,1),(.88,.80,.65,1),(.73,.55,.23,1),(.50,.38,.23,1),(.94,.88,.72,1)]
# Original flat palette atlas, authored inside Blender, no external imagery.
im=bpy.data.images.new('SunnyLoop_Medallion_Atlas_v1',width=512,height=512,alpha=False)
pixels=[]
for y in range(512):
 for x in range(512): pixels.extend(palette[min(5,x//85)])
im.pixels=pixels; im.filepath_raw=str(OUT/'SunnyLoop_Medallion_Atlas_v1.png');im.file_format='PNG';im.save()
mat=bpy.data.materials.new('SunnyLoop_Medallion_StoneGold_v1');mat.use_nodes=True
node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;node.interpolation='Closest'
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.72
mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
plain=bpy.data.materials.new('SunnyLoop_Medallion_Tint_v1');plain.diffuse_color=(.88,.80,.65,1);plain.use_nodes=True
plain.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.88,.80,.65,1)
plain.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.7
objects=[];records=[]
def mesh(name,verts,faces,colors=None):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 obj=bpy.data.objects.new(name,me);scene.collection.objects.link(obj);objects.append(obj)
 me.materials.append(mat if colors else plain)
 uv=me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  idx=colors[p.index] if colors else 5
  for li in p.loop_indices:uv.data[li].uv=((idx*85+42)/512,.5)
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 for v in me.vertices:v.co*=STUD
 obj.location=(0,0,0);return obj
# Continuous radial section; no overlapping discs, no internal faces.
n=24
profile=[(5.12,0),(5.65,.08),(5.84,.20),(5.74,.72),(5.53,.86),(5.40,1.12),(4.12,1.12),(3.95,.86)]
v=[(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),z) for r,z in profile for i in range(n)]
f=[];colors=[]
for j in range(len(profile)-1):
 for i in range(n): f.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i));colors.append(3 if j==3 else (4 if j==6 else (1+(i%5==0) if j==5 else 1)))
f += [tuple(reversed(range(n))),tuple(range((len(profile)-1)*n,len(profile)*n))];colors +=[0,4]
mesh('SunnyLoop_Space_Base_v1',v,f,colors)
def polygon(name,points,z=.91,h=.29):
 # Two perimeter loops with triangulated caps. Slightly inset top gives a modeled bevel.
 count=len(points);v=[(x,y,z) for x,y in points]+[(x*.96,y*.96,z+h) for x,y in points]
 f=[tuple(reversed(range(count))),tuple(range(count,2*count))]
 f += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
 return mesh(name,v,f)
def circle(r,n=20):return [(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n)) for i in range(n)]
polygon('SunnyLoop_Space_Inlay_Dot_v1',circle(1.6))
polygon('SunnyLoop_Space_Inlay_Circle_v1',circle(3.7))
polygon('SunnyLoop_Space_Inlay_Diamond_v1',[(0,-3.9),(3.9,0),(0,3.9),(-3.9,0)])
polygon('SunnyLoop_Space_Inlay_Square_v1',[(-2.6,-3),(2.6,-3),(3,-2.6),(3,2.6),(2.6,3),(-2.6,3),(-3,2.6),(-3,-2.6)])
# Ring: ten-sided outer/inner bevel walls; exactly80 triangles, open centre reveals stone bed.
v=[]
for r,z in [(3.8,.91),(3.65,1.2),(2.3,1.2),(2.3,.91)]:v += [(x,y,z) for x,y in circle(r,10)]
f=[]
for j in range(4):
 for i in range(10):f.append((j*10+i,j*10+(i+1)%10,((j+1)%4)*10+(i+1)%10,((j+1)%4)*10+i))
mesh('SunnyLoop_Space_Inlay_Ring_v1',v,f)
# Original thick silhouettes, not font outlines or copyrighted icons. Bottom1.24, top1.38.
# Gain/Lose use up/down coin arrows; changing numeric reward stays Roblox text.
symbols={
'Gain':[(-.4,-1.5),(.4,-1.5),(.4,.35),(1.25,.35),(0,1.65),(-1.25,.35),(-.4,.35)],
'Lose':[(-.4,1.5),(-.4,-.35),(-1.25,-.35),(0,-1.65),(1.25,-.35),(.4,-.35),(.4,1.5)],
'Event':[(-1.2,.9),(-.65,1.55),(.65,1.55),(1.25,.9),(1.25,.25),(.4,-.35),(.4,-.8),(-.35,-.8),(-.35,.1),(.5,.65),(.5,.85),(-.45,.85),(-.65,.5)],
'Shop':[(-1.6,-1.35),(1.6,-1.35),(1.6,.6),(1.85,.6),(1.3,1.5),(-1.3,1.5),(-1.85,.6),(-1.6,.6)],
'Item':[(-1.35,-1.3),(1.35,-1.3),(1.65,-.75),(1.3,.85),(.65,1.0),(.5,1.5),(-.5,1.5),(-.65,1),(-1.3,.85),(-1.65,-.75)],
'Duel':[(-1.5,-1.2),(-.9,-1.65),(0,-.55),(.9,-1.65),(1.5,-1.2),(.55,0),(1.65,1.1),(1.65,1.7),(1.05,1.65),(0,.55),(-1.05,1.65),(-1.65,1.7),(-1.65,1.1),(-.55,0)],
'Chaos':[(-.6,1.7),(.8,1.7),(.15,.35),(1.2,.35),(-.8,-1.7),(-.25,-.25),(-1.1,-.25)],
'Switch':[(-1.8,.7),(-.7,1.6),(-.7,1.1),(1.6,1.1),(1.6,.35),(-.7,.35),(-.7,-.1)],
'Reward':[(-1.5,-1.4),(1.5,-1.4),(1.5,.65),(.7,.65),(1.2,1.3),(.6,1.65),(0,1.05),(-.6,1.65),(-1.2,1.3),(-.7,.65),(-1.5,.65)]}
for key,pts in symbols.items():
 o=polygon('SunnyLoop_Space_Symbol_'+key+'_v1',pts,1.24,.14)
 if key in ('Event','Switch'):
  pts2=circle(.32,8) if key=='Event' else [(-x,-y) for x,y in pts]
  extra=polygon('_extra',[(x,y-1.35) for x,y in pts2] if key=='Event' else pts2,1.24,.14)
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);extra.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.join();objects.remove(extra)
# Validation, explicit triangulation, applied transforms, export per stable name.
for o in objects:
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 bm=bmesh.new();bm.from_mesh(o.data)
 bad=sum(not e.is_manifold for e in bm.edges)
 assert bad==0,(o.name,'non-manifold',bad)
 bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
 tris=len(o.data.polygons);limit=500 if '_Base_' in o.name else 80 if '_Inlay_' in o.name else 200
 assert tris<=limit,(o.name,tris,limit)
 coords=[v.co/STUD for v in o.data.vertices];lo=[min(v[a] for v in coords) for a in range(3)];hi=[max(v[a] for v in coords) for a in range(3)]
 records.append(dict(name=o.name,triangles=tris,material_count=len(o.data.materials),texture_dimensions=[512,512] if '_Base_' in o.name else None,pivot_studs=[0,0,0],bounds_blender_studs=[lo,hi],collision='none; retain existing 10.5-stud collider',non_manifold_edges=bad))
 bpy.ops.export_scene.fbx(filepath=str(OUT/(o.name+'.fbx')),use_selection=True,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',use_mesh_modifiers=True,mesh_smooth_type='FACE',bake_anim=False,path_mode='COPY',embed_textures=True)
 bpy.ops.export_scene.gltf(filepath=str(OUT/(o.name+'.glb')),use_selection=True,export_format='GLB')
# Batch import keeps separate reusable meshes and their shared origin.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(filepath=str(OUT/'SunnyLoop_MedallionKit_v1.fbx'),use_selection=True,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',bake_anim=False,path_mode='COPY',embed_textures=True)
# Source all origin-aligned: assembled layers never moved for export. Preview copies only.
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'SunnyLoop_Medallions_v1.blend'))
(OUT/'manifest.json').write_text(json.dumps(dict(version=1,units='0.28m per stud',forward='Blender +Y / Roblox -Z',layers={'base_top':1.12,'bed_top':.86,'insert_bottom':.91,'insert_top':1.2,'symbol_bottom':1.24,'symbol_top':1.38},assets=records),indent=2))
print('MEDALLION_VALIDATION',json.dumps(records))
