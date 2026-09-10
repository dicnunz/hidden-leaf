"""Add metric planar UVs to a derived Leaf asset without editing its source.

blender --background --python tools/model/prepare_leaf.py
Only the UV layer is edited. Blender exports UV-aware tangents and their glTF
handedness; no mesh transforms, vertices, normals, materials or names are edited.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import bpy

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from village_kit import assign_metric_uvs
ROOT=HERE.parents[1]


def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def geometry_digest(objects):
    result={}
    for ob in objects:
        mesh=ob.data
        digest=hashlib.sha256()
        for vertex in mesh.vertices:digest.update(struct.pack('<3f',*vertex.co))
        for polygon in mesh.polygons:
            digest.update(struct.pack('<I',len(polygon.vertices)))
            for index in polygon.vertices:digest.update(struct.pack('<I',index))
        result[ob.name]={'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),
            'geometry_sha256':digest.hexdigest(),'matrix_world':[list(row) for row in ob.matrix_world],
            'materials':[mat.name if mat else None for mat in mesh.materials]}
    return result


def export_audit(path, repair=False):
    """Read actual exported attributes and tangent signs, including UV seam splits."""
    data=bytearray(path.read_bytes());json_bytes=struct.unpack_from('<I',data,12)[0]
    document=json.loads(data[20:20+json_bytes]);binary_offset=20+json_bytes+8
    counts={'primitives':0,'with_uv':0,'with_normals':0,'with_tangents':0,'tangent_signs':{},'invalid_tangents':0,'repaired_tangents':0}
    for mesh in document.get('meshes',[]):
        for primitive in mesh['primitives']:
            counts['primitives']+=1;attributes=primitive['attributes']
            for attribute,key in [('TEXCOORD_0','with_uv'),('NORMAL','with_normals'),('TANGENT','with_tangents')]:
                if attribute in attributes:counts[key]+=1
            if 'TANGENT' not in attributes:continue
            accessor=document['accessors'][attributes['TANGENT']]
            view=document['bufferViews'][accessor['bufferView']]
            start=binary_offset+view.get('byteOffset',0)+accessor.get('byteOffset',0)
            stride=view.get('byteStride',16)
            for i in range(accessor['count']):
                tangent=struct.unpack_from('<4f',data,start+i*stride)
                sign=str(round(tangent[3],4));counts['tangent_signs'][sign]=counts['tangent_signs'].get(sign,0)+1
                length=sum(value*value for value in tangent[:3])
                if not .98<length<1.02 or abs(abs(tangent[3])-1)>.0001:
                    counts['invalid_tangents']+=1
                    if repair:
                        normal_accessor=document['accessors'][attributes['NORMAL']]
                        normal_view=document['bufferViews'][normal_accessor['bufferView']]
                        normal_start=binary_offset+normal_view.get('byteOffset',0)+normal_accessor.get('byteOffset',0)
                        n=struct.unpack_from('<3f',data,normal_start+i*normal_view.get('byteStride',12))
                        axis=min(range(3),key=lambda j:abs(n[j]))
                        helper=[0.,0.,0.];helper[axis]=1.
                        t=[helper[1]*n[2]-helper[2]*n[1],helper[2]*n[0]-helper[0]*n[2],helper[0]*n[1]-helper[1]*n[0]]
                        size=math.sqrt(sum(v*v for v in t))
                        if size<1e-9:raise ValueError('Cannot repair tangent for zero normal')
                        struct.pack_into('<4f',data,start+i*stride,*(v/size for v in t),-1. if tangent[3]<0 else 1.)
                        counts['repaired_tangents']+=1
    if repair and counts['repaired_tangents']:path.write_bytes(data)
    return counts


def main():
    source=ROOT/'assets'/'village_v3.glb';output=ROOT/'assets'/'villages'/'leaf.glb'
    before=sha(source)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source),import_pack_images=False)
    objects=[ob for ob in bpy.context.scene.objects if ob.type=='MESH']
    original=geometry_digest(objects)
    for ob in objects:assign_metric_uvs(ob)
    assert original==geometry_digest(objects),'UV authoring changed source geometry, names, transforms or materials'
    output.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,
        export_materials='EXPORT',export_yup=True,export_cameras=False,export_lights=False,
        export_apply=False,export_normals=True,export_tangents=True)
    assert before==sha(source),'Original source asset changed'
    repair=export_audit(output,repair=True)
    audit=export_audit(output)
    assert audit['primitives']==audit['with_uv']==audit['with_normals']==audit['with_tangents'],audit
    assert audit['invalid_tangents']==0,audit
    report={'source':str(source.relative_to(ROOT)),'source_sha256':before,
        'output':str(output.relative_to(ROOT)),'output_sha256':sha(output),'uv_units':'metres',
        'method':'dominant world face axis; stable axes; cross(U,V) aligned with face normal',
        'geometry_unchanged_before_export':True,'source_unchanged':True,
        'objects':original,'export_attributes':audit,
        'degenerate_tangent_repairs':repair['repaired_tangents'],
        'tangent_repair_method':'Only invalid tangent vectors receive a unit basis perpendicular to unchanged normal; exporter handedness retained',
        'limitations':'Planar seams at dominant-axis changes. Appearance and runtime import still require inspection.'}
    report_path=ROOT/'.build'/'model'/'leaf-uv-report.json';report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    print('LEAF_UV_PREPARED',json.dumps({'objects':len(objects),'bytes':output.stat().st_size,'attributes':audit}),flush=True)


if __name__=='__main__':main()
