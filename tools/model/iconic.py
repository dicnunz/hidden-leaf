import math, random
from common import Builder, text, leaf_symbol

def ring(b,c,r1,r2,z,h,mat,start=0,end=math.tau,n=128):
    x,y=c
    for i in range(n):
        a=start+(end-start)*i/n; q=start+(end-start)*(i+1)/n
        v=[(x+r*math.cos(t),y+r*math.sin(t),zz) for zz in [z,z+h] for r,t in [(r1,a),(r2,a),(r2,q),(r1,q)]]
        b.mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)

def _surface(b,x0,x1,y0,y1,step,z,mat):
    nx=max(1,math.ceil((x1-x0)/step)); ny=max(1,math.ceil((y1-y0)/step))
    vertices=[]
    for j in range(ny+1):
        yy=y0+(y1-y0)*j/ny
        for i in range(nx+1):
            xx=x0+(x1-x0)*i/nx
            # Worn packed earth has slight physical variation beneath the material.
            rise=.018*math.sin(xx*.72+yy*.13)*math.sin(yy*.39)+.011*math.sin(xx*1.41-yy*.67)
            vertices.append((xx,yy,z+rise))
    b.mesh(vertices,[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(ny) for i in range(nx)],mat)

def build_ground():
    b=Builder('01 · Village ground and streets')
    b.cyl((0,0,-.7),6000,1.2,'grass',n=160)
    # Shallow mesh undulation, rather than an uninterrupted flat color disk.
    _surface(b,-354,354,-354,290,3.8,.09,'earth')
    _surface(b,-11,11,-360,250,1.8,.18,'road')
    for x in [-200,-100,100,200]:
        ym=math.sqrt(342**2-x*x)
        _surface(b,x-5,x+5,-ym,ym,2.0,.18,'road')
    for y in [-220,-110,0,110]:
        xm=math.sqrt(342**2-y*y)
        _surface(b,-xm,xm,y-6,y+6,2.,.188,'road')
    ring(b,(0,0),331,342,.11,.07,'road')
    _surface(b,-37.5,37.5,155,245,1.8,.19,'road')
    _surface(b,-120,-50,107.5,132.5,1.8,.21,'road')
    _surface(b,-8.5,8.5,-472,-348,1.8,.19,'road')
    # Open stone drains, with a recessed bed, vertical channel walls, and joints.
    rng=random.Random(24)
    for sign in [-1,1]:
        xx=sign*12.2
        for ya,yb in [(-335,-227),(-213,-117),(-103,-7),(7,103),(117,178)]:
            length=yb-ya
            for i in range(math.ceil(length/.62)):
                y=ya+(i+.5)*length/math.ceil(length/.62)
                ll=length/math.ceil(length/.62)-.018
                b.box((xx,y,.21),(.32,ll,.30),'stone')
                b.box((xx-sign*.59,y,.13),(.12,ll,.20),'stone')
                b.box((xx-sign*.37,y,.062),(.38,ll,.048),'rock_shadow')
    # Smaller, staggered pavement slabs give sidewalks credible scale.
    for sign in [-1,1]:
        for row in range(3):
            xx=sign*(12.54+row*.70)
            for i in range(643):
                yy=-333+i*.79+(row%2)*.39
                if any(abs(yy-v)<7.8 for v in [-220,-110,0,110]):continue
                b.box((xx,yy,.23+rng.uniform(-.008,.008)),(.68,.765,.10),rng.choice(['stone','stone','plaster']))
    b.flush()

def build_walls_gate():
    b=Builder('02 · Konoha defensive wall')
    start=-math.pi/2+.063; end=3*math.pi/2-.063
    ring(b,(0,0),349,354,0,19,'ochre',start,end,n=250)
    ring(b,(0,0),348.5,354.5,18.8,.8,'roof_teal',start,end,n=250)
    ring(b,(0,0),348.8,354.2,1.2,.8,'stone',start,end,n=250)
    b.flush()
    b=Builder('03 · Main gate')
    # Shippuden gate reference: tall plaster wall, shallow tiled cap, pale arch.
    for x in [-26,26]:
        b.box((x,-352,12),(12,6,24),'ochre')
        b.cyl((x+math.copysign(7,x),-356,12),1.5,24,'stone',n=40)
        b.cyl((x+math.copysign(7,x),-356,24),1.7,.7,'metal',n=40)
        b.box((x,-352,24.2),(14,8,.65),'roof_teal')
        b.box((x,-356,1.0),(13,1,2),'stone')
    # Continuous stone arch: the soffit follows the curve without stair-stepped boxes.
    n=160; v=[]
    for yy in [-355.,-349.]:
        for upper in [False,True]:
            for i in range(n+1):
                xx=-20+40*i/n
                low=20.7+2.4*math.sqrt(max(0,1-(xx/20)**2))
                v.append((xx,yy,26.3 if upper else low))
    a0=0;a1=n+1;a2=2*(n+1);a3=3*(n+1)
    faces=[]
    for i in range(n):
        faces += [(a0+i,a0+i+1,a1+i+1,a1+i),(a2+i,a3+i,a3+i+1,a2+i+1),
                  (a0+i,a2+i,a2+i+1,a0+i+1),(a1+i,a1+i+1,a3+i+1,a3+i)]
    faces += [(a0,a1,a3,a2),(a0+n,a2+n,a3+n,a1+n)]
    b.mesh(v,faces,'cream')
    # Individual fitted arch stones follow the soffit, with narrow mortar seams.
    for i in range(50):
        x0=-20+40*i/50+.012; x1=-20+40*(i+1)/50-.012
        z0=20.7+2.4*math.sqrt(max(0,1-(x0/20)**2))
        z1=20.7+2.4*math.sqrt(max(0,1-(x1/20)**2))
        b.mesh([(x0,-355.30,z0),(x1,-355.30,z1),(x1,-355.30,z1+.52),(x0,-355.30,z0+.52),
                (x0,-354.99,z0),(x1,-354.99,z1),(x1,-354.99,z1+.52),(x0,-354.99,z0+.52)],
               [(0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7),(0,3,7,4),(1,5,6,2)],'stone')
    b.box((0,-352,26.55),(70,9,.65),'roof_teal')
    for xx in range(-35,36):
        b.beam((xx,-356.4,26.8),(xx,-347.6,26.8),.14,'roof_teal',n=8)
    leaf_symbol(b,(0,-355.5,24.6),2.0,'red')
    text('忍',(-5.2,-355.52,24.65),1.95,'red',name='Gate left shinobi inscription')
    text('忍',(5.2,-355.52,24.65),1.95,'red',name='Gate right shinobi inscription')
    # Open green doors swing inward. Near-frontal panels retain the painted kana.
    for side,char in [(-1,'あ'),(1,'ん')]:
        angle=-side*.62
        cx=side*15.8;cy=-348.2
        b.box((cx,cy,10.7),(8.2,.62,21.4),'sage',angle)
        for h in [1,20.5]:b.box((cx,cy-.38,h),(8.3,.15,.28),'metal',angle)
        for u in [-3.8,3.8]:
            b.box((cx+u*math.cos(angle),cy+u*math.sin(angle),10.7),(.2,.75,21.4),'roof_teal',angle)
        ob=text(char,(cx,cy-.4,11.6),5.2,'red',name='Gate door '+char)
        ob.rotation_euler=(math.pi/2,0,angle)
    for side in [-1,1]:
        x=side*38
        b.box((x,-360,2.1),(9,7,4.2),'plaster')
        b.box((x,-363.6,2.35),(5,.13,1.55),'glass')
        for u in [-2.5,0,2.5]:b.box((x+u,-363.72,2.35),(.14,.2,1.75),'wood')
        b.box((x,-360,4.5),(10.4,8.8,.6),'roof_teal')
    b.flush()

def _windowed_drum(b,cx,cy,r,z0,z1,count,ww,hh,rows,mat='red'):
    """Cylindrical masonry is built around actual 32cm-deep window openings."""
    step=math.tau/count; half=ww/(2*r); depth=.32
    heights=sorted(set([z0,z1]+[v for h in rows for v in [h-hh/2,h+hh/2] if z0<v<z1]))
    def panel(a0,a1,lo,hi):
        n=max(1,math.ceil((a1-a0)*r/.5)); vertices=[]
        for rr,zz in [(r,lo),(r,hi),(r-depth,lo),(r-depth,hi)]:
            vertices += [(cx+rr*math.cos(a0+(a1-a0)*k/n),cy+rr*math.sin(a0+(a1-a0)*k/n),zz) for k in range(n+1)]
        aa=n+1;faces=[]
        for k in range(n):
            faces += [(k,k+1,aa+k+1,aa+k),(2*aa+k,3*aa+k,3*aa+k+1,2*aa+k+1),
                      (aa+k,aa+k+1,3*aa+k+1,3*aa+k),(k,2*aa+k,2*aa+k+1,k+1)]
        faces += [(0,aa,3*aa,2*aa),(n,2*aa+n,3*aa+n,aa+n)]
        b.mesh(vertices,faces,mat)
    for i in range(count):
        a=i*step
        panel(a-step/2,a-half,z0,z1);panel(a+half,a+step/2,z0,z1)
        for lo,hi in zip(heights,heights[1:]):
            mid=(lo+hi)/2
            if not any(abs(mid-h)<hh/2-.001 for h in rows):panel(a-half,a+half,lo,hi)
        for h in rows:
            rr=r-depth+.008
            b.mesh([(cx+rr*math.cos(a-half),cy+rr*math.sin(a-half),h-hh/2),
                    (cx+rr*math.cos(a+half),cy+rr*math.sin(a+half),h-hh/2),
                    (cx+rr*math.cos(a+half),cy+rr*math.sin(a+half),h+hh/2),
                    (cx+rr*math.cos(a-half),cy+rr*math.sin(a-half),h+hh/2)],[(0,1,2,3)],'glass')
            b.box((cx+(r-.14)*math.cos(a),cy+(r-.14)*math.sin(a),h-hh/2-.045),(ww+.16,.42,.09),'cream',a+math.pi/2)

def build_hokage():
    y=234
    b=Builder('04 · Hokage Residence')
    # Three adjacent red cylinders, stepped orange eaves and white flat roofs.
    for side in [-1,1]:
        xx=side*33; yy=y+13
        _windowed_drum(b,xx,yy,18,0,18.8,30,.8,1.5,[7.4,12.2])
        b.cyl((xx,yy,19.5),20.1,3.8,'roof_orange',n=96,r2=15.7)
        b.cyl((xx,yy,24.1),15.7,5.4,'red',n=96)
        b.cyl((xx,yy,27.15),16.3,.7,'cream',n=96)
        b.cyl((xx,yy,27.55),15.8,.15,'white',n=96)
        for i in range(30):
            a=math.tau*i/30
            for h in [7.4,12.2]:
                pass # Glazing is within the drum's actual openings.
        for i in range(86):
            a=math.tau*i/86
            b.beam((xx+20.12*math.cos(a),yy+20.12*math.sin(a),17.63),(xx+15.72*math.cos(a),yy+15.72*math.sin(a),21.42),.065,'roof_orange',n=5)
    b.cyl((0,y,.35),31.3,.7,'stone',n=128)
    b.cyl((0,y,3.5),30,6.3,'red',n=128)
    b.cyl((0,y,8.0),32.5,3.4,'roof_orange',n=128,r2=27)
    _windowed_drum(b,0,y,27,9.7,24.3,54,.78,1.45,[14.7,19.4])
    b.cyl((0,y,25.6),31.6,4.7,'roof_orange',n=128,r2=20.8)
    b.cyl((0,y,32.0),20.8,8.1,'red',n=128)
    b.cyl((0,y,36.25),21.3,.55,'cream',n=128)
    b.cyl((0,y,36.6),20.75,.15,'white',n=128)
    # Inward sloping white buttresses sit on the flat upper roof.
    for i in range(10):
        a=math.tau*i/10
        b.beam((20.4*math.cos(a),y+20.4*math.sin(a),36.85),(16.8*math.cos(a),y+16.8*math.sin(a),38.0),.55,'cream',n=4,r2=.38)
    for z0,z1,r0,r1 in [(6.32,9.72,32.53,27.03),(23.28,27.98,31.63,20.83)]:
        for i in range(140):
            a=math.tau*i/140
            b.beam((r0*math.cos(a),y+r0*math.sin(a),z0),(r1*math.cos(a),y+r1*math.sin(a),z1),.07,'roof_orange',n=5)
    # Narrow windows repeat around the middle red wall.
    for i in range(54):
        a=math.tau*i/54
        for h in [14.7,19.4]:
            pass # Window panes sit within the recessed masonry openings.
            b.box((27.13*math.cos(a),y+27.13*math.sin(a),h-.77),(.88,.2,.11),'cream',a+math.pi/2)
    for i in range(34):
        a=math.tau*i/34
        if abs(a-1.5*math.pi)<.25:continue
        b.box((30.06*math.cos(a),y+30.06*math.sin(a),3.35),(.52,.3,5.4),'cream',a+math.pi/2)
        b.box((30.04*math.cos(a+.055),y+30.04*math.sin(a+.055),3.45),(1.8,.14,4.65),'red',a+math.pi/2)
    # Grey conduits loop across the upper skirt, as in the reference.
    for center in [4.0,4.7,5.4]:
        points=[]
        for i in range(43):
            t=math.tau*i/42
            a=center+.28*math.cos(t);r=25.9+3.9*math.sin(t)
            h=23.28+(31.63-r)/(31.63-20.83)*4.7+.19
            points.append((r*math.cos(a),y+r*math.sin(a),h))
        b.line(points,.13,'metal',n=8)
    b.beam((0,y-20.95,30.5),(0,y-21.5,30.5),3.5,'metal',n=72)
    b.beam((0,y-21.5,30.5),(0,y-21.6,30.5),3.2,'red',n=72)
    text('火',(0,y-21.72,30.6),5.2,'black',name='Hokage fire crest')
    b.box((0,y-30.1,3.3),(8.0,.2,5.2),'wood')
    b.box((0,y-30.24,3.3),(6.7,.14,4.8),'glass')
    for xx in [-3.25,0,3.25]:b.box((xx,y-30.36,3.3),(.17,.16,4.9),'cream')
    for i in range(4):b.box((0,y-31.8-i*.6,.37-i*.073),(11+i*.5,.65,.15),'stone')
    b.flush()

def street_furniture():
    b=Builder('05 · Street furniture and utilities')
    rng=random.Random(91)
    for side in [-1,1]:
        x=side*15.1
        for y in [-308,-274,-244,-186,-153,-126,-80,-42,25,65,137,170]:
            # Tall utilitarian wooden poles, crossarms, insulators and wires.
            b.cyl((x,y,4.5),.18,9,'wood',n=10)
            b.box((x,y,8.3),(2.3,.15,.16),'wood')
            for dx in [-.9,.9]:
                b.cyl((x+dx,y,8.5),.11,.3,'paper',n=8)
            b.beam((x,y,6.4),(x-side*1.35,y,6.4),.08,'metal')
            b.cyl((x-side*1.35,y,6.13),.42,.4,'metal',n=16,r2=.18)
            b.cyl((x-side*1.35,y,5.94),.32,.05,'paper',n=16)
        ys=[-308,-274,-244,-186,-153,-126,-80,-42,25,65,137,170]
        for a,c in zip(ys,ys[1:]):
            for dx in [-.9,.9]:
                pts=[(x+dx,a+(c-a)*t/12,8.6-1.0*math.sin(math.pi*t/12)) for t in range(13)]
                b.line(pts,.024,'black',n=4)
    for x,y in [(-17,-290),(17,-230),(-16,-190),(16,-90),(-16,50),(18,145)]:
        b.box((x,y,.65),(1.55,.56,.15),'wood_light')
        for dx in [-.55,.55]: b.box((x+dx,y,.32),(.15,.4,.64),'wood')
        b.box((x,y+.2,1.02),(1.55,.1,.48),'wood_light')
    # Direction signs are in-world objects, not interface overlays.
    for x,y,label in [(-14.5,-205,'火影邸 ↑'),(14.5,-112,'一楽 ↓'),(-14.5,102,'忍者学校 ←')]:
        b.cyl((x,y,1.65),.095,3.3,'wood',n=8)
        b.box((x,y,2.9),(2.3,.18,.7),'wood_light')
        text(label,(x,y-.105,2.92),.32,'paper')
    b.flush()

def build_iconic():
    build_ground(); build_walls_gate(); build_hokage(); street_furniture()
    return {'radius_m':354,'main_gate':(0,-351,0),'hokage_tower':(0,234,0),'tower_height_m':38.7}
