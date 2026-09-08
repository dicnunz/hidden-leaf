"""Human-scale, batched residential and shopping streets for Shippuden Konoha.

Only geometry is constructed here.  Ground, roads and named landmarks are owned
by the scene assembly script. One Blender unit is one metre.
"""
import math
import random

from common import Builder

# Anime frames are used as dimensional references, never as facade textures.
REFERENCE_IMAGES = {
    'ichiraku_original': {
        'image': 'https://static.wikia.nocookie.net/naruto/images/b/be/Ichiraku_ramen.png/revision/latest?cb=20150703064830',
        'page': 'https://naruto.fandom.com/wiki/Ramen_Ichiraku',
        'use': 'Original-series view continuing into pre-Pain Shippuden: attached frontage, upper service storey, deep awning, mixed-height block.'},
    'yamanaka_original': {
        'image': 'https://static.wikia.nocookie.net/naruto/images/b/b7/Yamanaka%27s_flower_shop.PNG/revision/latest?cb=20150205191005',
        'page': 'https://naruto.fandom.com/wiki/Yamanaka_Flowers',
        'use': 'Original-series storefront: plaster piers, recessed entrance, shallow upper lights, continuous canopy and pots.'},
    'konoha_skyline': {
        'image': 'https://static.wikia.nocookie.net/naruto/images/3/34/Konohagakure.png/revision/latest?cb=20160728115517',
        'page': 'https://naruto.fandom.com/wiki/Konohagakure',
        'use': 'Mixed rectangular blocks and round tower silhouettes; geographic adjacency is interpreted.'},
}


def _opening(x, z, width, height):
    return (x-width/2, x+width/2, z-height/2, z+height/2)


def _facade_wall(f, span, bottom, top, openings, mat, thickness=.32):
    """Build masonry around actual openings, leaving the entire reveal empty.

    Local negative Y points outdoors. Wall faces lie at Y=0 and Y=thickness;
    no full building cube remains behind a window or doorway.
    """
    holes=[(max(-span/2,a),min(span/2,b),max(bottom,c),min(top,d))
           for a,b,c,d in openings if a<span/2 and b>-span/2 and c<top and d>bottom]
    xs=sorted(set([-span/2,span/2]+[v for a,b,c,d in holes for v in (a,b)]))
    zs=sorted(set([bottom,top]+[v for a,b,c,d in holes for v in (c,d)]))
    verts=[]
    faces=[]
    def quad(points):
        start=len(verts)
        verts.extend(points)
        faces.append(tuple(range(start,start+4)))
    for z0,z1 in zip(zs,zs[1:]):
        run=None
        for x0,x1 in zip(xs,xs[1:]):
            mx,mz=(x0+x1)/2,(z0+z1)/2
            solid=not any(a<mx<b and c<mz<d for a,b,c,d in holes)
            if solid and run is None:
                run=x0
            if run is not None and (not solid or x1==xs[-1]):
                end=x0 if not solid else x1
                if end-run>.001 and z1-z0>.001:
                    quad([(run,0,z0),(end,0,z0),(end,0,z1),(run,0,z1)])
                    quad([(end,thickness,z0),(run,thickness,z0),
                          (run,thickness,z1),(end,thickness,z1)])
                run=None
    for a,b,c,d in holes:
        quad([(a,0,c),(a,thickness,c),(a,thickness,d),(a,0,d)])
        quad([(b,thickness,c),(b,0,c),(b,0,d),(b,thickness,d)])
        quad([(a,0,c),(b,0,c),(b,thickness,c),(a,thickness,c)])
        quad([(a,thickness,d),(b,thickness,d),(b,0,d),(a,0,d)])
    for xx in (-span/2,span/2):
        quad([(xx,0,bottom),(xx,thickness,bottom),(xx,thickness,top),(xx,0,top)])
    for zz in (bottom,top):
        quad([(-span/2,0,zz),(span/2,0,zz),(span/2,thickness,zz),(-span/2,thickness,zz)])
    f.mesh(verts,faces,mat)


def _drum_shell(f, radius, bottom, height, stories, mat, rich=False, doorway=False):
    """Sixteen curved wall bays with eight genuinely pierced window bays."""
    sides=16
    apothem=radius*math.cos(math.pi/sides)
    span=2*radius*math.sin(math.pi/sides)
    for face in range(sides):
        angle=face*math.tau/sides
        ff=f.child((apothem*math.sin(angle),-apothem*math.cos(angle),0),angle)
        holes=[]
        for story in range(stories):
            if face%2:
                continue
            if doorway and face==0 and story==0:
                holes.append(_opening(0,1.395,1.54,2.31))
                _door(ff,rich=rich)
                continue
            z=bottom+(story+.59)*height/stories
            ww=min(1.42,span-.34)
            holes.append(_opening(0,z,ww+.20,1.65))
            _window(ff,0,z,ww,1.45,rich=rich and face in (0,2,14))
        _facade_wall(ff,span,bottom,bottom+height,holes,mat)


class Frame:
    """A tiny local coordinate system, keeping all primitives batchable."""
    def __init__(self, builder, x=0, y=0, z=0, rot=0):
        self.b = builder
        self.x, self.y, self.z, self.rot = x, y, z, rot
        self.co, self.si = math.cos(rot), math.sin(rot)

    def p(self, p):
        x, y, z = p
        return (self.x+x*self.co-y*self.si,
                self.y+x*self.si+y*self.co, self.z+z)

    def child(self, p=(0, 0, 0), rot=0):
        return Frame(self.b, *self.p(p), self.rot+rot)

    def box(self, c, s, mat, rot=0):
        self.b.box(self.p(c), s, mat, self.rot+rot)

    def cyl(self, c, r, h, mat, n=16, r2=None, rot=0):
        self.b.cyl(self.p(c), r, h, mat, n, r2, self.rot+rot)

    def beam(self, a, b, r, mat, n=6, r2=None):
        self.b.beam(self.p(a), self.p(b), r, mat, n, r2)

    def mesh(self, verts, faces, mat):
        self.b.mesh([self.p(v) for v in verts], faces, mat)


def _window(f, x, z, width=1.3, height=1.48, shutters=False, rich=False):
    # Glazing sits 31 cm behind the wall plane inside a genuinely cut opening.
    # Continuous joinery ring avoids hidden overlapping cubes inside masonry.
    vs=[]
    for yy,ww,hh in ((-.06,width+.20,height+.20),(-.06,width,height),
                     (.33,width+.20,height+.20),(.33,width,height)):
        vs.extend((x+xx,yy,z+zz) for xx,zz in
                  ((-ww/2,-hh/2),(ww/2,-hh/2),(ww/2,hh/2),(-ww/2,hh/2)))
    fs=[]
    for i in range(4):
        j=(i+1)%4
        fs.extend(((i,j,j+4,i+4),(i+4,j+4,j+12,i+12),
                   (j+8,i+8,i+12,j+12)))
    f.mesh(vs,fs,'wood')
    f.mesh([(x-width/2,.31,z-height/2),(x+width/2,.31,z-height/2),
            (x+width/2,.31,z+height/2),(x-width/2,.31,z+height/2)],
           [(0,1,2,3)],'glass')
    f.box((x, .265, z), (.065, .075, height), 'wood_light')
    if rich:
        f.box((x, .265, z+.03), (width, .075, .065), 'wood_light')
    f.box((x, .05, z-height/2-.10), (width+.35, .64, .14), 'wood_light')
    if shutters:
        for sign in (-1, 1):
            sx = x+sign*(width*.5+.38)
            f.box((sx, -.15, z), (.51, .095, height+.04), 'wood_light')
            if rich:
                for dz in (-.45, -.15, .15, .45):
                    f.box((sx, -.205, z+dz), (.43, .04, .058), 'wood')
    elif rich:
        for dx in (-width*.25, width*.25):
            f.box((x+dx, .265, z), (.04, .075, height), 'wood_light')


def _door(f, x=0, rich=False):
    for sign in (-1,1):
        f.box((x+sign*.705,.14,1.39),(.13,.42,2.31),'wood')
    f.box((x,.14,2.48),(1.54,.42,.15),'wood')
    f.box((x,.35,1.35),(1.28,.10,2.10),'wood_light')
    f.box((x,.285,1.79),(1.09,.025,.97),'glass')
    f.box((x,.24,1.79),(.06,.07,1.02),'wood')
    f.box((x,.24,1.79),(1.13,.07,.065),'wood')
    f.box((x,.285,.72),(1.08,.07,.47),'wood')
    f.box((x+.46,.19,1.26),(.055,.14,.23),'metal')
    f.box((x, -.35, .20), (1.85, .77, .18), 'stone')
    if rich:
        f.box((x+1.14, -.23, 1.7), (.45, .31, .43), 'metal')
        f.box((x+1.14, -.4, 1.77), (.33, .022, .025), 'black')
        f.box((x-.91, -.14, 2.40), (.50, .13, .25), 'paper')


def _small_canopy(f, width, z=2.95, reach=1.3, roof='roof_teal'):
    # Four-vertex gently sloping canopy with visible underside and fascia.
    verts=[(-width/2,.11,z+.13),(width/2,.11,z+.13),
           (width/2,-reach,z-.20),(-width/2,-reach,z-.20),
           (-width/2,.11,z),(width/2,.11,z),
           (width/2,-reach,z-.31),(-width/2,-reach,z-.31)]
    f.mesh(verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(3,2,6,7),
                  (0,3,7,4),(1,5,6,2)],roof)
    # Standing folded seams retain a readable physical silhouette at oblique views.
    n=max(3,int(width/.42))
    for i in range(n+1):
        x=-width/2+i*width/n
        f.beam((x,.11,z+.16),(x,-reach,z-.17),.033,roof,5)
    f.box((0,-reach,z-.26),(width,.14,.20),'wood')
    for x in (-width*.39,width*.39):
        f.beam((x,-.05,z-.55),(x,-reach*.83,z-.27),.075,'wood')


def _balcony(f, width, z, roof, rich):
    width=min(width,5.2)
    f.box((0,-.75,z),(width,1.6,.20),'wood_light')
    f.box((0,-1.5,z+1.05),(width,.09,.11),'wood')
    count=max(4,int(width/.53))
    for j in range(count+1):
        x=-width/2+j*width/count
        f.box((x,-1.5,z+.51),(.085,.10,1.02),'wood')
    for x in (-width/2,width/2):
        f.box((x,-.78,z+1.05),(.10,1.46,.11),'wood')
        f.box((x,-.78,z+.55),(.08,1.40,.07),'wood')
        f.beam((x,-.09,z-.83),(x,-1.39,z-.04),.10,'wood')


def _shop(f, width, rng, rich):
    """A cut, 40 cm-deep sliding shop entrance and dimensional timber porch."""
    shopw=min(width-1.1,7.2)
    for sign in (-1,1):
        f.box((sign*(shopw/2-.07),.16,1.43),(.14,.44,2.30),'wood')
    for z in (.31,2.53):
        f.box((0,.16,z),(shopw,.44,.15),'wood')
    # Sliding panels carry individual glass panes and rails behind the wall.
    panel_count=4 if shopw>=3.8 else 2
    panelw=(shopw-.28)/panel_count
    for i in range(panel_count):
        cx=-shopw/2+.14+(i+.5)*panelw
        yy=.33+(i%2)*.055
        for sign in (-1,1):
            f.box((cx+sign*(panelw/2-.035),yy,1.43),(.07,.095,2.10),'wood_light')
        f.box((cx,yy,.65),(panelw,.10,.62),'wood_light')
        for z in (1.01,1.60,2.47):
            f.box((cx,yy,z),(panelw,.09,.065),'wood')
        f.mesh([(cx-panelw/2+.07,yy+.045,1.04),(cx+panelw/2-.07,yy+.045,1.04),
                (cx+panelw/2-.07,yy+.045,2.44),(cx-panelw/2+.07,yy+.045,2.44)],
                [(0,1,2,3)],'glass')
    f.box((0,-.20,.18),(shopw+.3,.85,.18),'stone')
    _small_canopy(f,shopw+.65,3.04,1.45,rng.choice(('roof_red','roof_teal','roof_orange')))
    # Plain cloth has modeled folds, thickness and irregular hems. No faux text.
    noren=rng.choice(('sage','fabric','roof_blue'))
    curtains=max(3,int(shopw/1.2))
    for i in range(curtains):
        cw=shopw/curtains-.045
        cx=-shopw/2+(i+.5)*shopw/curtains
        vs=[]
        for layer in (0,.018):
            for row in range(4):
                t=row/3
                for col in range(7):
                    u=col/6
                    fold=.043*math.sin(u*math.tau*2.0+i*.7)*(.35+.65*t)
                    vs.append((cx+(u-.5)*cw,-1.40+fold+layer,2.87-.60*t-.018*math.sin(u*math.pi)))
        fs=[]
        for row in range(3):
            for col in range(6):
                q=row*7+col
                fs.extend(((q,q+1,q+8,q+7),(q+28,q+35,q+36,q+29)))
        fs.extend((21+j,22+j,50+j,49+j) for j in range(6))
        f.mesh(vs,fs,noren)
    if rich and rng.random()<.35:
        # Unlettered timber bench, as seen beside small Konoha businesses.
        f.box((-shopw*.32,-.64,.60),(1.50,.48,.13),'wood_light')
        for x in (-shopw*.32-.58,-shopw*.32+.58):
            f.box((x,-.64,.34),(.12,.39,.52),'wood')


def _gable_roof(f, w, d, h, roof, rich, rng, party=()):
    """Curved eaves, ridge caps and tile courses visible as real geometry."""
    xl=-w/2-(0 if 'left' in party else .64)
    xr=w/2+(0 if 'right' in party else .64)
    ew, ed = w/2+.64, d/2+.78
    rise=rng.uniform(1.75,2.7)
    # Ridge runs along x. Three points in each slope give turned-up eaves.
    cross=[(-ed,h+.13),(-ed+.50,h+.08),(0,h+rise),
           (ed-.50,h+.08),(ed,h+.13)]
    surface=[(x,y,z) for x in (xl,xr) for y,z in cross]
    verts=surface+[(x,y,z-.11) for x,y,z in surface]
    faces=[(i,i+5,i+6,i+1) for i in range(4)]
    faces.extend((i+11,i+16,i+15,i+10) for i in range(4))
    for i in range(4):
        faces.append((i,i+1,i+11,i+10))
        faces.append((i+6,i+5,i+15,i+16))
    faces.extend([(0,10,15,5),(4,9,19,14)])
    f.mesh(verts,faces,roof)
    # Solid roof edge and triangular warm plaster gable ends.
    for x in (-w/2,w/2):
        f.mesh([(x,-d/2,h-.12),(x,d/2,h-.12),(x,0,h+rise-.13)],[(0,1,2)],'cream')
        for sign in (-1,1):
            f.beam((x,0,h+rise),(x,sign*ed,h+.08),.095,'wood')
    for y in (-ed,ed):
        f.box(((xl+xr)/2,y,h+.055),(xr-xl,.15,.20),'wood')
    f.beam((xl,0,h+rise+.11),(xr,0,h+rise+.11),.14,roof,6)
    # Tile divisions are batched low-sided ribs, denser in the main streets.
    rib_count=max(5,int(w/(.63 if rich else 2.6)))
    for i in range(rib_count+1):
        x=xl+i*(xr-xl)/rib_count
        for sign in (-1,1):
            f.beam((x,0,h+rise+.045),(x,sign*(ed-.50),h+.12),.038,roof,4)
            f.beam((x,sign*(ed-.50),h+.12),(x,sign*ed,h+.18),.041,roof,4)
    courses=3 if rich else 0
    for i in range(1,courses+1):
        y=(ed-.50)*i/(courses+1)
        z=h+rise*(1-y/(ed-.50))+.08
        for sign in (-1,1):
            f.beam((xl,sign*y,z),(xr,sign*y,z),.025,roof,4)
    if rich:
        for x in (-w*.36,-w*.18,0,w*.18,w*.36):
            for sign in (-1,1):
                f.box((x,sign*(d/2+.34),h-.10),(.10,.88,.14),'wood_light')
    return h+rise+.3


def _hip_roof(f,w,d,h,roof,rich,party=()):
    ew,ed=w/2+.73,d/2+.73
    xl=-w/2-(0 if 'left' in party else .73)
    xr=w/2+(0 if 'right' in party else .73)
    rise=2.15
    ridge=max(.8,w*.28)
    verts=[(xl,-ed,h+.12),(xr,-ed,h+.12),(xr,ed,h+.12),(xl,ed,h+.12),
           (-ridge,0,h+rise),(ridge,0,h+rise)]
    upper_faces=[(0,1,5,4),(1,2,5),(2,3,4,5),(3,0,4)]
    solid_verts=verts+[(x,y,z-.11) for x,y,z in verts]
    solid_faces=upper_faces+[tuple(i+6 for i in reversed(face)) for face in upper_faces]
    solid_faces.extend(((i+1)%4,i,i+6,(i+1)%4+6) for i in range(4))
    f.mesh(solid_verts,solid_faces,roof)
    for a,b in ((0,1),(1,2),(2,3),(3,0),(0,4),(1,5),(2,5),(3,4),(4,5)):
        f.beam(verts[a],verts[b],.105 if a>=4 or b>=4 else .08,roof,6)
    for y in (-ed,ed):
        f.box(((xl+xr)/2,y,h+.005),(xr-xl,.12,.18),'wood')
    if rich:
        for i in range(1,6):
            t=i/6
            left=xl*(1-t)-ridge*t
            right=xr*(1-t)+ridge*t
            for sign in (-1,1):
                y=sign*ed*(1-t)
                z=h+.12+2.03*t
                f.beam((left,y,z),(right,y,z),.035,roof,4)
    return h+rise+.2


def _tank(f,h,rng,rich):
    x,y=rng.uniform(-1.9,1.9),rng.uniform(-1.0,1.0)
    r=rng.uniform(.69,1.02)
    for dx in (-r*.67,r*.67):
        for dy in (-r*.67,r*.67):
            f.box((x+dx,y+dy,h+.62),(.10,.10,1.20),'metal')
    f.cyl((x,y,h+1.57),r,1.62,'metal',16)
    for z in (h+.87,h+1.58,h+2.28):
        f.cyl((x,y,z),r+.036,.067,'trim',16)
    f.cyl((x,y,h+2.42),r+.09,.24,'roof_dark',16,r2=r*.72)
    f.beam((x+r*.45,y,h+.75),(x+r*.45,y,h+.10),.055,'metal')
    if rich:
        for xoff in (-.31,.31):
            f.beam((x+xoff,y-r-.13,h+.04),(x+xoff,y-r-.13,h+2.18),.033,'metal')
        for i in range(6):
            f.beam((x-.31,y-r-.13,h+.20+i*.33),(x+.31,y-r-.13,h+.20+i*.33),.028,'metal')


def _rect_house(f,w,d,floors,wall,roof,rng,rich,shop,party=()):
    floor=3.32
    h=.26+floors*floor
    f.body_height=h
    f.tiered=False
    f.box((0,0,.18),(w+.26,d+.26,.36),'stone')
    # Physical floor slabs and ceiling; the volume between them is hollow.
    for story in range(1,floors):
        f.box((0,0,.26+story*floor),(w,d,.15),'trim')
    f.box((0,0,h-.07),(w,d,.14),'trim')
    for x in (-w/2+.085,w/2-.085):
        for y in (-d/2+.085,d/2-.085):
            f.box((x,y,h/2),(.18,.18,h),'wood_light')
    facades=[(f.child((0,-d/2,0)),w),(f.child((w/2,0,0),math.pi/2),d),
             (f.child((0,d/2,0),math.pi),w),(f.child((-w/2,0,0),-math.pi/2),d)]
    for side,(ff,span) in enumerate(facades):
        if (side==1 and 'right' in party) or (side==3 and 'left' in party):
            _facade_wall(ff,span,.30,h,[],wall)
            continue
        front=side==0
        count=max(2,int(span/3.6))
        openings=[]
        for story in range(floors):
            z=.27+story*floor+2.04
            for j in range(count):
                x=-span/2+(j+.5)*span/count
                if story==0 and front and (shop or abs(x)<2.0):
                    continue
                # Sparse rear ground-floor windows leave credible service walls.
                if side==2 and story==0 and j%2:
                    continue
                windoww=min(1.85,span/count*.44) if front else 1.35
                openings.append(_opening(x,z,windoww+.20,1.62))
                _window(ff,x,z,windoww,
                        1.42,shutters=(front and story>0 and rng.random()<.5),
                        rich=rich and front)
        if front:
            if shop:
                openings.append(_opening(0,1.43,min(span-1.1,7.2),2.30))
                _shop(ff,span,rng,rich)
            else:
                openings.append(_opening(0,1.395,1.54,2.31))
                _door(ff,0,rich)
                _small_canopy(ff,2.5,2.97,1.03,roof)
            if floors>=2 and rng.random()<(.50 if rich else .20):
                _balcony(ff.child((rng.uniform(-.7,.7),0,0)),
                         min(span*.56,5.2),floor+.19,roof,rich)
        _facade_wall(ff,span,.30,h,openings,wall)
        # Vertical gutters tied back into the upper roof, on real wall edges.
        if side in (0,2):
            xx=span/2-.39
            ff.beam((xx,-.20,.24),(xx,-.20,h-.1),.063,'metal')
            ff.beam((xx,-.20,.30),(xx,-.43,.14),.063,'metal')
            if rich:
                for zz in (1.45,4.10,6.5):
                    if zz<h:
                        ff.box((xx,-.13,zz),(.21,.22,.07),'metal')
    roof_type=rng.random()
    if roof_type<.27:
        left=.12 if 'left' not in party else 0
        right=.12 if 'right' not in party else 0
        f.box(((right-left)/2,0,h+.07),(w+left+right,d+.24,.22),'stone')
        for y in (-d/2,d/2):
            f.box((0,y,h+.50),(w,.22,.86),wall)
        for x in (-w/2,w/2):
            f.box((x,0,h+.50),(.22,d,.86),wall)
        if roof_type<.11:
            f.tiered=True
            # Konoha frequently combines rectangular bases and rooftop drums.
            rr=min(w,d)*rng.uniform(.21,.28)
            _drum_shell(f,rr,h+.105,2.85,1,'cream')
            f.cyl((0,0,h+3.0),rr+.4,.15,'wood',20)
            f.cyl((0,0,h+3.6),rr+.54,1.13,roof,20,r2=rr*.34)
            f.cyl((0,0,h+4.20),rr*.36,.11,roof,16)
            top=h+4.3
        else:
            _tank(f,h+.2,rng,rich)
            f.box((-w*.25,d*.2,h+.73),(2.45,2.1,1.34),'cream')
            f.box((-w*.25,d*.2,h+1.43),(2.65,2.3,.15),roof)
            top=h+2.8
    elif roof_type<.53:
        top=_hip_roof(f,w,d,h,roof,rich,party)
    else:
        top=_gable_roof(f,w,d,h,roof,rich,rng,party)
    if roof_type>=.27 and rng.random()<.22:
        x,y=w*.27,d*.15
        f.box((x,y,h+1.33),(.52,.63,2.28),'stone')
        f.box((x,y,h+2.51),(.74,.82,.15),'roof_dark')
        top=max(top,h+2.6)
    return top


def _round_house(f,w,d,floors,wall,roof,rng,rich,shop):
    r=min(w,d)*.47
    tiered=floors>=3 and rng.random()<.68
    base_floors=floors-1 if tiered else floors
    h=.26+base_floors*3.35
    f.body_height=h
    f.tiered=tiered
    sides=24
    f.cyl((0,0,.18),r+.2,.36,'stone',sides)
    _drum_shell(f,r,.30,h-.30,base_floors,wall,rich,doorway=True)
    for story in range(base_floors+1):
        z=.32+story*3.35
        f.cyl((0,0,z),r+.15,.15,'cream' if story else 'stone',sides)
    ff=f.child((0,-r*math.cos(math.pi/16),0))
    _small_canopy(ff,2.6,roof=roof)
    if base_floors>1 and rng.random()<.43:
        _balcony(ff,3.45,3.55,roof,rich)
    # Stepped drums give the silhouette seen in the anime's village aerials.
    if tiered:
        upper_r=r*rng.uniform(.58,.70)
        f.cyl((0,0,h+.09),r+.65,.22,'wood',sides)
        f.cyl((0,0,h+.81),r+.83,1.31,roof,sides,r2=upper_r+.13)
        upper_z=h+1.43
        upper_h=2.95
        _drum_shell(f,upper_r,upper_z,upper_h,1,
                    'white' if rng.random()<.7 else wall,rich)
        f.cyl((0,0,upper_z+.08),upper_r+.08,.14,'trim',sides)
        top_eave=upper_z+upper_h
        f.cyl((0,0,top_eave),upper_r+.48,.19,'wood',sides)
        f.cyl((0,0,top_eave+.72),upper_r+.66,1.31,roof,sides,r2=.59)
        f.cyl((0,0,top_eave+1.42),.67,.15,roof,16,r2=.49)
        if rich:
            for i in range(16):
                a=math.tau*i/16
                f.beam(((r+.79)*math.sin(a),-(r+.79)*math.cos(a),h+.2),
                       ((upper_r+.14)*math.sin(a),-(upper_r+.14)*math.cos(a),h+1.49),.032,roof,4)
        top=top_eave+1.56
    elif rng.random()<.69:
        rise=rng.uniform(1.7,2.6)
        f.cyl((0,0,h+.10),r+.68,.24,'wood',sides)
        f.cyl((0,0,h+rise/2+.23),r+.78,rise,roof,sides,r2=.47)
        f.cyl((0,0,h+rise+.30),.50,.18,roof,16,r2=.28)
        steps=3 if rich else 1
        for i in range(steps):
            t=(i+.32)/(steps+.3)
            rr=(r+.78)*(1-t)+.47*t
            f.cyl((0,0,h+.25+rise*t),rr+.023,.055,roof,sides,r2=rr-.012)
        if rich:
            for i in range(16):
                a=math.tau*i/16
                f.beam(((r+.75)*math.sin(a),-(r+.75)*math.cos(a),h+.27),
                       (.45*math.sin(a),-.45*math.cos(a),h+rise+.26),.035,roof,4)
        top=h+rise+.45
    else:
        f.cyl((0,0,h+.1),r+.22,.24,'stone',sides)
        # Ring parapet made as quads rather than a solid cylinder covering roof.
        vs=[]
        for z,rr in ((h+.17,r),(h+.85,r),(h+.85,r-.22),(h+.17,r-.22)):
            vs.extend((rr*math.sin(i*math.tau/sides),rr*math.cos(i*math.tau/sides),z) for i in range(sides))
        fs=[]
        for j in range(3):
            for i in range(sides):
                nxt=(i+1)%sides
                fs.append((j*sides+i,j*sides+nxt,(j+1)*sides+nxt,(j+1)*sides+i))
        f.mesh(vs,fs,wall)
        _tank(f,h+.23,rng,rich)
        top=h+2.85
    # Exterior service pipes reinforce the village's mixed old/industrial look.
    for angle in (math.pi*.65,math.pi*1.1):
        px,py=(r+.13)*math.sin(angle),-(r+.13)*math.cos(angle)
        f.beam((px,py,.30),(px,py,h+.48),.093,'metal')
        f.beam((px,py,h+.48),(px*.90,py*.90,h+.48),.093,'metal')
    return top


def _centres(lo,hi,pitch=16.5):
    count=max(1,int((hi-lo)/pitch))
    return [lo+(i+.5)*(hi-lo)/count for i in range(count)]


def _reserved(x,y,w,d,market=False):
    # Include overhangs, exterior decks and storefront canopies in the keepout.
    a,b=w/2+2.0,d/2+2.0
    if max((x+dx)**2+(y+dy)**2 for dx in (-a,a) for dy in (-b,b))>334**2:
        return True
    if y+b>285 or abs(x)-a<12:
        return True
    for sy in (-220,-110,0,110):
        if abs(y-sy)<b+6:
            return True
    for sx in (-200,-100,100,200):
        if abs(x-sx)<a+5:
            return True
    # Named landmarks and generous aprons have priority over regular parcels.
    rects=[(-57,57,171,310),(-128,-52,122,188)]
    if not market:
        rects.extend([(16,44,-157,-128),(16,45,-211,-124)])
    for x0,x1,y0,y1 in rects:
        if x+a>x0 and x-a<x1 and y+b>y0 and y-b<y1:
            return True
    for cx,cy,rr in ((-225,90,48),(225,90,52)):
        dx=max(abs(x-cx)-a,0)
        dy=max(abs(y-cy)-b,0)
        if dx*dx+dy*dy<rr*rr:
            return True
    return False


def _aabb(w,d,rot):
    co,si=abs(math.cos(rot)),abs(math.sin(rot))
    return w*co+d*si,w*si+d*co


def _too_close(a,b,clearance=1.80):
    return (abs(a['x']-b['x'])<(a['ww']+b['ww'])/2+clearance and
            abs(a['y']-b['y'])<(a['dd']+b['dd'])/2+clearance)


def _curated_market():
    """Pre-Pain Ichiraku's neighboring shop row and its back service street.

    The named stall occupies x18..23.8, y-147.75..-140.25. A 2.05 m clear
    service passage remains on its south side. Awnings stop at x16.55 or east,
    so the x12..16.5 pavement stays more than 2.5 m wide.
    """
    entries=[
        (23.4,-133.6,12.3,10.8,3,('right',),None),
        (23.4,-155.8,12.0,10.8,2,('right',),10001),
        (23.4,-168.3,13.0,10.8,3,('left',),10001),
        (23.4,-185.8,11.0,10.8,2,('right',),10002),
        (23.4,-197.55,12.5,10.8,3,('left',),10002),
        (38.0,-134.5,11.0,9.8,2,(),None),
        (38.0,-155.0,12.8,9.8,3,('right',),10003),
        (38.0,-167.0,11.2,9.8,2,('left',),10003),
        (38.3,-185.5,11.6,9.8,3,('right',),10004),
        (38.3,-197.1,11.6,9.8,2,('left',),10004),
    ]
    result=[]
    for i,(x,y,w,d,floors,party,cluster) in enumerate(entries):
        result.append({'x':x,'y':y,'w':w,'d':d,'ww':d,'dd':w,
                       'rotation':-math.pi/2,'round':False,'rich':True,
                       'row':('market',i//5,0),'column':i,'party':party,
                       'cluster':cluster,'market':True,'floors':floors,'shop':i<5})
    return result


def _plans():
    """Parcel limits preserve navigable streets; setbacks vary inside them."""
    rng=random.Random(84327)
    plans=_curated_market()
    rows={}
    segments=[(-327,-205),(-195,-105),(-95,-14),(14,95),(105,195),(205,327)]
    blocks=[(-326,-226),(-214,-116),(-104,-6),(6,104),(116,283)]
    for bi,(y0,y1) in enumerate(blocks):
        for si,(x0,x1) in enumerate(segments):
            for ri,cy in enumerate(_centres(y0,y1)):
                # A shallow, deterministic bend gives side streets changing views.
                row_shift=1.5*math.sin(cy/35+si*.7)
                for ci,cx in enumerate(_centres(x0,x1)):
                    x=cx+row_shift+rng.uniform(-.35,.35)
                    y=cy+1.15*math.sin(cx/37+bi)+rng.uniform(-.30,.30)
                    w,d=rng.uniform(11.3,13.7),rng.uniform(10.5,13.3)
                    rich=abs(x)<63 or (abs(x)<145 and min(abs(y-v) for v in (-220,-110,0,110))<24)
                    roundhouse=rng.random()<.24 and abs(x)>47
                    if roundhouse:
                        w=d=rng.uniform(11.0,13.6)
                    rot=0 if ri%2==0 else math.pi
                    if abs(x)<43:
                        rot=-math.pi/2 if x>0 else math.pi/2
                    elif abs(x)>145:
                        rot+=rng.uniform(-.055,.055)
                    ww,dd=(w,d) if roundhouse else _aabb(w,d,rot)
                    if _reserved(x,y,ww,dd):
                        continue
                    p={'x':x,'y':y,'w':w,'d':d,'ww':ww,'dd':dd,'rotation':rot,
                       'round':roundhouse,'rich':rich,'row':(bi,si,ri),'column':ci,
                       'party':(),'cluster':None}
                    if any(_too_close(p,q) for q in plans):
                        continue
                    plans.append(p)
                    rows.setdefault((bi,si,ri),[]).append(p)
    _connect_frontages(plans,rows)
    _connect_avenue_frontages(plans)

    return plans


def _connect_frontages(plans,rows):
    """Repack existing houses into terraces; reserve the released side courts.

    The anime's irregular urban blocks read as joined masses, with foliage in
    the remaining courts. Counts and main-avenue/market parcels stay fixed.
    """
    cluster=0
    for row_key,row in rows.items():
        eligible=[]
        groups=[]
        for p in row:
            if p['round'] or abs(p['x'])<53:
                if len(eligible)>1: groups.append(eligible)
                eligible=[]
                continue
            if eligible and p['column']!=eligible[-1]['column']+1:
                if len(eligible)>1: groups.append(eligible)
                eligible=[]
            eligible.append(p)
            if len(eligible)==5:
                groups.append(eligible)
                eligible=[]
        if len(eligible)>1: groups.append(eligible)
        for group in groups:
            old_left=min(p['x']-p['ww']/2 for p in group)
            old_right=max(p['x']+p['ww']/2 for p in group)
            rot=math.pi if math.cos(group[0]['rotation'])<0 else 0
            front_sign=1 if rot else -1
            # Align a continuous facade line while varied depths form rear courts.
            fronts=sorted(p['y']+front_sign*p['d']/2 for p in group)
            frontage=fronts[len(fronts)//2]
            span=sum(p['w'] for p in group)
            anchors=(-1,1,0) if sum(row_key)%2 else (1,-1,0)
            replacements=None
            for anchor in anchors:
                left=(old_left if anchor<0 else old_right-span if anchor>0
                      else (old_left+old_right-span)/2)
                proposed=[]
                edge=left
                for p in group:
                    q=dict(p,x=edge+p['w']/2,y=frontage-front_sign*p['d']/2,
                           rotation=rot,ww=p['w'],dd=p['d'])
                    proposed.append(q)
                    edge+=p['w']
                if any(_reserved(q['x'],q['y'],q['ww'],q['dd']) for q in proposed):
                    continue
                if any(_too_close(q,other) for q in proposed for other in plans
                       if all(other is not original for original in group)):
                    continue
                replacements=proposed
                break
            if replacements is None:
                continue
            for i,(p,q) in enumerate(zip(group,replacements)):
                p.update(q)
                party=[]
                if i>0: party.append('left' if rot==0 else 'right')
                if i<len(group)-1: party.append('right' if rot==0 else 'left')
                p['party']=tuple(party)
                p['cluster']=cluster
                p['frontage_length_m']=span
            # Feed the vacated parcel strip to the garden-court allocator first.
            new_left=replacements[0]['x']-replacements[0]['w']/2
            new_right=replacements[-1]['x']+replacements[-1]['w']/2
            for x0,x1 in ((old_left,new_left-1.8),(new_right+1.8,old_right)):
                if x1-x0>3.5:
                    y0=max(q['y']-q['d']/2 for q in replacements)+.35
                    y1=min(q['y']+q['d']/2 for q in replacements)-.35
                    group[0].setdefault('court_candidates',[]).append((x0,x1,y0,y1))
            cluster+=1


def _garden_courts(plans):
    """Select broad residual parcel voids, preserving 1.8m routes around beds."""
    candidates=[]
    for p in plans:
        candidates.extend(p.get('court_candidates',[]))
    # Larger empty bays between rows become courts instead of continuous sand.
    for y in range(-298,271,12):
        for x in range(-310,311,12):
            if abs(x)<53: continue
            candidates.append((x-4.2,x+4.2,y-4.2,y+4.2))
    courts=[]
    for x0,x1,y0,y1 in candidates:
        if x1-x0<3.5 or y1-y0<4.0: continue
        x,y=(x0+x1)/2,(y0+y1)/2
        w,d=x1-x0,y1-y0
        if _reserved(x,y,w,d): continue
        area={'x':x,'y':y,'ww':w,'dd':d}
        if any(_too_close(area,p,clearance=1.8) for p in plans): continue
        if any(_too_close(area,p,clearance=2.0) for p in courts): continue
        courts.append(dict(area,bounds=[x0,x1,y0,y1]))
    return courts


def _connect_avenue_frontages(plans):
    """Join the existing north-south frontage rows without entering the avenue."""
    rows={}
    for p in plans:
        if p.get('market',False) or p['round'] or abs(p['x'])>=43: continue
        key=(p['row'][0],p['row'][1],p['column'])
        rows.setdefault(key,[]).append(p)
    cluster=20000
    for key,row in rows.items():
        row.sort(key=lambda p:p['y'])
        groups=[]
        group=[]
        for p in row:
            if group and p['row'][2]!=group[-1]['row'][2]+1:
                if len(group)>1: groups.append(group)
                group=[]
            group.append(p)
            if len(group)==5:
                groups.append(group)
                group=[]
        if len(group)>1: groups.append(group)
        for group in groups:
            west=group[0]['x']>0
            sign=-1 if west else 1
            rot=-math.pi/2 if west else math.pi/2
            frontage=sorted(p['x']+sign*p['d']/2 for p in group)[len(group)//2]
            old_bottom=min(p['y']-p['w']/2 for p in group)
            old_top=max(p['y']+p['w']/2 for p in group)
            span=sum(p['w'] for p in group)
            replacement=None
            for anchor in (-1,1,0):
                bottom=(old_bottom if anchor<0 else old_top-span if anchor>0
                        else (old_bottom+old_top-span)/2)
                edge=bottom
                proposed=[]
                for p in group:
                    proposed.append(dict(p,x=frontage-sign*p['d']/2,y=edge+p['w']/2,
                                         ww=p['d'],dd=p['w'],rotation=rot))
                    edge+=p['w']
                if any(_reserved(q['x'],q['y'],q['ww'],q['dd']) for q in proposed): continue
                if any(_too_close(q,other) for q in proposed for other in plans
                       if all(other is not original for original in group)): continue
                replacement=proposed
                break
            if replacement is None: continue
            for i,(p,q) in enumerate(zip(group,replacement)):
                p.update(q)
                party=[]
                if i>0: party.append('right' if west else 'left')
                if i<len(group)-1: party.append('left' if west else 'right')
                p['party']=tuple(party)
                p['cluster']=cluster
                p['frontage_length_m']=span
            bottom=replacement[0]['y']-replacement[0]['w']/2
            top=replacement[-1]['y']+replacement[-1]['w']/2
            for y0,y1 in ((old_bottom,bottom-1.8),(top+1.8,old_top)):
                if y1-y0<3.5: continue
                x0=max(q['x']-q['d']/2 for q in replacement)+.35
                x1=min(q['x']+q['d']/2 for q in replacement)-.35
                group[0].setdefault('court_candidates',[]).append((x0,x1,y0,y1))
            cluster+=1


def _build_garden_court(builder,court,index):
    """Raised soil, real coping, and a slotted surface drain bound each court."""
    x,y,w,d=(court[k] for k in ('x','y','ww','dd'))
    f=Frame(builder,x,y)
    f.box((0,0,.20),(w,d,.40),'stone')
    f.box((0,0,.413),(w-.30,d-.30,.036),'grass')
    colliders=[_collider(f,w-.30,d-.30,.431)]
    for xx in (-w/2+.075,w/2-.075):
        f.box((xx,0,.447),(.15,d,.085),'stone')
        colliders.append(_collider(f,.15,d,.4895,local=(xx,0,0)))
    for yy in (-d/2+.075,d/2-.075):
        f.box((0,yy,.447),(w-.30,.15,.085),'stone')
        colliders.append(_collider(f,w-.30,.15,.4895,local=(0,yy,0)))
    # The channel is built into the front stone coping, never across a route.
    yy=-d/2+.21
    f.box((0,yy,.437),(w-.46,.085,.016),'metal')
    for i in range(max(3,int((w-.5)/.34))):
        xx=-w/2+.32+i*.34
        f.box((xx,yy,.451),(.04,.12,.018),'stone')
    for collider in colliders: collider['building_id']='garden_court_%03d'%index
    rng=random.Random(538+index)
    trees=[]
    # Larger courts carry a broad canopy; smaller courts stay low and planted.
    if min(w,d)>=5.0:
        height=rng.uniform(8.5,12.8)
        trees.append({'x':x,'y':y,'z':.431,'height':height,'rotation':rng.random()*math.tau,
                      'trunk_radius':height*.018,'collider_height':height*.37})
    shrubs=[]
    for sign in (-1,1):
        shrubs.append({'x':x+sign*w*.24,'y':y-sign*d*.22,'z':.431,
                       'height':rng.uniform(1.3,2.2),'rotation':rng.random()*math.tau})
    return colliders,trees,shrubs


def _collider(f,w,d,h,shape='box',radius=None,local=(0,0,0)):
    x,y,z=f.p((local[0],local[1],local[2]+h/2))
    value={'shape':shape,'x':x,'y':y,'z':z,'width':w,'depth':d,
           'height':h,'rotation_z':f.rot}
    if radius is not None:
        value['radius']=radius
    return value


def _courtyard(f,w,d):
    """A little shared-service yard; wall colliders accompany the geometry."""
    colliders=[]
    extent=w*.38
    wall_h=1.03
    for x in (-extent,extent):
        f.box((x,d/2+1.10,wall_h/2),(.18,2.20,wall_h),'plaster')
        f.box((x,d/2+1.10,wall_h+.045),(.26,2.28,.12),'roof_dark')
        colliders.append(_collider(f,.22,2.28,wall_h+.10,local=(x,d/2+1.10,0)))
    # Split rear wall leaves an opening through the yard for pedestrians.
    segment=extent-.67
    for sign in (-1,1):
        x=sign*(.67+segment/2)
        f.box((x,d/2+2.20,wall_h/2),(segment,.18,wall_h),'plaster')
        f.box((x,d/2+2.20,wall_h+.045),(segment+.07,.26,.12),'roof_dark')
        colliders.append(_collider(f,segment+.07,.26,wall_h+.10,local=(x,d/2+2.20,0)))
    f.box((-extent*.64,d/2+.70,.37),(.8,.72,.72),'wood_light')
    return colliders


def build_districts():
    rng=random.Random(18746)
    builders={}
    metadata=[]
    colliders=[]
    planting=[]
    courtyard_trees=[]
    courtyard_shrubs=[]
    plans=_plans()
    courts=_garden_courts(plans)
    walls=['plaster','cream','cream','white','white','peach','sage','ochre']
    roofs=['roof_red','roof_red','roof_orange','roof_orange','roof_teal','roof_blue','roof_dark']
    for index,p in enumerate(plans):
        x,y,w,d,rot=(p[k] for k in ('x','y','w','d','rotation'))
        rich,roundhouse=p['rich'],p['round']
        bx,by=math.floor((x+350)/55),math.floor((y+350)/55)
        block_id='B%02d_%02d'%(bx,by)
        if block_id not in builders:
            builders[block_id]=Builder('Village · Block '+block_id+' · buildings')
        f=Frame(builders[block_id],x,y,rot=rot)
        floors=p.get('floors',rng.choices((2,3,4),(.54,.40,.06))[0])
        if roundhouse:
            floors=rng.choices((2,3,4,5),(.16,.43,.34,.07))[0]
        shop=p.get('shop',rich and not roundhouse and rng.random()<.52)
        wall,roof=rng.choice(walls),rng.choice(roofs)
        if roundhouse:
            top=_round_house(f,w,d,floors,wall,roof,rng,rich,shop)
            radius=min(w,d)*.47
            body=_collider(f,radius*2,radius*2,f.body_height,'cylinder',radius)
        else:
            top=_rect_house(f,w,d,floors,wall,roof,rng,rich,shop,p['party'])
            body=_collider(f,w,d,f.body_height)
        body['building_id']='house_%03d'%index
        colliders.append(body)
        # The vegetation owner supplies actual plant assets for these positions.
        pots=[]
        if rich and not roundhouse:
            for xx in (-w*.40,w*.40):
                px,py,pz=f.p((xx,-d/2-.48,.12))
                pot={'x':px,'y':py,'z':pz,'kind':'potted_shrub',
                     'scale':.75 if shop else 1.0,'building_id':body['building_id']}
                pots.append(pot)
                planting.append(pot)
        # Yard placement is checked against every neighbor and all keepouts.
        # It stays inside the house's parcel, away from main-avenue entrances.
        if not shop and not roundhouse and rng.random()<.32:
            yc=f.p((0,d/2+1.15,0))
            yw,yd=_aabb(w*.8,2.65,rot)
            yard={'x':yc[0],'y':yc[1],'ww':yw,'dd':yd}
            if (not _reserved(yard['x'],yard['y'],yw,yd) and
                not any(_too_close(yard,q,clearance=.9) for q in plans if q is not p) and
                not any(_too_close(yard,court,clearance=1.8) for court in courts)):
                walls_colliders=_courtyard(f,w,d)
                for c in walls_colliders:
                    c['building_id']=body['building_id']+'_yard'
                colliders.extend(walls_colliders)
        metadata.append({'x':round(x,3),'y':round(y,3),'w':round(p['ww'],3),
                         'd':round(p['dd'],3),'height':round(top,3),
                         'stories':floors,'type':'round' if roundhouse else 'rect',
                         'shop':shop,'roof':roof,'rotation':rot,'block_id':block_id,
                         'building_id':body['building_id'],'tiered':f.tiered,
                         'attached_cluster':p['cluster'],'body_height':f.body_height,
                         'local_width':w,'local_depth':d,'collision_footprint':body,
                         'curated_market':p.get('market',False),'planting_positions':pots,
                         'facade_recess_m':.31,
                         'frontage_length_m':p.get('frontage_length_m',w)})
    garden_patches=[]
    for index,court in enumerate(courts):
        bx,by=math.floor((court['x']+350)/55),math.floor((court['y']+350)/55)
        block_id='B%02d_%02d'%(bx,by)
        if block_id not in builders:
            builders[block_id]=Builder('Village · Block '+block_id+' · buildings')
        court_colliders,trees,shrubs=_build_garden_court(builders[block_id],court,index)
        colliders.extend(court_colliders)
        courtyard_trees.extend(trees)
        courtyard_shrubs.extend(shrubs)
        x0,x1,y0,y1=court['bounds']
        garden_patches.append({'id':'garden_court_%03d'%index,
                               'polygon':[[x0,y0],[x1,y0],[x1,y1],[x0,y1]],
                               'surface_z':.431,'area_m2':court['ww']*court['dd'],
                               'bounds':court['bounds'],'built_geometry':True})
    mesh_count=0
    face_count=0
    for builder in builders.values():
        face_count+=sum(len(fs) for vs,fs in builder.data.values())
        mesh_count+=len(builder.flush())
    return {'count':len(metadata),'buildings':metadata,'faces':face_count,
            'meshes':mesh_count,'chunks':len(builders),'chunk_size_m':55,
            'colliders':colliders,'units':'metres','opaque_building_interiors':True,
            'window_recess_m':.31,'hollow_facades':True,'planting':planting,
            'reference_images':REFERENCE_IMAGES,
            'density_reference':'https://naruto.fandom.com/wiki/Konohagakure',
            'garden_patches':garden_patches,'courtyard_trees':courtyard_trees,
            'courtyard_shrubs':courtyard_shrubs,
            'market_ground_bounds':[12,44,-211,-123],
            'market_walkways':[
                {'bounds':[12,16.55,-209,-123],'clear_width':4.55},
                {'bounds':[28.8,31.6,-204,-126],'clear_width':2.8},
                {'bounds':[18,24,-149.8,-147.75],'clear_width':2.05}]}
