import bpy,sys,math,json,time,importlib,os
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(HERE))
import common
from common import OUT,camera
ROOT=HERE.parents[1];ASSETS=ROOT/'assets';ASSETS.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);common.setup_materials()
for p in ([Path(os.environ['HIDDEN_LEAF_FONT'])] if os.environ.get('HIDDEN_LEAF_FONT') else [])+list(Path('/System/Library/Fonts').glob('*Sans*'))+list(Path('/System/Library/Fonts').glob('*角*W3*')):
 try:common.text.font=bpy.data.fonts.load(str(p));break
 except:pass
scene=bpy.context.scene;scene.name='Konoha Shippuden · Explorer edition';scene.unit_settings.system='METRIC'
meta={'era':'Naruto Shippuden, pre-Pain','fidelity':'Reference-guided reconstruction. Unshown geography and exact dimensions are inferred.'}
for name,fn in [('iconic','build_iconic'),('districts','build_districts'),('landmarks','build_landmarks'),('landscape','build_landscape')]:
 print('BUILD',name,flush=True);mod=importlib.import_module(name);meta[name]=getattr(mod,fn)()
 if name=='landscape':meta['gardens']=mod.build_village_greenery(meta['districts']['buildings'])
# Shop forecourts and rear service lane meet the attached market buildings.
from iconic import _surface
market=common.Builder('Market lane · worn packed earth')
_surface(market,12.1,44.,-211.,-123.,1.3,.205,'road')
market.flush()
# Actual hollow terracotta planters surround the source-guided shop frontages.
from landmarks import lathe
pots=common.Builder('Garden containers · terracotta')
for d in meta['districts'].get('planting',[]):
 ground=max(.12,.205 if 12<d['x']<44 and -211<d['y']<-123 else .12)
 lathe(pots,(d['x'],d['y'],ground),[(.21,0),(.25,.035),(.35,.44),(.39,.47),(.39,.55),(.34,.565),(.315,.49),(.22,.075),(.21,.04)],'ochre',n=40)
 pots.cyl((d['x'],d['y'],ground+.48),.313,.018,'earth',n=40)
 d['z']=ground+.49;d['height']=1.2*d.get('scale',1.0)
pots.flush()
# Material colors exported separately so shader textures can be shared across the village.
meta['materials']={n:list(m.diffuse_color) for n,m in common.MATS.items()}
# Convert type geometry once, retain named chunks and all engraved/printed signs.
for ob in list(scene.objects):
 if ob.type=='FONT':
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH')
# Small physical edge radii catch highlights at walking distance.
# Angular architecture only. Sculpted rock, cloth and terrain keep their geometry.
for ob in list(scene.objects):
 if ob.type!='MESH':continue
 if not (ob.name.startswith('Village · Block') or 'Main gate' in ob.name or 'Hokage Residence' in ob.name):continue
 # Roofing, narrow joinery, cloth and round fittings already have their authored
 # profiles. Bevel only broad masonry edges where the radius is visible.
 if not any(m and m.name in ['plaster','cream','white','ochre','peach','sage','red','stone'] for m in ob.data.materials):continue
 bpy.context.view_layer.objects.active=ob
 bevel=ob.modifiers.new('Construction edge radius','BEVEL');bevel.width=.018;bevel.segments=2
 bevel.limit_method='ANGLE';bevel.angle_limit=math.radians(52);bevel.use_clamp_overlap=True
 try:bpy.ops.object.modifier_apply(modifier=bevel.name)
 except Exception:ob.modifiers.remove(bevel)
 for face in ob.data.polygons:face.use_smooth=True
 ob.data.set_sharp_from_angle(angle=math.radians(38))
 normal=ob.modifiers.new('Area weighted construction normals','WEIGHTED_NORMAL')
 normal.keep_sharp=True;normal.weight=50
 try:bpy.ops.object.modifier_apply(modifier=normal.name)
 except Exception:ob.modifiers.remove(normal)
# Remove export-incompatible procedural shader graphs; runtime supplies original PBR scans.
for m in bpy.data.materials:
 m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF')
 for n in list(m.node_tree.nodes):
  if n.type not in ['BSDF_PRINCIPLED','OUTPUT_MATERIAL']:m.node_tree.nodes.remove(n)
 p.inputs['Base Color'].default_value=m.diffuse_color
# Bake deterministic source. Native textures are supplied by the standalone renderer.
scene.render.engine='BLENDER_EEVEE';scene.world=bpy.data.worlds.new('Summer sky');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.45,.65,.85,1)
sun_data=bpy.data.lights.new('Afternoon sun','SUN');sun_data.energy=2.0
sun=bpy.data.objects.new('Afternoon sun',sun_data);scene.collection.objects.link(sun);sun.rotation_euler=(.5,-.4,-.5)
scene.camera=camera('Main gate',(0,-392,1.9),(0,-330,12),25)
for i,(name,pos,target) in enumerate([('Village',(500,-650,500),(0,0,35)),('Hokage residence',(0,175,2),(0,234,20)),('Ichiraku',(13,-148,1.8),(22,-144,1.7))],1):
 c=camera(name,pos,target,26);mk=scene.timeline_markers.new(name,frame=i);mk.camera=c
scene.render.resolution_x=1600;scene.render.resolution_y=900
OUT.mkdir(parents=True,exist_ok=True);bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Hidden_Leaf_Explorer.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT')
for ob in scene.objects:
 if ob.type=='MESH':ob.select_set(True)
print('EXPORT',len(scene.objects),flush=True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'village_v3.glb'),export_format='GLB',use_selection=True,export_materials='EXPORT',export_yup=True,export_cameras=False,export_lights=False,export_apply=True)
meta['vertices']=sum(len(o.data.vertices) for o in scene.objects if o.type=='MESH');meta['faces']=sum(len(o.data.polygons) for o in scene.objects if o.type=='MESH')
(ASSETS/'village_v3.json').write_text(json.dumps(meta,indent=2,default=str))
print('DONE',meta['vertices'],meta['faces'],flush=True)
