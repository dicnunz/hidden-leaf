import bpy, math, random
from mathutils import Vector
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.build' / 'model'
MATS = {}

def material(name, color, roughness=.82, noise=0, metallic=0, emission=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=roughness; p.inputs['Metallic'].default_value=metallic
    if emission:
        p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emission
    if noise:
        nd=m.node_tree.nodes; lk=m.node_tree.links
        tex=nd.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=2.5; tex.inputs['Detail'].default_value=3
        coord=nd.new('ShaderNodeTexCoord'); lk.new(coord.outputs['Object'],tex.inputs['Vector'])
        ramp=nd.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position=.2; ramp.color_ramp.elements[0].color=(*(c*.79 for c in color),1)
        ramp.color_ramp.elements[1].position=.8; ramp.color_ramp.elements[1].color=(*(min(c*1.09,1) for c in color),1)
        lk.new(tex.outputs['Fac'],ramp.inputs[0]); lk.new(ramp.outputs[0],p.inputs['Base Color'])
        b=nd.new('ShaderNodeBump'); b.inputs['Strength'].default_value=noise; b.inputs['Distance'].default_value=.06
        lk.new(tex.outputs['Fac'],b.inputs['Height']); lk.new(b.outputs[0],p.inputs['Normal'])
    # Keep the painted palette rich under bright daylight and AgX.
    m.diffuse_color=(*(c**1.55 for c in color),1)
    p.inputs['Base Color'].default_value=(*(c**1.55 for c in color),1)
    for nd in m.node_tree.nodes:
        if nd.type=='VALTORGB':
            for e in nd.color_ramp.elements: e.color=(*(c**1.55 for c in e.color[:3]),1)
    MATS[name]=m; return m

def setup_materials():
    colors={'plaster':(.69,.61,.42),'cream':(.83,.77,.57),'white':(.86,.83,.68),
      'ochre':(.63,.40,.17),'peach':(.71,.44,.29),'sage':(.42,.53,.40),
      'roof_red':(.42,.095,.049),'roof_orange':(.65,.23,.067),'roof_teal':(.07,.29,.25),
      'roof_blue':(.13,.26,.32),'roof_dark':(.12,.16,.16),'wood':(.24,.12,.054),
      'wood_light':(.42,.25,.12),'trim':(.26,.22,.15),'stone':(.47,.43,.32),
      'cliff':(.44,.285,.125),'rock_light':(.51,.325,.155),'rock_shadow':(.25,.18,.12),
      'earth':(.51,.39,.235),'road':(.72,.58,.36),'grass':(.21,.31,.10),
      'leaf':(.10,.24,.055),'leaf_light':(.23,.38,.09),'leaf_dark':(.054,.15,.043),
      'bark':(.18,.105,.046),'red':(.60,.065,.028),'black':(.035,.038,.028),
      'fabric':(.82,.73,.51),'paper':(.94,.84,.59),'metal':(.16,.22,.20),
      'water':(.075,.33,.31),'glass':(.09,.18,.17),'glow':(1,.52,.14)}
    for n,c in colors.items():
        material(n,c,roughness=.3 if n in ['water','glass'] else .82,
                 noise=.25 if n in ['plaster','cream','stone','cliff','rock_light','road','earth','wood','bark'] else .07,
                 metallic=.35 if n=='metal' else 0,emission=.7 if n=='glow' else 0)

class Builder:
    def __init__(self,name): self.name=name; self.data=defaultdict(lambda:[[],[]])
    def mesh(self,verts,faces,mat):
        vs,fs=self.data[mat]; off=len(vs); vs.extend(verts); fs.extend(tuple(i+off for i in f) for f in faces)
    def box(self,c,s,mat,rot=0):
        x,y,z=c; a,b,h=[v/2 for v in s]; co,si=math.cos(rot),math.sin(rot)
        v=[(x+u*co-v*si,y+u*si+v*co,z+w) for u,v,w in [(-a,-b,-h),(a,-b,-h),(a,b,-h),(-a,b,-h),(-a,-b,h),(a,-b,h),(a,b,h),(-a,b,h)]]
        self.mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    def cyl(self,c,r,h,mat,n=20,r2=None,rot=0):
        x,y,z=c; r2=r if r2 is None else r2
        v=[(x+rr*math.cos(i*math.tau/n+rot),y+rr*math.sin(i*math.tau/n+rot),z+zz) for rr,zz in [(r,-h/2),(r2,h/2)] for i in range(n)]
        f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        self.mesh(v,f,mat)
    def sphere(self,c,s,mat,n=16,rings=10):
        x,y,z=c; sx,sy,sz=s
        v=[(x+sx*math.sin(math.pi*j/rings)*math.cos(math.tau*i/n),y+sy*math.sin(math.pi*j/rings)*math.sin(math.tau*i/n),z+sz*math.cos(math.pi*j/rings)) for j in range(rings+1) for i in range(n)]
        self.mesh(v,[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(rings) for i in range(n)],mat)
    def beam(self,a,b,r,mat,n=8,r2=None):
        a,b=Vector(a),Vector(b); d=(b-a).normalized(); q=d.to_track_quat('Z','Y'); r2=r if r2 is None else r2
        v=[tuple(p+q@Vector((rr*math.cos(i*math.tau/n),rr*math.sin(i*math.tau/n),0))) for p,rr in [(a,r),(b,r2)] for i in range(n)]
        self.mesh(v,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat)
    def line(self,points,r,mat,n=6):
        for a,b in zip(points,points[1:]): self.beam(a,b,r,mat,n)
    def flush(self,collection=None):
        col=collection or bpy.data.collections.new(self.name)
        if not collection: bpy.context.scene.collection.children.link(col)
        obs=[]
        for mat,(v,f) in self.data.items():
            if not v: continue
            mesh=bpy.data.meshes.new(self.name+' · '+mat); mesh.from_pydata(v,[],f); mesh.materials.append(MATS[mat]); mesh.update()
            # Smooth connected curved surfaces while retaining construction edges.
            for poly in mesh.polygons: poly.use_smooth=True
            mesh.set_sharp_from_angle(angle=math.radians(38))
            ob=bpy.data.objects.new(mesh.name,mesh); col.objects.link(ob); obs.append(ob)
        self.data.clear(); return obs

def text(body,loc,size,mat='black',name=None,rotation=(math.pi/2,0,0),align='CENTER'):
    cu=bpy.data.curves.new(name or body,'FONT'); cu.body=body; cu.size=size; cu.align_x=align; cu.align_y='CENTER'; cu.extrude=.012
    font=getattr(text,'font',None)
    if font: cu.font=font
    ob=bpy.data.objects.new(name or body,cu); bpy.context.scene.collection.objects.link(ob); ob.location=loc; ob.rotation_euler=rotation; cu.materials.append(MATS[mat]); return ob

def leaf_symbol(b,c,size,mat='red'):
    x,y,z=c
    pts=[]
    for i in range(45):
        t=i/44*math.pi*3.45; r=size*(.07+.29*i/44)
        pts.append((x+r*math.cos(t),y,z+r*math.sin(t)))
    b.line(pts,size*.035,mat)
    b.line([(x-size*.04,y,z-size*.28),(x-size*.51,y,z-size*.30),(x-size*.44,y,z+size*.20),(x-size*.27,y,z+size*.24)],size*.035,mat)
    b.line([(x+size*.24,y,z+size*.22),(x+size*.42,y,z+size*.52),(x+size*.07,y,z+size*.40)],size*.035,mat)

def camera(name,loc,target,lens=36):
    data=bpy.data.cameras.new(name); data.lens=lens; data.clip_end=5000; data.clip_start=.08
    ob=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(ob); ob.location=loc; ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler(); return ob
