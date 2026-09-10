"""Original early-Shippuden Suna geometry. Layout and dimensions are inferred.
Reference features: dense round clay towers, ring cornices, slit openings,
bulging Kazekage office with wind medallion, continuous eroded cliff enclosure.
"""
import math
import random
import os
import hashlib
from pathlib import Path
import bpy
import bmesh
from collections import defaultdict
from common import Builder, material, MATS, text
from districts import Frame
from village_kit import finish, godot, profiled_shell, ring, radius_at, smooth_profile, curved_patch

SEED=260909

def palette():
    for name,color in {'sand_stucco':(.67,.52,.32),'sand_pale':(.78,.64,.42),
        'sand_rose':(.65,.44,.29),'sand_trim':(.56,.40,.23),'sand_shadow':(.10,.085,.061),
        'sand_rock':(.60,.46,.29),'sand_strata':(.49,.35,.21),'sand_ground':(.66,.53,.36),
        'sand_wood':(.25,.16,.085),'sand_cloth':(.51,.37,.23)}.items():
        material(name,color,roughness=.91)


def core_occluder(frame,profile):
    width=min(radius for _,radius in profile)*1.20
    low=profile[0][0]+.4;high=profile[-1][0]-.4
    return {'shape':'box','position':godot(frame.p((0,0,(low+high)/2))),
        'size':[width,high-low,width],'yaw':frame.rot}


def house(b,x,y,r,floors,rng,rich=True,family=0,occluders=None):
    height=floors*3.15+.30
    f=Frame(b,x,y,.10,rng.choice([0.,.10,-.10]))
    mat=rng.choice(['sand_stucco','sand_pale','sand_rose'])
    if family==0:
        profile=[(0,r*.91),(.35,r),(height*.45,r*1.035),(height-.55,r*.94),(height,r*.96)]
    elif family==1:
        profile=[(0,r*.84),(.55,r*.92),(height*.35,r*1.06),(height*.72,r),(height,r*.83)]
    else:
        profile=[(0,r),(.4,r),(height*.50,r*.91),(height*.52,r*.86),(height,r*.83)]
    profile=smooth_profile(profile,3 if rich else 1)
    if occluders is not None:occluders.append(core_occluder(f,profile))
    profiled_shell(f,profile,floors,mat,bays=40 if rich else 20,detailed=rich,door_material='sand_shadow',
        shadow_material='sand_shadow',trim_material='sand_trim',
        window_bands=[(story*3.15-.92,.68,.52) for story in range(1,floors+1) if family!=1 or story%2==0 or story==floors])
    for story in range(1,floors+1):
        z=story*3.15
        radius=radius_at(profile,z)
        if family!=1 or story%2==0 or story==floors:
            ring(f,radius+.11,z,.11 if family==2 else .16,'sand_trim' if family!=2 else mat,n=40 if rich else 20)
    roof_r=profile[-1][1]
    f.cyl((0,0,height-.08),roof_r-.16,.18,mat,n=40 if rich else 20)
    parapet=.48 if family==1 else (.72 if family==2 else .60)
    ring(f,roof_r,height,parapet,mat,n=40 if rich else 20)
    ring(f,roof_r+.07,height+parapet-.08,.12,'sand_trim' if family==0 else mat,n=40 if rich else 20)
    if family==1:
        # Shallow stepped dome rises inside the terrace parapet.
        dome=[(height,roof_r*.70),(height+.35,roof_r*.65),(height+.80,roof_r*.48),(height+1.1,.10)]
        profiled_shell(f,dome,0,mat,bays=40 if rich else 20,detailed=False)
    # Wind deposited apron fades into the ground; leave the door approach bare.
    if rich:
        skirt=[]
        for i in range(49):
            a=.25+(math.tau-.50)*i/48
            drift=.20+.28*(.5+.5*math.sin(a*3+x*.37))
            rr=radius_at(profile,.1)
            skirt.extend([(rr*math.sin(a),-rr*math.cos(a),.16+drift*.25),
                ((rr+drift)*math.sin(a),-(rr+drift)*math.cos(a),-.075)])
        f.mesh(skirt,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(48)],'sand_ground')
    if not rich:
        # Distant window cuts use four vertices apiece, batched with each cell.
        for story in range(floors):
            z=2.23+story*3.15
            rr=radius_at(profile,z)+.012
            for i in range(12):
                a=i*math.tau/12; da=.24/rr
                f.mesh([(rr*math.sin(angle),-rr*math.cos(angle),zz)
                    for zz in (z,z+.68) for angle in (a-da,a+da)],[(0,1,3,2)],'sand_shadow')
        return
    # Closed timber leaves follow the true curved opening, 28cm into its reveal.
    door_half=math.asin(1.30/(2*radius_at(profile,1.)))
    for i in range(8):
        left=-door_half+(2*door_half)*i/8+.002
        right=-door_half+(2*door_half)*(i+1)/8-.002
        curved_patch(f,profile,left,right,.14,2.28,'sand_wood',.285)
    for z in (.44,1.83):curved_patch(f,profile,-door_half+.004,door_half-.004,z,z+.095,'sand_wood',.25)
    def front(x,z,inset=0.):return -math.sqrt(max(.1,radius_at(profile,z)**2-x*x))+inset
    foot=radius_at(profile,.10)
    f.box((0,-foot-.08,.06),(1.62,.80,.12),'sand_trim')
    f.box((0,-foot-.40,.015),(1.88,.34,.05),'sand_pale')
    for offset in (-.67,.67):
        points=[(offset,front(offset,z,.015),z) for z in (.10,.55,1.1,1.65,2.34)]
        for aa,bb in zip(points,points[1:]):f.beam(aa,bb,.052,'sand_wood')
    curved_patch(f,profile,-door_half-.025,door_half+.025,2.34,2.47,'sand_trim',-.065)
    f.beam((.38,front(.38,1.1,.23),1.05),(.38,front(.38,1.1,.23),1.28),.026,'sand_trim')
    # Drainage scuppers project out from flat terraces and have open U profiles.
    if family!=1:
        for a in (math.pi*.5,math.pi*1.5):
            ff=f.child((roof_r*math.sin(a),-roof_r*math.cos(a),height+.025),a)
            ff.box((0,-.21,0),(.24,.64,.09),'sand_trim')
            for xx in (-.105,.105):ff.box((xx,-.21,.075),(.05,.64,.16),'sand_trim')
    # Restrained shop groups use connected timber frames and tensioned cloth.
    if abs(x)<20 and -50<y<2 and family!=2:
        back=-radius_at(profile,3.0)+.06;edge=-foot-1.75
        for xx in (-1.75,1.75):
            f.beam((xx,edge,.05),(xx,edge,2.69),.065,'sand_wood')
            f.beam((xx,back,3.03),(xx,edge,2.69),.055,'sand_wood')
            f.beam((xx,edge,2.05),(xx,edge+.48,2.79),.035,'sand_wood')
        f.beam((-1.88,edge,2.69),(1.88,edge,2.69),.07,'sand_wood')
        f.beam((-1.88,back,3.03),(1.88,back,3.03),.07,'sand_wood')
        vv=[]
        for j in range(5):
            t=j/4
            for i in range(13):
                u=i/12;xx=-1.8+3.6*u
                vv.append((xx,back+(edge-back)*t,3.05-.34*t-.11*math.sin(math.pi*u)*math.sin(math.pi*t)))
        faces=[]
        for j in range(4):
            for i in range(12):
                k=j*13+i;faces.append((k,k+1,k+14,k+13))
        # Both sides have actual triangles so ordinary opaque cloth remains visible.
        f.mesh(vv+[(xx,yy,zz-.016) for xx,yy,zz in vv],faces+[tuple(k+len(vv) for k in reversed(face)) for face in faces],'sand_cloth')
        for i in range(12):
            xx=-1.8+i*.30
            f.box((xx+.15,edge,2.58),(.30,.016,.22),'sand_cloth')
        # Raised display shelf occupies one side; the 1.3m doorway stays clear.
        f.box((1.23,edge+.48,.84),(.66,.70,.075),'sand_wood')
        for xx in (.97,1.49):
            for yy in (edge+.21,edge+.74):f.beam((xx,yy,.07),(xx,yy,.82),.037,'sand_wood')
    elif family==2:
        # Stone sitting ledge belongs to the entrance apron instead of floating on a radius.
        bx=1.55;by=front(bx,.3)-.14
        f.box((bx,by,.28),(1.12,.43,.48),mat)


def office(roles,occluders):
    b=Builder('Sand Kazekage office'); f=Frame(b,0,46,.20)
    # Reference: solid rounded belly, lateral short porthole belts, stepped crown.
    body=smooth_profile([(0,10.4),(1,11.2),(6,13.4),(12,13.8),(17.4,12.2)],4)
    profile=body+[(18.6,11.45),(18.75,10.65),(20.0,10.65),(20.12,9.7),(21.5,8.8),(22.,7.8),(22.35,7.8)]
    occluders.append(core_occluder(f,profile))
    belts=[(4.5,-1.25,-.55),(7.8,-1.28,-.63),(6.6,.67,1.29),(13.7,.45,1.03),(14.2,-1.1,-.67),(12.0,1.07,1.45)]
    bands=[(z,.43,.39) for z,_,_ in belts]+[(19.1,.43,.42)]
    def openings(angle,z):
        if z>18:return True
        return any(abs(z-bz)<.05 and lo<angle<hi for bz,lo,hi in belts)
    profiled_shell(f,profile,0,'sand_pale',bays=192,detailed=True,door_width=2.2,
        door_material='sand_wood',shadow_material='sand_shadow',trim_material='sand_trim',
        window_filter=openings,window_bands=bands)
    def surface(x,z,depth=.08):return -math.sqrt(max(.1,radius_at(profile,z)**2-x*x))-depth
    def band_frame(z,lo,hi):
        r=radius_at(profile,z);center=z+.215;half=.40
        points=[]
        # Rounded capsule ends join the upper and lower continuous cast-stucco lips.
        for i in range(17):
            a=lo+(hi-lo)*i/16;points.append((r*math.sin(a),-r*math.cos(a)-.08,center+half))
        for i in range(1,9):
            t=math.pi/2-math.pi*i/8;a=hi+math.cos(t)*half/r
            zz=center+math.sin(t)*half;rr=radius_at(profile,zz)
            points.append((rr*math.sin(a),-rr*math.cos(a)-.08,zz))
        for i in range(1,17):
            a=hi-(hi-lo)*i/16;rr=radius_at(profile,center-half)
            points.append((rr*math.sin(a),-rr*math.cos(a)-.08,center-half))
        for i in range(1,9):
            t=-math.pi/2-math.pi*i/8;a=lo+math.cos(t)*half/r
            zz=center+math.sin(t)*half;rr=radius_at(profile,zz)
            points.append((rr*math.sin(a),-rr*math.cos(a)-.08,zz))
        for aa,bb in zip(points,points[1:]+points[:1]):f.beam(aa,bb,.075,'sand_trim',n=8)
    for z,lo,hi in belts:band_frame(z,lo,hi)
    for z in (18.66,18.96,19.73,20.06):ring(f,radius_at(profile,z)+.10,z,.13,'sand_trim',n=96)
    f.cyl((0,0,22.28),7.65,.16,'sand_pale',n=64)
    # Railing follows the flattened crown. Uprights have actual top/bottom rings.
    ring(f,7.25,22.37,.06,'sand_wood',n=64)
    ring(f,7.25,22.93,.055,'sand_wood',n=64)
    for i in range(48):
        angle=i*math.tau/48
        f.beam((7.22*math.sin(angle),-7.22*math.cos(angle),22.38),(7.22*math.sin(angle),-7.22*math.cos(angle),22.94),.026,'sand_wood',n=6)
    # Large inset wind medallion occupies 42% of the office's maximum diameter.
    material('sand_emblem',(.52,.55,.45),roughness=.88)
    emblem_radius=5.75;center_z=9.65
    vv=[(0,surface(0,center_z,.11),center_z)]
    for j in range(1,9):
        rr=emblem_radius*j/8
        for i in range(96):
            angle=i*math.tau/96;x=rr*math.cos(angle);z=center_z+rr*math.sin(angle)
            vv.append((x,surface(x,z,.11),z))
    faces=[(0,1+i,1+(i+1)%96) for i in range(96)]
    for j in range(7):
        for i in range(96):
            aa=1+j*96+i;bb=1+j*96+(i+1)%96
            faces.append((aa,aa+96,bb+96,bb))
    f.mesh(vv,faces,'sand_emblem')
    for radius in (5.75,5.40):
        points=[]
        for i in range(97):
            angle=i*math.tau/96;x=radius*math.cos(angle);z=center_z+radius*math.sin(angle)
            points.append((x,surface(x,z,.20),z))
        for aa,bb in zip(points,points[1:]):f.beam(aa,bb,.12,'sand_trim',n=10)
    # Bake a real CJK glyph outline, without bundling a font runtime dependency.
    font_paths=([Path(os.environ['HIDDEN_LEAF_FONT'])] if os.environ.get('HIDDEN_LEAF_FONT') else [])+sorted(Path('/System/Library/Fonts').glob('*明朝*'))+[Path('/System/Library/Fonts/Supplemental/Songti.ttc')]
    font_path=next((path for path in font_paths if path.is_file()),None)
    if font_path is None:raise RuntimeError('Set HIDDEN_LEAF_FONT to a CJK font for the baked wind glyph')
    text.font=bpy.data.fonts.load(str(font_path))
    glyph=text('風',(0,0,0),1.,mat='sand_wood',name='Wind glyph authoring source',rotation=(0,0,0))
    glyph.data.resolution_u=8;glyph.data.extrude=.014
    bpy.ops.object.select_all(action='DESELECT');glyph.select_set(True);bpy.context.view_layer.objects.active=glyph
    bpy.ops.object.convert(target='MESH')
    coords=[v.co.copy() for v in glyph.data.vertices]
    if not coords:raise RuntimeError('CJK font did not produce wind glyph geometry')
    min_x=min(v.x for v in coords);max_x=max(v.x for v in coords)
    min_y=min(v.y for v in coords);max_y=max(v.y for v in coords)
    scale=8.55/max(max_x-min_x,max_y-min_y)
    vertices=[]
    for v in coords:
        x=(v.x-(min_x+max_x)/2)*scale;z=center_z+(v.y-(min_y+max_y)/2)*scale
        vertices.append((x,surface(x,z,.235)-v.z*scale,z))
    f.mesh(vertices,[tuple(p.vertices) for p in glyph.data.polygons],'sand_wood')
    bpy.data.objects.remove(glyph,do_unlink=True)
    font_record={'glyph':'風','source_path':str(font_path),'source_sha256':hashlib.sha256(font_path.read_bytes()).hexdigest(),
        'delivery':'baked glyph mesh only; font file is not copied or bundled'}
    # Original source leaves access inferred; preserve the functioning low entrance.
    f.box((0,-10.8,.4),(9,7,.8),'sand_stucco')
    for i in range(5):f.box((0,-16.0+i*.36,.075*(i+1)),(6.5,.38,.15*(i+1)),'sand_trim')
    finish(b,roles,True,850)
    for x in (-21,21):
        tower=Builder('Sand office flanking tower '+str(x))
        tf=Frame(tower,x,48,.1);h=20.;r=5.5
        tp=smooth_profile([(0,4.8),(1,5.2),(7,5.65),(14,5.5),(h,5.1)],3)
        occluders.append(core_occluder(tf,tp))
        profiled_shell(tf,tp,0,'sand_stucco',bays=96,detailed=True,door_material='sand_wood',
            shadow_material='sand_shadow',trim_material='sand_trim',window_bands=[(z,.85,.48) for z in (3.15,8.15,13.15,18.15)])
        for z in (3.02,4.12,8.02,9.12,13.02,14.12,18.02,19.12):ring(tf,radius_at(tp,z)+.11,z,.15,'sand_trim',n=64)
        tf.cyl((0,0,h-.08),5.0,.16,'sand_stucco',n=64)
        ring(tf,5.10,h,.65,'sand_stucco',n=64)
        finish(tower,roles,True,850)
    # Low service walls connect the frontage without closing the central route.
    walls=Builder('Sand official frontage')
    for x in (-13.,13.):
        walls.box((x,27,1.2),(13.,.65,2.4),'sand_stucco')
        walls.box((x,27,2.4),(13.2,.79,.18),'sand_trim')
    # Two purposeful utility spans connect office-side posts, safely above walking.
    for side in (-1,1):
        points=[]
        for i in range(17):
            t=i/16;points.append((side*(7+14*t),31+9*t,6.2+.8*t-.65*math.sin(math.pi*t)))
        for aa,bb in zip(points,points[1:]):walls.beam(aa,bb,.018,'sand_wood',n=5)
        walls.beam((side*7,31,0),(side*7,31,6.3),.065,'sand_wood',n=8)
    finish(walls,roles,True,450)
    return font_record


def enclosure(roles):
    rng=random.Random(SEED+1)
    count=576
    # Alternating resistant ledges and recessed beds; each has its own thickness.
    heights=[0,.07,.15,.21,.235,.32,.39,.415,.49,.57,.595,.69,.76,.79,.88,.94,1.]
    shelves=[0,-1,1.1,1.9,-.6,.4,2.2,-1.2,.6,2.3,-.8,.9,2.8,-.4,1.5,2.1,1.]
    def point(i,j):
        a=-math.pi/2+.055+(math.tau-.11)*i/count
        t=heights[j]
        a+=math.sin(a*19+t*7)*.0025*math.sin(math.pi*t)
        # Erosion runs vertically through beds, while joint spacing varies around basin.
        gully=(.5+.5*math.sin(a*43+math.sin(a*13)+t*1.7))**6
        joint=math.sin(a*89+j*.62)*.62+math.sin(a*131-j*.41)*.36
        buttress=9.0*math.sin(a*7+1.4)+5.8*math.sin(a*17)+2.8*math.sin(a*31)
        radius=245+buttress+t*16+shelves[j]*(.35+.65*math.sin(a*8+1))*math.sin(a*3+t*4)+gully*9.5+joint
        elevation=t*(91+17*math.sin(a*5)+10*math.sin(a*11)+5*math.sin(a*23))
        if j not in (0,len(heights)-1):elevation+=math.sin(a*23+j*.4)*.62+math.sin(a*59)*.34
        return (radius*math.cos(a),radius*math.sin(a),elevation-.13)
    for start in range(0,count,count):
        b=Builder('Sand eroded escarpment %03d'%start)
        for i in range(start,min(count,start+count)):
            for j in range(len(heights)-1):
                p=[point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)]
                # Triangulated angular beds carry real ledge and gully silhouettes.
                faces=[(0,3,2),(0,2,1)] if (i+j)%2 else [(0,3,1),(1,3,2)]
                mat='sand_rock'
                b.mesh(p,faces,mat)
            a,c=point(i,len(heights)-1),point(i+1,len(heights)-1)
            b.mesh([a,c,(c[0]*1.38,c[1]*1.38,c[2]+2.4),(a[0]*1.38,a[1]*1.38,a[2]+2.4)],[(3,2,1,0)],'sand_rock')
            # Accumulated talus slopes ease the vertical wall into basin soil.
            aa=point(i,0);cc=point(i+1,0)
            basea=(aa[0]*.95,aa[1]*.95,.02);basec=(cc[0]*.95,cc[1]*.95,.02)
            uppa=point(i,1);uppc=point(i+1,1)
            b.mesh([basea,basec,uppc,uppa],[(0,3,2),(0,2,1)],'sand_rock')
        for _ in range(25):
            i=rng.uniform(start,min(count-.001,start+count))
            a=-math.pi/2+.055+(math.tau-.11)*i/count
            rr=rng.uniform(229,240);size=rng.uniform(.28,1.25)
            b.sphere((rr*math.cos(a),rr*math.sin(a),size*.29),(size,size*.73,size*.58),'sand_rock',n=7,rings=4)
        objects=finish(b,roles,True,1500)
        for ob in objects:
            bm=bmesh.new();bm.from_mesh(ob.data)
            bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.001)
            bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
            bm.to_mesh(ob.data);bm.free()
            for face in ob.data.polygons:face.use_smooth=True


def build(slice_only=False):
    palette();rng=random.Random(SEED);roles={};colliders=[];occluders=[]
    ground=Builder('Sand ground');ground.box((0,0,-.20),(900,900,.4),'sand_ground')
    for ob in finish(ground,roles,True,1800):roles[ob.name]['occlusion_culling']=False
    font_record=office(roles,occluders)
    # Staggered frontage clusters tighten the avenue to 8-12m, opening into
    # the official plaza. Metric entrances stay unchanged; layouts are inferred.
    count=0;frontages=[]
    for row,y in enumerate((-60,-43,-27,-10,7,25,41)):
        for column,x in enumerate((-43,-27,-11,11,27,43)):
            if y>15 and abs(x)<20:continue
            r=rng.uniform(4.2,5.9)
            floors=rng.choice([2,2,3,4,5])
            b=Builder('Sand district %02d'%count)
            hx=x+rng.uniform(-1.3,1.3)
            # Reserve x [-20.5,-17.5] through the residential district, including
            # maximum bulge, trims and drift skirts. Annexes face away from it.
            if x==-27:hx=min(hx,-20.5-1.12*r-.65)
            if x==-11:hx=max(hx,-17.5+1.12*r+.65)
            hy=y+rng.uniform(-2.0,2.0)+(2.5 if column%2 else 0.)
            house(b,hx,hy,r,floors,rng,True,rng.randrange(3),occluders)
            frontages.append((row,hx,hy,r))
            # Low attached rear rooms form inhabited compounds, breaking the
            # isolated tower rhythm without changing the tower or its doorway.
            if row%2==column%2:
                annex=Frame(b,hx+(-1 if x==-27 else 1)*r*.58,hy+r*.42,.1)
                ah=2.8+rng.random()*.8
                annex.box((0,0,ah/2),(r*1.35,r*1.15,ah),'sand_stucco')
                annex.box((0,0,ah),(r*1.40,r*1.20,.18),'sand_pale')
            finish(b,roles,True,650);count+=1
    # Shared masonry courts join selected neighbors; 1.2m portals retain passage.
    links=Builder('Sand shared service courts')
    for row in (0,2,4,6):
        houses=sorted([p for p in frontages if p[0]==row],key=lambda p:p[1])
        for aa,bb in zip(houses,houses[1:]):
            if aa[1]*bb[1]<0 or aa[1]<-19<bb[1]:continue
            left=aa[1]+aa[3]*.87;right=bb[1]-bb[3]*.87
            span=right-left
            if span<1.6:continue
            center=(left+right)/2;yy=aa[2]+1.1
            pier=(span-1.2)/2
            for xx in (left+pier/2,right-pier/2):
                links.box((xx,yy,1.05),(pier,.48,2.1),'sand_stucco')
                links.box((xx,yy,2.09),(pier+.08,.57,.13),'sand_pale')
            links.box((center,yy,2.02),(1.32,.48,.20),'sand_stucco')
            links.box((center,yy,.025),(1.22,.76,.05),'sand_trim')
    finish(links,roles,True,400)
    # Public courtyard and route furniture are practical masonry, not vegetation.
    court=Builder('Sand courtyard');f=Frame(court,0,-23,0)
    for x in (-4.2,4.2):
        f.box((x,0,.29),(.65,8,.58),'sand_pale')
        for y in (-3.5,3.5):f.cyl((x,y,.95),.18,1.9,'sand_trim',n=16)
    # Small covered well on a lateral court, maintaining central road clearance.
    f=Frame(court,62,-18,0);ring(f,1.05,.1,.82,'sand_trim',n=40)
    for x in (-1.3,1.3):f.beam((x,0,.1),(x,0,2.65),.10,'sand_wood')
    f.beam((-1.5,0,2.65),(1.5,0,2.65),.12,'sand_wood')
    # A raised service court provides an actual walkable stair/terrace transition.
    f=Frame(court,59,-46,0)
    f.box((0,0,.60),(5.8,5,1.2),'sand_stucco')
    f.box((2.65,0,1.62),(.35,5,.84),'sand_pale')
    f.box((0,2.3,1.62),(5.8,.35,.84),'sand_pale')
    for i in range(8):f.box((0,-5.0+i*.32,.075*(i+1)),(2.3,.34,.15*(i+1)),'sand_trim')
    finish(court,roles,True,350)
    # Macro city preserves dense rounded silhouette with spatial material batches.
    # --slice still includes skyline; it reduces only the distant density.
    cells={};macro=0
    step=19 if slice_only else 16
    for y in range(-211,212,step):
        for x in range(-211,212,step):
            if math.hypot(x,y)>225 or (abs(x)<64 and -75<y<80) or abs(x)<9:continue
            key=(x//64,y//64)
            if key not in cells:cells[key]=Builder('Sand skyline %d %d'%key)
            hx=x+rng.uniform(-2.5,2.5)+(3.5 if (y//step)%2 else -1.5);hy=y+rng.uniform(-2.4,2.4)
            radius=rng.uniform(4.4,6.6);floors=rng.choice([2,3,4,5]);height=floors*3.15+.94
            house(cells[key],hx,hy,radius,floors,rng,False,macro%3,occluders)
            colliders.append({'shape':'cylinder','position':godot((hx,hy,height/2+.10)),'radius':radius,'height':height})
            macro+=1
    for b in cells.values():finish(b,roles,False,1100)
    enclosure(roles)
    return {'id':'sand','name':'Sunagakure','era':'Early Shippuden, Kazekage Rescue',
        'provenance':'Original geometry from supplied reference frames; unshown layout and metric dimensions inferred.',
        'seed':SEED,'units':'meters','slice_buildings':count+3,'macro_buildings':macro,
        'materials':{n:list(m.diffuse_color) for n,m in MATS.items()},'mesh_roles':roles,'colliders':colliders,
        'occluders':occluders,'baked_font':font_record,
        'bookmarks':[{'name':'Sand avenue','position':godot((0,-72,.12)),'target':godot((0,46,12))},
            {'name':'Kazekage plaza','position':godot((0,15,.12)),'target':godot((0,46,12))},
            {'name':'Clay district','position':godot((-19,-42,.12)),'target':godot((-30,-29,8))},
            {'name':'Enclosure','position':godot((0,-213,.12)),'target':godot((0,0,20))}]}
