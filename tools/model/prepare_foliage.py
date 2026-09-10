"""Recover CC0 twig instances and build compact full-coverage foliage cards.
Run with Blender --background --python tools/model/prepare_foliage.py -- --source PATH.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from collections import defaultdict
import bpy
import numpy as np
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[2]

def arrays(mesh):
    coords=np.array([v.co[:] for v in mesh.vertices])
    uv=np.array([v.uv[:] for v in mesh.uv_layers.active.data])
    return coords,uv

def signature(poly,uv):
    return tuple(sorted(tuple(np.round(uv[i],5)) for i in poly.loop_indices))

def inspect(source):
    tree=bpy.data.objects['tree_small_02_LOD1']
    xyz,uv=arrays(tree.data)
    signatures=defaultdict(list)
    leaf_index=next(i for i,m in enumerate(tree.data.materials) if 'leaves' in m.name)
    for p in tree.data.polygons:
        if p.material_index==leaf_index:signatures[signature(p,uv)].append(p.index)
    report=[]
    for letter in 'abcd':
        ob=bpy.data.objects[f'tree_small_02_leaves_{letter}_LOD1']
        c,t=arrays(ob.data)
        loops=list(ob.data.loops)
        x=np.array([c[l.vertex_index] for l in loops])
        a=np.column_stack((t,np.ones(len(t))))
        coeff=np.linalg.lstsq(a,x,rcond=None)[0]
        error=np.linalg.norm(a@coeff-x,axis=1)
        matches=[(p.index,len(signatures[signature(p,t)])) for p in ob.data.polygons]
        report.append({'template':letter,'vertices':len(c),'affine_error_percentiles':np.percentile(error,[50,95,100]).tolist(),'dimensions':list(ob.dimensions),'matches':matches[:5],'matched_polygons':sum(n>0 for _,n in matches),'polygons':len(matches),'uv_bounds':[t.min(axis=0).tolist(),t.max(axis=0).tolist()]})
    print('TEMPLATE_INSPECTION',json.dumps(report),flush=True)
    return tree,signatures

def recover(tree, signatures):
    xyz,uv=arrays(tree.data)
    kd=KDTree(len(xyz))
    for i,co in enumerate(xyz):kd.insert(co,i)
    kd.balance()
    result={};recovery_report={}
    for letter in 'abcd':
        ob=bpy.data.objects[f'tree_small_02_leaves_{letter}_LOD1']
        c,t=arrays(ob.data)
        candidates=[p for p in ob.data.polygons if len(p.vertices)==3]
        anchor=min(candidates,key=lambda p:(len(signatures[signature(p,t)]),-p.area))
        ordered=sorted(anchor.loop_indices,key=lambda i:tuple(t[i]))
        local=np.array([c[ob.data.loops[i].vertex_index] for i in ordered])
        def basis(points):
            u,v=points[1]-points[0],points[2]-points[0]
            n=np.cross(u,v);n=n/np.linalg.norm(n)*np.sqrt(np.linalg.norm(u)*np.linalg.norm(v))
            return np.column_stack((u,v,n))
        inv=np.linalg.inv(basis(local))
        instances=[];errors=[]
        for index in signatures[signature(anchor,t)]:
            poly=tree.data.polygons[index]
            order=sorted(poly.loop_indices,key=lambda i:tuple(uv[i]))
            world=np.array([xyz[tree.data.loops[i].vertex_index] for i in order])
            matrix=basis(world)@inv
            offset=world[0]-matrix@local[0]
            transformed=c@matrix.T+offset
            error=max(kd.find(co)[2] for co in transformed)
            errors.append(error)
            instances.append((matrix,offset))
        assert max(errors)<1e-4, 'Twig recovery exceeded 0.1mm'
        recovery_report[letter]={'instances':len(instances),'maximum_vertex_error_m':max(errors),'p95_instance_error_m':float(np.percentile(errors,95))}
        result[letter]=(ob,instances)
        print('RECOVERY',letter,len(instances),'max_error',max(errors),'p95',float(np.percentile(errors,95)),flush=True)
    return result,recovery_report

def pixels(path):
    im=bpy.data.images.load(str(path),check_existing=True)
    return np.array(im.pixels[:],dtype=np.float32).reshape(im.size[1],im.size[0],4)

def save_image(path,data):
    im=bpy.data.images.new(path.stem,width=data.shape[1],height=data.shape[0],alpha=True)
    im.pixels.foreach_set(data.ravel())
    im.filepath_raw=str(path);im.file_format='PNG';im.save()

def bake(recovered,source):
    tile=512;pad=8
    color=np.zeros((tile*3,tile*4,4),dtype=np.float32)
    normals=np.zeros_like(color);normals[:]=(.5,.5,1.,1.)
    texture=pixels(source.parent/'textures/tree_small_02_leaves_diff_1k.png')
    alpha=pixels(source.parent/'textures/tree_small_02_leaves_alpha_1k.png')
    cards={};coverage={}
    for column,(letter,(ob,instances)) in enumerate(recovered.items()):
        c,uv=arrays(ob.data);ob.data.calc_loop_triangles()
        low,high=c.min(axis=0),c.max(axis=0)
        cards[letter]=[];coverage[letter]=[]
        for row,(u,v,w) in enumerate([(0,1,2),(1,2,0),(2,0,1)]):
            depth=np.full((tile,tile),-np.inf)
            projected=(c[:,[u,v]]-low[[u,v]])/(high-low)[[u,v]]*(tile-2*pad)+pad
            for tri in ob.data.loop_triangles:
                ids=list(tri.vertices);p=projected[ids]
                lo=np.maximum(np.floor(p.min(axis=0)).astype(int),0)
                hi=np.minimum(np.ceil(p.max(axis=0)).astype(int),tile-1)
                if np.any(hi<lo):continue
                xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5)
                den=(p[1,1]-p[2,1])*(p[0,0]-p[2,0])+(p[2,0]-p[1,0])*(p[0,1]-p[2,1])
                if abs(den)<1e-10:continue
                a=((p[1,1]-p[2,1])*(xx-p[2,0])+(p[2,0]-p[1,0])*(yy-p[2,1]))/den
                b=((p[2,1]-p[0,1])*(xx-p[2,0])+(p[0,0]-p[2,0])*(yy-p[2,1]))/den
                bary=np.stack((a,b,1-a-b),axis=-1)
                tex=bary@uv[list(tri.loops)]
                tx=np.clip((tex[...,0]*(texture.shape[1]-1)).astype(int),0,texture.shape[1]-1)
                ty=np.clip((tex[...,1]*(texture.shape[0]-1)).astype(int),0,texture.shape[0]-1)
                z=bary@c[ids,w]
                sl=np.s_[lo[1]:hi[1]+1,lo[0]:hi[0]+1]
                mask=(bary.min(axis=-1)>=-1e-7)&(alpha[ty,tx,0]>.34)&(z>depth[sl])
                rgba=texture[ty,tx].copy();rgba[...,3]=alpha[ty,tx,0]
                tile_color=color[row*tile:(row+1)*tile,column*tile:(column+1)*tile]
                tile_color[sl][mask]=rgba[mask];depth[sl][mask]=z[mask]
                n=np.array(tri.normal)[[u,v,w]]
                if n[2]<0:n=-n
                tile_normal=normals[row*tile:(row+1)*tile,column*tile:(column+1)*tile]
                tile_normal[sl][mask,:3]=n*.5+.5
            corners=[]
            for x,y in [(0,0),(1,0),(1,1),(0,1)]:
                point=(low+high)*.5;point[u]=low[u]+x*(high[u]-low[u]);point[v]=low[v]+y*(high[v]-low[v]);corners.append(point)
            atlas_uv=[((column*tile+pad+x*(tile-2*pad))/(tile*4),(row*tile+pad+y*(tile-2*pad))/(tile*3)) for x,y in [(0,0),(1,0),(1,1),(0,1)]]
            cards[letter].append((np.array(corners),atlas_uv))
            coverage[letter].append(int(np.isfinite(depth).sum()))
    output=ROOT/'assets/vegetation'
    # Blender exposes source color pixels in linear light; generated PNG pixels
    # are stored directly, so encode color while keeping alpha and normals linear.
    rgb=color[...,:3]
    color[...,:3]=np.where(rgb<=.0031308,rgb*12.92,1.055*np.power(np.maximum(rgb,0),1/2.4)-.055)
    save_image(output/'optimized_leaves_color.png',color)
    save_image(output/'optimized_leaves_normal.png',normals)
    return cards,coverage

def export(recovered,cards,tree):
    output=ROOT/'assets/vegetation';verts=[];faces=[];uvs=[]
    matrix=np.array(tree.matrix_world)
    for letter,(_,instances) in recovered.items():
        for rotation,translation in instances:
            for corners,atlas_uv in cards[letter]:
                points=corners@rotation.T+translation
                points=points@matrix[:3,:3].T+matrix[:3,3]
                start=len(verts);verts.extend(points.tolist());faces.append(tuple(range(start,start+4)));uvs.extend(atlas_uv)
    mesh=bpy.data.meshes.new('CC0 reconstructed twig cards');mesh.from_pydata(verts,[],faces);mesh.update()
    layer=mesh.uv_layers.new(name='UVMap')
    for loop in mesh.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
    leaves=bpy.data.objects.new('Optimized leaves cards',mesh);bpy.context.collection.objects.link(leaves)
    material=bpy.data.materials.new('tree_small_02_leaves_cards');material.use_nodes=True
    node=material.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(output/'optimized_leaves_color.png'))
    bsdf=material.node_tree.nodes.get('Principled BSDF');material.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color']);material.node_tree.links.new(node.outputs['Alpha'],bsdf.inputs['Alpha'])
    mesh.materials.append(material)
    report=[]
    for lod in ['near','mid','far','distant','horizon']:
        before=set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(output/f'tree_v3_{lod}.glb'))
        imported=set(bpy.data.objects)-before
        wood=[o for o in imported if o.type=='MESH' and 'leaves' not in o.name.lower()]
        bpy.ops.object.select_all(action='DESELECT')
        leaves.select_set(True)
        for ob in wood:ob.select_set(True)
        path=output/f'optimized_{lod}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='EXPORT',export_yup=True,export_cameras=False,export_lights=False,export_normals=True,export_tangents=True)
        triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in wood)+len(faces)*2
        report.append({'lod':lod,'triangles':triangles,'leaf_triangles':len(faces)*2,'file':str(path.relative_to(ROOT)),'bytes':path.stat().st_size})
        for ob in imported:bpy.data.objects.remove(ob,do_unlink=True)
    coords=np.array(verts)
    return {'lods':report,'card_bounds_blender':[coords.min(axis=0).tolist(),coords.max(axis=0).tolist()]}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.source))
    tree,signatures=inspect(args.source)
    recovered,recovery_report=recover(tree,signatures)
    cards,coverage=bake(recovered,args.source)
    recovered_triangles=sum(len(instances)*sum(len(p.vertices)-2 for p in ob.data.polygons) for ob,instances in recovered.values())
    source_leaf_index=next(i for i,m in enumerate(tree.data.materials) if 'leaves' in m.name)
    source_triangles=sum(len(p.vertices)-2 for p in tree.data.polygons if p.material_index==source_leaf_index)
    assert recovered_triangles==source_triangles, 'Recovered twig population differs from original'
    report=export(recovered,cards,tree)
    report['source_leaf_triangles_accounted_for']=source_triangles
    report.update({'source':str(args.source),'source_sha256':hashlib.file_digest(args.source.open('rb'),'sha256').hexdigest(),'reconstruction':recovery_report,'license':'CC0','source_url':'https://polyhaven.com/a/tree_small_02','method':'Recover exact twig transforms from matching original UV triangles; CPU orthographic albedo/alpha and geometric normal projection into three fixed intersecting planes per twig. Original per-tier wood retained.','instances':{letter:len(instances) for letter,(_,instances) in recovered.items()},'opaque_pixels_per_template_axis':coverage,'limitations':'Card parallax and overdraw require multi-angle runtime review. Distant tiers retain all twigs and cost more triangles than prior thinned meshes.'})
    path=ROOT/'.build/model/foliage-report.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,indent=2)+'\n')
    print('FOLIAGE_PREPARED',json.dumps(report),flush=True)

if __name__=='__main__':main()
