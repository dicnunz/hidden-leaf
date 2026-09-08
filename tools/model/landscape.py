"""Hokage Rock relief sculpture and broadleaf landscape, in life-size metres."""
import math
import random
from common import Builder, MATS, material, leaf_symbol


def _lerp_profile(value, points):
    for (a, va), (b, vb) in zip(points, points[1:]):
        if value <= b:
            t = max(0.0, min(1.0, (value-a)/(b-a)))
            return va+(vb-va)*t
    return points[-1][1]


def _gauss(x, z, cx, cz, sx, sz):
    return math.exp(-((x-cx)/sx)**2-((z-cz)/sz)**2)


# Physical proportion controls are intentionally different for each portrait.
_FACE_PROFILES={
    'Hashirama':dict(width=23.4,height=28.2,jaw=1.08,chin=1.05,depth=14.4,cheek=3.2,
                     nose=6.2,nose_width=.145,socket=2.85,brow=2.65,brow_slope=.095,
                     eye_rise=.005,eye_open=.037,lip=.78,age=.18),
    'Tobirama':dict(width=24.0,height=26.8,jaw=1.12,chin=.96,depth=14.0,cheek=4.0,
                    nose=6.7,nose_width=.155,socket=3.55,brow=3.10,brow_slope=.15,
                    eye_rise=.025,eye_open=.029,lip=.62,age=.28),
    'Hiruzen':dict(width=22.7,height=26.1,jaw=1.04,chin=1.12,depth=13.4,cheek=3.6,
                   nose=5.9,nose_width=.162,socket=3.85,brow=2.15,brow_slope=.015,
                   eye_rise=-.012,eye_open=.031,lip=.60,age=1.0),
    'Minato':dict(width=22.0,height=27.6,jaw=.89,chin=.80,depth=13.5,cheek=2.8,
                  nose=4.95,nose_width=.127,socket=2.50,brow=1.9,brow_slope=.055,
                  eye_rise=.017,eye_open=.041,lip=.82,age=0.),
    'Tsunade':dict(width=21.8,height=27.0,jaw=.85,chin=.86,depth=13.0,cheek=2.65,
                   nose=4.1,nose_width=.116,socket=2.05,brow=1.3,brow_slope=-.025,
                   eye_rise=.018,eye_open=.043,lip=1.26,age=.08),
}
_FACE_STYLE=_FACE_PROFILES['Hashirama']


def _hash2(x,y,seed=0):
    n=math.sin(x*127.1+y*311.7+seed*74.73)*43758.5453123
    return 2*(n-math.floor(n))-1


def _noise2(x,y,seed=0):
    ix,iy=math.floor(x),math.floor(y)
    fx,fy=x-ix,y-iy
    sx,sy=fx*fx*(3-2*fx),fy*fy*(3-2*fy)
    a,b=_hash2(ix,iy,seed),_hash2(ix+1,iy,seed)
    c,d=_hash2(ix,iy+1,seed),_hash2(ix+1,iy+1,seed)
    return (a+(b-a)*sx)*(1-sy)+(c+(d-c)*sx)*sy


def _fbm(x,y,seed=0):
    return (_noise2(x,y,seed)+.48*_noise2(x*2.13,y*2.13,seed+3)+
            .23*_noise2(x*4.37,y*4.37,seed+7)+.105*_noise2(x*8.73,y*8.73,seed+11))/1.815


def _face_width(v, female=False):
    p=_FACE_STYLE
    profile=[(-1.10,.015),(-1.02,.235),(-.88,.47),(-.64,.655),(-.32,.795),
             (.06,.88),(.37,.855),(.73,.81),(1.02,.72),(1.17,.48),(1.24,.012)]
    w=_lerp_profile(v,profile)
    lower=max(0.,min(1.,(-.15-v)/.68))
    chin=max(0.,min(1.,(-.82-v)/.20))
    return w*(1+(p['jaw']-1)*lower)*(1+(p['chin']-1)*chin)


def _eye_level(u):
    return .205+_FACE_STYLE['eye_rise']*(abs(u)-.35)/.2


def _face_depth(u,v,female=False,elder=False):
    """Continuous facial anatomy; orbit, nasal, lip and age cuts are in the mesh."""
    p=_FACE_STYLE
    width=_face_width(v)
    edge=max(0.,1-(abs(u)/max(width,.001))**2.7)
    vertical=min(1.,max(0.,(v+1.10)/.28),max(0.,(1.24-v)/.31))
    d=p['depth']*edge**.52*vertical**.5
    # Broad forehead and mid-face transition into individually shaped cheek planes.
    d+=2.1*_gauss(u,v,0,.64,.68,.34)
    d+=p['cheek']*(_gauss(u,v,-.56,-.04,.245,.235)+_gauss(u,v,.56,-.04,.245,.235))
    d+=1.3*_gauss(u,v,0,-.43,.38,.27)
    d+=(3.0 if not female else 2.3)*_gauss(u,v,0,-.855,.31,.17)
    for sign in (-1,1):
        eye_v=_eye_level(u)
        d-=p['socket']*_gauss(u,v,sign*.355,eye_v,.235,.084)
        brow_v=.35+p['brow_slope']*(abs(u)-.35)
        d+=p['brow']*_gauss(u,v,sign*.35,brow_v,.25,.062)
        d+=.80*_gauss(u,v,sign*.39,eye_v-.084,.22,.036)
        # The glabella and inner eye fold remain continuous with the nose root.
        d+=.62*_gauss(u,v,sign*.145,.27,.071,.091)
    # A low-rooted straight nasal ridge and two integrated alar planes.
    ridge=max(0.,1-abs(u)/p['nose_width'])**.72
    bridge=_lerp_profile(v,[(-.28,0),(-.18,.68),(-.085,1.0),(.12,.67),(.37,.23),(.48,0)])
    if -.28<v<.48:
        d+=ridge*bridge*p['nose']
    alar=.13 if not female else .109
    d+=2.05*(_gauss(u,v,-alar,-.16,.088,.064)+_gauss(u,v,alar,-.16,.088,.064))
    d-=1.15*(_gauss(u,v,-alar,-.212,.043,.025)+_gauss(u,v,alar,-.212,.043,.025))
    d-=.50*_gauss(u,v,0,-.325,.036,.065)
    d+=p['lip']*_gauss(u,v,0,-.43,.245,.038)
    d+=p['lip']*.85*_gauss(u,v,0,-.506,.22,.043)
    d-=1.05*_gauss(u,v,0,-.467,.26,.019)
    d-=.70*_gauss(u,v,0,-.606,.255,.036)
    age=p['age']
    if age:
        for sign in (-1,1):
            d-=age*.98*_gauss(u,v,sign*.32,-.35,.039,.20)
            d-=age*.80*_gauss(u,v,sign*.53,.033,.18,.022)
            d-=age*.55*_gauss(u,v,sign*.62,.115,.13,.026)
        for zz in (.57,.66,.75):
            d-=age*.32*_gauss(u,v,0,zz,.52,.014)
    # Shallow weathering does not overwhelm the carved expression.
    d+=.10*_fbm(u*12.7,v*12.7,13)
    return max(0.,d)*min(1.,edge*5.)


def _relief_surface(b,cx,cz,female=False,elder=False):
    width,height=_FACE_STYLE['width'],_FACE_STYLE['height']
    nv,nu=94,78
    verts=[]
    for j in range(nv+1):
        v=-1.10+2.34*j/nv
        half=_face_width(v)
        for i in range(nu+1):
            u=(-1+2*i/nu)*half
            xx,zz=cx+width*u,cz+height*v
            edge_fade=max(0.,min(1.,(abs(u)/max(half,.001)-.88)/.12))
            edge_fade=max(edge_fade,max(0.,min(1.,(abs(v-.07)-1.10)/.07)))
            edge_fade=edge_fade*edge_fade*(3-2*edge_fade)
            back=315+(_cliff_front_y(xx,zz)+1.2-315)*edge_fade
            verts.append((xx,back-_face_depth(u,v,female,elder),zz))
    faces=[]
    for j in range(nv):
        for i in range(nu):
            k=j*(nu+1)+i
            faces.append((k,k+1,k+nu+2,k+nu+1))
    b.mesh(verts,faces,'monument_stone')


def _carve_line(b,cx,cz,points,r=.14,female=False,elder=False,material_name='monument_crease'):
    width,height=_FACE_STYLE['width'],_FACE_STYLE['height']
    path=[(cx+width*u,315-_face_depth(u,v,female,elder)-.012,cz+height*v) for u,v in points]
    b.line(path,r*.72,material_name,n=5)


def _polygon_relief(b,cx,cz,points,front=296.,back=320.,ridge=2.5,mat='monument_hair'):
    """Rounded stone lock with a buried root and several continuous bevel rings."""
    # Bevel each corner while preserving the long character-defining lock tips.
    outline=[]
    for i,p in enumerate(points):
        prev,nxt=points[i-1],points[(i+1)%len(points)]
        outline.extend([(p[0]*.93+prev[0]*.07,p[1]*.93+prev[1]*.07),
                        (p[0]*.93+nxt[0]*.07,p[1]*.93+nxt[1]*.07)])
    if sum(outline[i][0]*outline[(i+1)%len(outline)][1]-outline[(i+1)%len(outline)][0]*outline[i][1] for i in range(len(outline)))<0:
        outline.reverse()
    n=len(outline)
    center=(sum(x for x,z in outline)/n,sum(z for x,z in outline)/n)
    verts=[]
    rings=[(0.,back),(.08,front+5.0),(.24,front+.4),(.48,front-ridge*.72),(.76,front-ridge)]
    for inset,y in rings:
        for i,(x,z) in enumerate(outline):
            xx=x*(1-inset)+center[0]*inset
            zz=z*(1-inset)+center[1]*inset
            grain=.11*_noise2(xx*.6,zz*.6,17)*(inset>0)
            verts.append((cx+xx,y+grain,cz+zz))
    verts.append((cx+center[0],front-ridge*.95,cz+center[1]))
    faces=[]
    for j in range(len(rings)-1):
        for i in range(n):
            faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    for i in range(n):
        faces.append(((len(rings)-1)*n+i,(len(rings)-1)*n+(i+1)%n,len(verts)-1))
    faces.append(tuple(reversed(range(n))))
    b.mesh(verts,faces,mat)


def _headband(b,cx,cz,width=32,low=14.8,high=22.0):
    fw,fh=_FACE_STYLE['width'],_FACE_STYLE['height']
    sections,rows=32,6
    verts=[]
    for j in range(rows+1):
        z=low+(high-low)*j/rows
        edge=min(1.,j,rows-j)
        for i in range(sections+1):
            x=-width/2+width*i/sections
            y=315-_face_depth(x/fw,z/fh)-.40-.48*edge
            verts.append((cx+x,y,cz+z))
    b.mesh(verts,[(j*(sections+1)+i,j*(sections+1)+i+1,(j+1)*(sections+1)+i+1,(j+1)*(sections+1)+i)
                  for j in range(rows) for i in range(sections)],'monument_band')
    mid=(low+high)/2
    yy=315-_face_depth(0,mid/fh)-.99
    leaf_symbol(b,(cx,yy,cz+mid),5.1,'monument_crease')
    for sign in (-1,1):
        xx=sign*(width/2-2)
        for zz in (low+1.35,high-1.35):
            yy=315-_face_depth(xx/fw,zz/fh)-.92
            b.sphere((cx+xx,yy,cz+zz),(.28,.13,.28),'monument_stone',n=8,rings=4)


def _portrait(b,cx,cz,kind):
    global _FACE_STYLE
    _FACE_STYLE=_FACE_PROFILES[kind]
    female=kind=='Tsunade'
    elder=kind=='Hiruzen'
    _relief_surface(b,cx,cz,female,elder)
    # Eyelids are incised almond shapes on the concave orbital surface.
    for s in (-1,1):
        upper=[]; lower=[]
        for i in range(19):
            t=i/18
            u=s*(.16+.40*t)
            upper.append((u,_eye_level(u)+_FACE_STYLE['eye_open']*math.sin(math.pi*t)))
            lower.append((u,_eye_level(u)-_FACE_STYLE['eye_open']*.64*math.sin(math.pi*t)))
        _carve_line(b,cx,cz,upper,.20 if female else .23,female,elder)
        _carve_line(b,cx,cz,lower,.13,female,elder)
        # Small vertical cut suggests the pupil within the socket, not a protruding eye.
        _carve_line(b,cx,cz,[(s*.35,.18),(s*.35,.225)],.25,female,elder)
        _carve_line(b,cx,cz,[(s*u,.35+_FACE_STYLE['brow_slope']*(u-.35)) for u in (.15,.28,.44,.60)],.21 if female else .28,female,elder)
        _carve_line(b,cx,cz,[(s*.073,-.218),(s*.128,-.226),(s*.18,-.208)],.20,female,elder)
    _carve_line(b,cx,cz,[(-.25,-.474),(-.12,-.465),(0,-.476),(.12,-.465),(.25,-.474)],.18,female,elder)

    if kind=='Hashirama':
        # Long central-part hair frames a rectangular, solemn First Hokage face.
        for s in (-1,1):
            shapes=[[(0,33),(s*13,36),(s*22,28),(s*25,8),(s*21,1),(s*14,26)],
                    [(s*18,24),(s*27,22),(s*28,-9),(s*25,-33),(s*17,-27),(s*18,-2)],
                    [(s*25,12),(s*31,7),(s*33,-30),(s*25,-35),(s*26,-8)]]
            for shape in shapes: _polygon_relief(b,cx,cz,shape,front=299,ridge=2.5)
        _headband(b,cx,cz,31,15.8,23)
    elif kind=='Tobirama':
        # A compact, jagged crown and white-fur collar, all cut in sandstone.
        for i in range(11):
            a=math.pi*(.04+.92*i/10)
            x=23*math.cos(a); z=21+9*math.sin(a)
            tip=(x*1.26, z+8+(i%3)*2)
            _polygon_relief(b,cx,cz,[(x-5,z-8),tip,(x+5,z-7)],front=298,ridge=3)
        for s in (-1,1):
            _polygon_relief(b,cx,cz,[(s*18,24),(s*28,27),(s*24,13),(s*30,11),(s*22,-3),(s*17,7)],front=298)
            for i in range(5):
                x=s*(11+i*4)
                _polygon_relief(b,cx,cz,[(x-5,-25),(x,-19-(i%2)*2),(x+5,-28),(x+2,-37)],front=305,ridge=2)
            for u in (.47,.58):
                _carve_line(b,cx,cz,[(s*u,.055),(s*(u-.03),-.105),(s*(u+.02),-.25)],.42)
        _headband(b,cx,cz,35,16,23)
    elif kind=='Hiruzen':
        # Hiruzen's distinctive close-fitting shinobi cap and hanging temple guards.
        cap=[(-24,18),(-24,31),(-17,39),(0,42),(17,39),(24,31),(24,18)]
        _polygon_relief(b,cx,cz,cap,front=300,ridge=3.5)
        for s in (-1,1):
            _polygon_relief(b,cx,cz,[(s*17,27),(s*25,29),(s*27,-1),(s*23,-17),(s*18,-15)],front=301,ridge=2)
            _carve_line(b,cx,cz,[(s*.23,.052),(s*.46,.025),(s*.62,-.022)],.16,elder=True)
            _carve_line(b,cx,cz,[(s*.20,-.25),(s*.30,-.35),(s*.33,-.52)],.16,elder=True)
            _carve_line(b,cx,cz,[(s*.56,-.20),(s*.64,-.31),(s*.53,-.49)],.15,elder=True)
        _headband(b,cx,cz,34,15,23)
    elif kind=='Minato':
        # Long pointed locks radiate asymmetrically, with a split fringe over the band.
        spikes=[(-27,18,-38,31,-18,27),(-24,27,-29,43,-12,29),(-14,29,-17,49,-3,31),
                (-4,29,2,48,9,28),(7,30,20,44,17,24),(17,25,32,34,24,15),
                (23,16,37,21,25,4),(-24,10,-36,13,-23,-5)]
        for x1,z1,xt,zt,x2,z2 in spikes:
            _polygon_relief(b,cx,cz,[(x1,z1),(xt,zt),(x2,z2)],front=296.5,ridge=4)
        for s in (-1,1):
            _polygon_relief(b,cx,cz,[(s*17,23),(s*29,18),(s*23,-19),(s*17,-10)],front=296.5,ridge=3)
        _headband(b,cx,cz,32,14.8,22)
        for shape in [[(-15,29),(-1,29),(-7,12)],[(-2,30),(11,28),(5,16)],[(9,27),(20,24),(15,13)]]:
            _polygon_relief(b,cx,cz,shape,front=292,ridge=2)
    else:
        # Tsunade has no forehead protector: parted hair, narrow jaw, diamond seal.
        for s in (-1,1):
            _polygon_relief(b,cx,cz,[(0,32),(s*10,37),(s*23,30),(s*25,6),(s*18,9),(s*12,26)],front=298,ridge=3)
            _polygon_relief(b,cx,cz,[(s*20,21),(s*29,18),(s*31,-24),(s*24,-38),(s*17,-30),(s*19,-5)],front=299,ridge=3)
            _polygon_relief(b,cx,cz,[(s*24,-8),(s*31,-10),(s*33,-35),(s*27,-40),(s*23,-27)],front=303,ridge=2)
        vv=.62; yy=315-_face_depth(0,vv,True)-.055; zz=cz+27*vv
        b.mesh([(cx,yy,zz+1.9),(cx+1.25,yy,zz),(cx,yy,zz-1.9),(cx-1.25,yy,zz)],[(0,1,2,3)],'monument_crease')


# The geological shell remains below 150k triangles together with all portraits.
_CLIFF_NX,_CLIFF_NZ=196,62
_PEAK_NX,_PEAK_NY=72,80
_CAP_NX,_CAP_NY=112,34
_PORTRAIT_CENTRES=[(-140,100),(-70,85),(0,111),(70,90),(140,94)]


def _cliff_top(x):
    edge=max(0.,1-(abs(x)/420)**3)
    return (151+3.1*_noise2(x*.028,0,28)+2.0*_noise2(x*.086,1,6))*edge


def _cliff_front_y(x,z):
    # Water-cut vertical flutes, broad undulations and nonuniform sediment beds.
    body=3.1*_fbm(x*.021,z*.009,4)+1.1*_noise2(x*.083,z*.018,17)
    # The source cliff is dominated by irregular vertical weathering. Subdued,
    # nonperiodic bedding avoids the previous evenly spaced horizontal waves.
    bedding=.38*_noise2(x*.009,z*.12,51)
    flute=1.2*(.5+.5*math.sin(x*.34+2.3*_noise2(x*.032,z*.012,19)))**5
    fracture=0.
    for fault in (-293,-229,-178,-108,-34,38,101,174,237,316):
        path=fault+.11*z+1.1*_noise2(0,z*.049,int(fault))
        fracture+=1.15*math.exp(-((x-path)/1.8)**2)
    # The rock is cut back directly around each portrait and joins its buried rim.
    relief=max(math.exp(-((x-cx)/28)**4-((z-cz)/40)**4) for cx,cz in _PORTRAIT_CENTRES)
    geology=(body+bedding+flute+fracture)*(1-.82*relief)
    foot=-7.0*math.exp(-z/17)
    lip=3.0*max(0.,(z-132)/20)
    return 318+geology+foot+lip


def _cap_height(x,y):
    return (_cliff_top(x)+2.8*_fbm(x*.029,y*.029,24)
            -max(0.,y-438)*.115)


def _cliff(b,rng):
    nx,nz=_CLIFF_NX,_CLIFF_NZ
    verts=[]
    for j in range(nz+1):
        for i in range(nx+1):
            x=-385+770*i/nx
            z=_cliff_top(x)*j/nz
            verts.append((x,_cliff_front_y(x,z),z))
    faces=[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i)
           for j in range(nz) for i in range(nx)]
    b.mesh(verts,faces,'cliff')
    # The cap starts at the actual front rim and has a continuously rolling surface.
    nx,ny=_CAP_NX,_CAP_NY
    verts=[]
    for j in range(ny+1):
        t=j/ny
        for i in range(nx+1):
            x=-385+770*i/nx
            rim_z=_cliff_top(x); rim_y=_cliff_front_y(x,rim_z)
            y=rim_y+(590-rim_y)*t
            z=_cap_height(x,y)
            z=rim_z*(1-min(1.,t*7))+z*min(1.,t*7)
            verts.append((x,y,z))
    faces=[]
    for j in range(ny):
        for i in range(nx):
            k=j*(nx+1)+i
            faces.extend([(k,k+1,k+nx+2),(k,k+nx+2,k+nx+1)])
    b.mesh(verts,faces,'plateau')


def _peak_height(x,y,side):
    xx=x*side
    if not (185<=xx<=515 and 276<=y<=650):
        return 0.
    # Multiple eroded summits join into one continuous rock shoulder.
    peak=207*math.exp(-((xx-339)/104)**2-((y-406)/117)**2)
    ridge=169*math.exp(-((xx-265)/68)**2-((y-440)/97)**2)
    spur=121*math.exp(-((xx-406)/94)**2-((y-460)/110)**2)
    # Smooth maximum blends ridges without the previous giant planar fold.
    k=14.
    largest=max(peak,ridge,spur)
    z=largest+k*math.log(sum(math.exp((h-largest)/k) for h in (peak,ridge,spur)))
    border=min(1.,max(0.,(xx-185)/37),max(0.,(515-xx)/50),
               max(0.,(y-276)/39),max(0.,(650-y)/50))
    border=border*border*(3-2*border)
    broad=17*_fbm(xx*.018,y*.018,11+side)
    erosion=4.5*_noise2(xx*.067,y*.055,32)
    bed=1.15*math.sin(z*.34+.8*_noise2(xx*.019,y*.019,47))
    return max(0.,(z+broad+erosion+bed)*border)


def _interpolate_triangle(a,b,c,d,tx,ty):
    if ty<=tx:
        return (1-tx)*a+(tx-ty)*b+ty*c
    return (1-ty)*a+tx*c+(ty-tx)*d


def _peak_mesh_height(x,y,side):
    """Exact triangle height for vegetation roots on the exported mountain."""
    xx=x*side
    if not (185<=xx<=515 and 276<=y<=650):
        return 0.
    gx=(xx-185)/330*_PEAK_NX; gy=(y-276)/374*_PEAK_NY
    i,j=min(_PEAK_NX-1,int(gx)),min(_PEAK_NY-1,int(gy))
    tx,ty=gx-i,gy-j
    def sample(ii,jj):
        return _peak_height(side*(185+330*ii/_PEAK_NX),276+374*jj/_PEAK_NY,side)
    return _interpolate_triangle(sample(i,j),sample(i+1,j),sample(i+1,j+1),sample(i,j+1),tx,ty)


def _cap_mesh_height(x,y):
    if not (-385<=x<=385):
        return 0.
    gx=(x+385)/770*_CAP_NX
    i=min(_CAP_NX-1,int(gx)); tx=gx-i
    def rim(ii):
        xx=-385+770*ii/_CAP_NX
        zz=_cliff_top(xx)
        return xx,_cliff_front_y(xx,zz),zz
    xa,ya,za=rim(i); xb,yb,zb=rim(i+1)
    rimy=ya*(1-tx)+yb*tx
    if not rimy<=y<=590:
        return 0.
    gy=(y-rimy)/(590-rimy)*_CAP_NY
    j=min(_CAP_NY-1,int(gy)); ty=gy-j
    def sample(xx,yy,zz,jj):
        t=jj/_CAP_NY; yv=yy+(590-yy)*t
        factor=min(1.,t*7)
        return zz*(1-factor)+_cap_height(xx,yv)*factor
    # Solve the same diagonal triangles used by the exported cap, including its
    # slightly skewed front edge. This avoids a tree hovering over a bilinear guess.
    t0,t1=j/_CAP_NY,(j+1)/_CAP_NY
    ay,by=ya+(590-ya)*t0,yb+(590-yb)*t0
    dy,cy=ya+(590-ya)*t1,yb+(590-yb)*t1
    az,bz=sample(xa,ya,za,j),sample(xb,yb,zb,j)
    dz,cz=sample(xa,ya,za,j+1),sample(xb,yb,zb,j+1)
    diagonal_y=ay+(cy-ay)*tx
    if y<=diagonal_y:
        wc=(y-(1-tx)*ay-tx*by)/(cy-by)
        return (1-tx)*az+(tx-wc)*bz+wc*cz
    wd=(y-(1-tx)*ay-tx*cy)/(dy-ay)
    return (1-tx-wd)*az+tx*cz+wd*dz



def _shoulder_mountains(b,rng):
    nx,ny=_PEAK_NX,_PEAK_NY
    for side in (-1,1):
        verts=[]
        for j in range(ny+1):
            y=276+374*j/ny
            for i in range(nx+1):
                x=side*(185+330*i/nx)
                verts.append((x,y,_peak_height(x,y,side)))
        faces=[]
        for j in range(ny):
            for i in range(nx):
                k=j*(nx+1)+i
                triangles=[(k,k+1,k+nx+2),(k,k+nx+2,k+nx+1)]
                faces.extend(tuple(reversed(f)) if side<0 else f for f in triangles)
        b.mesh(verts,faces,'cliff')


def _tree_placement(rng,x,y,z=0.,scale=1.,region='forest'):
    """A real tree instance specification; scale is relative to a 15-metre tree."""
    height=rng.uniform(11.,20.)*scale
    radius=max(.17,min(.52,height*.021))
    return {'x':round(x,4),'y':round(y,4),'z':round(z,4),
            'scale':round(height/15.,5),'rotation':round(rng.uniform(0,math.tau),6),
            'height':round(height,4),'trunk_radius':round(radius,4),
            'collider_height':round(min(5.5,height*.36),4),'region':region}


def _smooth_objects(objects):
    for ob in objects:
        for polygon in ob.data.polygons:
            polygon.use_smooth=True


def build_landscape():
    rng=random.Random(12298)
    material('monument_stone',(.59,.49,.35),noise=.30)
    material('monument_hair',(.555,.455,.322),noise=.31)
    material('monument_band',(.60,.50,.36),noise=.28)
    material('monument_crease',(.36,.282,.188),noise=.19)
    material('cliff_stratum',(.47,.36,.23),noise=.34)
    material('plateau',(.24,.29,.12),noise=.43)
    rock=Builder('Hokage Rock · weathered continuous sandstone')
    _cliff(rock,rng)
    _shoulder_mountains(rock,rng)
    terrain_triangles=sum(sum(len(f)-2 for f in fs) for vs,fs in rock.data.values())
    rock_objects=rock.flush()
    _smooth_objects(rock_objects)
    sculptures=[]; portrait_triangles=0
    for i,name in enumerate(('Hashirama','Tobirama','Hiruzen','Minato','Tsunade')):
        b=Builder(f'Hokage {i+1} · {name} · carved relief')
        cx=(i-2)*70
        cz=[100,85,111,90,94][i]
        _portrait(b,cx,cz,name)
        triangles=sum(sum(len(f)-2 for f in fs) for vs,fs in b.data.values())
        obs=b.flush(); _smooth_objects(obs)
        for ob in obs:
            # Seat the carving inside the parent rock, following the reference's
            # shallow relief rather than projecting a whole head in front of it.
            for vertex in ob.data.vertices:vertex.co.y=318+(vertex.co.y-318)*.58
            ob.data.set_sharp_from_angle(angle=math.pi)
            if any(m and m.name=='monument_hair' for m in ob.data.materials):
                import bpy
                bpy.context.view_layer.objects.active=ob
                sub=ob.modifiers.new('Sculpted stone lock continuity','SUBSURF')
                sub.levels=2;sub.render_levels=2
                bpy.ops.object.modifier_apply(modifier=sub.name)
        triangles=sum(sum(len(face.vertices)-2 for face in ob.data.polygons) for ob in obs)
        portrait_triangles+=triangles
        sculptures.append({'hokage':name,'location':[cx,305.82,cz],
                           'objects':len(obs),'triangles':triangles,
                           'proportion_profile':dict(_FACE_STYLE)})
    forest=[]; occupancy={}
    # Native trees share one real source asset; only transforms are generated here.
    while len(forest)<2200:
        angle=rng.uniform(0,math.tau)
        radius=math.sqrt(rng.uniform(365**2,670**2))
        x,y=radius*math.cos(angle),radius*math.sin(angle)
        if abs(x)<24 and y<-325: continue
        if -530<x<530 and y>276: continue
        cell=(int(math.floor(x/3.2)),int(math.floor(y/3.2)))
        close=False
        for dx in (-1,0,1):
            for dy in (-1,0,1):
                if any((x-xx)**2+(y-yy)**2<3.2**2 for xx,yy in occupancy.get((cell[0]+dx,cell[1]+dy),())):
                    close=True
        if close: continue
        occupancy.setdefault(cell,[]).append((x,y))
        forest.append(_tree_placement(rng,x,y,0.,1.15,'outer_forest'))
    for i in range(110):
        x=rng.uniform(-345,345); y=rng.uniform(344,550)
        z=_cap_mesh_height(x,y)
        if abs(x)>185:
            z=max(z,_peak_mesh_height(x,y,1 if x>0 else -1))
        forest.append(_tree_placement(rng,x,y,z+.025,rng.uniform(.55,.8),'mountain_canopy'))
    return {'portraits':sculptures,'broadleaf_trees':len(forest),
            'forest_trees':forest,'outer_forest_count':2200,'mountain_canopy_count':110,
            'forest_objects':0,'cliff_objects':len(rock_objects),
            'terrain_triangles':terrain_triangles,'portrait_triangles':portrait_triangles,
            'cliff_extent_m':[-515,515,276,650,0,225],
            'tree_reference_height_m':15.,'tree_rotation_units':'radians about Blender +Z',
            'vegetation_geometry':'Native real-asset instances supplied by the scene assembler',
            'description':'Continuous weathered sandstone with five distinct Shippuden-era carved Hokage portraits.'}


# These clear parcels are shared with the districts layout. Named geometry stays clear.
_GARDEN_RECTS=[(-57,57,171,310),(16,44,-157,-128),(-128,-52,122,188)]
_GARDEN_CIRCLES=[(-225,90,48),(225,90,52)]


def _bbox_distance(x,y,building):
    dx=max(abs(x-building['x'])-building['w']/2,0.)
    dy=max(abs(y-building['y'])-building['d']/2,0.)
    return math.hypot(dx,dy)


def _garden_clear(x,y,margin=0.):
    if math.hypot(x,y)>329-margin or y>281-margin:
        return False
    if abs(x)<15+margin:
        return False
    if any(abs(y-street)<7+margin for street in (-220,-110,0,110,220)):
        return False
    if any(abs(x-street)<6+margin for street in (-200,-100,100,200)):
        return False
    for x0,x1,y0,y1 in _GARDEN_RECTS:
        if x0-margin<x<x1+margin and y0-margin<y<y1+margin:
            return False
    for cx,cy,radius in _GARDEN_CIRCLES:
        if math.hypot(x-cx,y-cy)<radius+margin:
            return False
    return True


def _garden_island(b,rng,x,y,radius):
    n=rng.randrange(12,18)
    verts=[(x,y,.17)]
    for i in range(n):
        angle=math.tau*i/n
        rr=radius*rng.uniform(.77,1.)
        verts.append((x+math.cos(angle)*rr,y+math.sin(angle)*rr,.135))
    b.mesh(verts,[(0,1+i,1+(i+1)%n) for i in range(n)],'grass')
    plants=[]
    for j in range(2):
        angle=rng.uniform(0,math.tau); rr=radius*rng.uniform(.40,.64)
        sx,sy=x+math.cos(angle)*rr,y+math.sin(angle)*rr
        size=rng.uniform(.52,.9)
        plants.append({'x':round(sx,4),'y':round(sy,4),'z':.16,'scale':round(size,4),
                       'height':round(size*1.2,4),'rotation':round(rng.uniform(0,math.tau),5),
                       'radius':round(size,4),'region':'courtyard_shrub'})
    return plants


def build_village_greenery(buildings):
    """Return native real-tree placements and lightweight irregular planting beds.

    The village GLB contains no fake sphere crowns or sphere bushes. Instancing
    uses village_trees and village_shrubs; scale is relative to a 15m source tree.
    """
    if isinstance(buildings,dict): buildings=buildings['buildings']
    rng=random.Random(70403)
    b=Builder('Village gardens · irregular planting beds')
    placed=[]; trees=[]; shrubs=[]; garden_count=0; avenue_count=0
    minimum_clearance=float('inf')
    candidates=[]
    for building in buildings:
        for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
            candidates.append((building['x']+sx*(building['w']/2+rng.uniform(2.7,5.5)),
                               building['y']+sy*(building['d']/2+rng.uniform(2.7,5.5))))
    rng.shuffle(candidates)
    candidates.extend((rng.uniform(-328,328),rng.uniform(-320,279)) for i in range(16000))
    candidates.sort(key=lambda point:0 if 20<abs(point[0])<55 else 1)
    for x,y in candidates:
        if len(placed)>=250: break
        if not _garden_clear(x,y,1.2): continue
        if any((x-xx)**2+(y-yy)**2<8.2**2 for xx,yy in placed): continue
        clearance=min((_bbox_distance(x,y,house) for house in buildings),default=999.)
        if clearance<2.65: continue
        avenue=abs(x)<55
        if avenue and avenue_count>=60: continue
        scale=rng.uniform(.68,.94) if avenue else rng.uniform(.72,1.10)
        tree=_tree_placement(rng,x,y,.17,scale,'avenue' if avenue else 'courtyard')
        if clearance-tree['trunk_radius']<2.0: continue
        trees.append(tree); placed.append((x,y)); avenue_count+=int(avenue)
        minimum_clearance=min(minimum_clearance,clearance)
        if rng.random()<.62:
            radius=min(rng.uniform(2.0,3.6),clearance-.2)
            while radius>1.3 and not _garden_clear(x,y,radius): radius-=.35
            if radius>1.3:
                shrubs.extend(_garden_island(b,rng,x,y,radius)); garden_count+=1
    face_count=sum(len(faces) for verts,faces in b.data.values())
    objects=b.flush()
    return {'trees':len(trees),'village_trees':trees,'village_shrubs':shrubs,
            'detailed_trees':sum(t['region']=='avenue' for t in trees),
            'garden_islands':garden_count,'shrubs':len(shrubs),
            'faces':face_count,'objects':len(objects),
            'minimum_trunk_to_building_bbox_m':round(minimum_clearance,3),
            'street_and_landmark_keepouts_checked':True,
            'tree_reference_height_m':15.,'tree_rotation_units':'radians about Blender +Z',
            'vegetation_geometry':'Native real-asset instances supplied by the scene assembler'}
