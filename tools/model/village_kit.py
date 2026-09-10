"""Metric curved masonry helpers shared by original village generators."""
import math
import bpy
from common import Builder
from mathutils import Vector


def godot(p):
    return [p[0], p[2], -p[1]]


def radius_at(profile, z):
    for (za, ra), (zb, rb) in zip(profile, profile[1:]):
        if z <= zb:
            return ra + (rb-ra)*max(0., min(1., (z-za)/(zb-za)))
    return profile[-1][1]


def smooth_profile(profile, subdivisions=4):
    """Cubic Hermite radius transitions retain authored silhouette control points."""
    slopes=[]
    for i,(z,r) in enumerate(profile):
        a=profile[max(0,i-1)];b=profile[min(len(profile)-1,i+1)]
        slopes.append((b[1]-a[1])/(b[0]-a[0]))
    result=[]
    for i,((za,ra),(zb,rb)) in enumerate(zip(profile,profile[1:])):
        for j in range(subdivisions):
            t=j/subdivisions;d=zb-za
            r=(2*t**3-3*t*t+1)*ra+(t**3-2*t*t+t)*d*slopes[i]+(-2*t**3+3*t*t)*rb+(t**3-t*t)*d*slopes[i+1]
            result.append((za+t*d,r))
    return result+[profile[-1]]


def curved_patch(f, profile, a0, a1, z0, z1, mat, inset=0.):
    """Closed thick shell patch with radial facade normals and flat reveals."""
    if z1-z0<1e-7 or a1-a0<1e-7:return
    cuts = [z0] + [z for z, _ in profile if z0 < z < z1] + [z1]
    normals=getattr(f.b,'surface_normals',None)
    if normals is None:f.b.surface_normals={};normals=f.b.surface_normals
    if not hasattr(f.b,'surface_uvs'):f.b.surface_uvs={}
    uv_radius=radius_at(profile,(profile[0][0]+profile[-1][0])*.5)
    for low, high in zip(cuts, cuts[1:]):
        verts=[]
        for depth in (inset, inset+.34):
            for z in (low, high):
                r=radius_at(profile,z)-depth
                verts.extend([(r*math.sin(a),-r*math.cos(a),z) for a in (a0,a1)])
        face_start=len(f.b.data[mat][1])
        f.mesh(verts,[(0,1,3,2),(5,4,6,7),(4,0,2,6),(1,5,7,3),(2,3,7,6),(4,5,1,0)],mat)
        def normal(angle,z,sign=1):
            za=max(profile[0][0],z-.025);zb=min(profile[-1][0],z+.025)
            slope=(radius_at(profile,zb)-radius_at(profile,za))/max(.0001,zb-za)
            return tuple(Vector((math.sin(angle+f.rot),-math.cos(angle+f.rot),-slope)).normalized()*sign)
        normals[(mat,face_start)]=[normal(a0,low),normal(a1,low),normal(a1,high),normal(a0,high)]
        normals[(mat,face_start+1)]=[normal(a1,low,-1),normal(a0,low,-1),normal(a0,high,-1),normal(a1,high,-1)]
        f.b.surface_uvs[(mat,face_start)]=[(a0*uv_radius,low+f.z),(a1*uv_radius,low+f.z),(a1*uv_radius,high+f.z),(a0*uv_radius,high+f.z)]
        f.b.surface_uvs[(mat,face_start+1)]=[(-a1*uv_radius,low+f.z),(-a0*uv_radius,low+f.z),(-a0*uv_radius,high+f.z),(-a1*uv_radius,high+f.z)]


def profiled_shell(f, profile, floors, mat, bays=40, doorway=True, detailed=True,
                   shadow_material=None, trim_material=None,
                   door_material=None, window_filter=None, door_width=1.30, window_bands=None):
    """Pierce independent wall bays, including a full-width multi-bay door.

    window_filter(angle_radians, bottom_m) can reserve solid facade for signs.
    Recessed closures are real surfaces 32cm behind the masonry face.
    """
    top=profile[-1][0]
    shadow_material=shadow_material or mat
    trim_material=trim_material or mat
    door_half=math.asin(min(.95,door_width/(2*radius_at(profile,1.))))
    for i in range(bays):
        angle=(i*math.tau/bays+math.pi)%math.tau-math.pi
        half=math.pi/bays
        left,right=angle-half,angle+half
        holes=[]
        if detailed:
            has_door=doorway and right>-door_half and left<door_half
            if has_door:holes.append((.10,2.35,max(left,-door_half),min(right,door_half),True))
            bands=window_bands if window_bands is not None else [(1.35+floor*3.15,1.13,.52) for floor in range(floors)]
            for z,opening_height,opening_width in bands:
                if i%2 or (has_door and z<2.35):continue
                if window_filter is not None and not window_filter(angle,z):continue
                opening=min(half*.72,opening_width/(2*radius_at(profile,z)))
                holes.append((z,z+opening_height,angle-opening,angle+opening,False))
        holes.sort(key=lambda hole:hole[0])
        low=profile[0][0]
        for bottom,upper,hole_left,hole_right,is_door in holes:
            curved_patch(f,profile,left,right,low,bottom,mat)
            if hole_left>left+1e-6:
                curved_patch(f,profile,left,hole_left,bottom,upper,mat)
            if hole_right<right-1e-6:
                curved_patch(f,profile,hole_right,right,bottom,upper,mat)
            closure=door_material if is_door and door_material else shadow_material
            curved_patch(f,profile,hole_left,hole_right,bottom,upper,closure,.32)
            if not is_door:
                curved_patch(f,profile,hole_left-.015,hole_right+.015,bottom-.055,bottom+.02,trim_material,-.06)
            low=upper
        curved_patch(f,profile,left,right,low,top,mat)


def ring(f, radius, z, height, mat, thickness=.22, n=56):
    profile=[(z,radius),(z+height,radius)]
    # Thin cornices still use the shell helper's sturdy construction thickness.
    for i in range(n):
        curved_patch(f,profile,i*math.tau/n,(i+1)*math.tau/n,z,z+height,mat)


def assign_metric_uvs(ob, face_uvs=None):
    """UV units are metres. Planar bases satisfy cross(U,V)=outward normal.

    Blender's glTF exporter performs the UV vertical convention conversion and
    derives tangent handedness. Face overrides are cylindrical shell UVs.
    """
    mesh=ob.data
    uv=mesh.uv_layers[0] if mesh.uv_layers else mesh.uv_layers.new(name='MetricUV')
    uv.name='MetricUV'
    mesh.uv_layers.active=uv
    uv.active_render=True
    matrix=ob.matrix_world
    normal_matrix=matrix.to_3x3().inverted().transposed()
    points=[matrix@v.co for v in mesh.vertices]
    for polygon in mesh.polygons:
        specified=(face_uvs or {}).get(polygon.index)
        n=(normal_matrix@polygon.normal).normalized()
        axis=max(range(3),key=lambda i:abs(n[i]));sign=1 if n[axis]>=0 else -1
        for j,loop in enumerate(polygon.loop_indices):
            if specified:coords=specified[j]
            else:
                p=points[mesh.loops[loop].vertex_index]
                if axis==2:coords=(p.x,sign*p.y)
                elif axis==1:coords=(p.x,-sign*p.z)
                else:coords=(p.y,sign*p.z)
            uv.data[loop].uv=coords
    return uv


def finish(builder, roles, collision=True, distance=650.):
    """Center each material chunk's origin on its bounds for distance culling."""
    normals=getattr(builder,'surface_normals',{})
    uvs=getattr(builder,'surface_uvs',{})
    if normals:
        # Join coincident shell patch vertices and remove paired internal faces.
        # Normal records follow surviving faces; aperture reveals remain flat.
        compact_normals={}
        compact_uvs={}
        for mat,(vertices,faces) in builder.data.items():
            unique=[];lookup={};remap=[]
            for vertex in vertices:
                key=tuple(round(v,6) for v in vertex)
                if key not in lookup:lookup[key]=len(unique);unique.append(vertex)
                remap.append(lookup[key])
            mapped=[tuple(remap[i] for i in face) for face in faces]
            counts={}
            for face in mapped:
                key=tuple(sorted(face));counts[key]=counts.get(key,0)+1
            survivors=[]
            for old,face in enumerate(mapped):
                if counts[tuple(sorted(face))]>1:continue
                record=normals.get((mat,old))
                if record:compact_normals[(mat,len(survivors))]=record
                if (mat,old) in uvs:compact_uvs[(mat,len(survivors))]=uvs[(mat,old)]
                survivors.append(face)
            builder.data[mat]=[unique,survivors]
        normals=compact_normals
        uvs=compact_uvs
    objects=builder.flush()
    for ob in objects:
        if not ob.data.vertices: continue
        if normals:
            mat=ob.data.materials[0].name
            loop_normals=[(0.,0.,0.)]*len(ob.data.loops)
            for polygon in ob.data.polygons:
                specified=normals.get((mat,polygon.index))
                for j,loop in enumerate(polygon.loop_indices):
                    loop_normals[loop]=specified[j] if specified else tuple(polygon.normal)
            ob.data.normals_split_custom_set(loop_normals)
        material_name=ob.data.materials[0].name
        assign_metric_uvs(ob,{index:value for (mat,index),value in uvs.items() if mat==material_name})
        lo=[min(v.co[i] for v in ob.data.vertices) for i in range(3)]
        hi=[max(v.co[i] for v in ob.data.vertices) for i in range(3)]
        center=[(a+b)/2 for a,b in zip(lo,hi)]
        for vertex in ob.data.vertices:
            for i in range(3): vertex.co[i]-=center[i]
        ob.location=center
        # glTF tangent generation requires triangles/quads; cylinder caps are n-gons.
        if any(len(poly.vertices)>4 for poly in ob.data.polygons):
            modifier=ob.modifiers.new('Triangulate caps for tangent export','TRIANGULATE')
            modifier.min_vertices=5
            if hasattr(modifier,'keep_custom_normals'):modifier.keep_custom_normals=True
        roles[ob.name]={'collision':collision,'shadow':True,'range_m':distance}
    return objects
