"""Build original village assets: blender --background --python tools/model/build_villages.py -- --village sand [--slice]."""
import argparse
import json
from pathlib import Path
import sys
import bpy

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import common


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--village',choices=['sand'],required=True)
    parser.add_argument('--slice',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    common.MATS.clear();common.setup_materials()
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1.
    import suna
    meta=suna.build(args.slice)
    output=HERE.parents[1]/'assets'/'villages';output.mkdir(parents=True,exist_ok=True)
    # Runtime supplies scanned material detail. Export stable named material IDs.
    for material in bpy.data.materials:
        material.use_nodes=True
        nodes=material.node_tree.nodes
        for node in list(nodes):
            if node.type not in ('BSDF_PRINCIPLED','OUTPUT_MATERIAL'):nodes.remove(node)
        nodes.get('Principled BSDF').inputs['Base Color'].default_value=material.diffuse_color
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(output/(args.village+'.glb')),export_format='GLB',
        use_selection=True,export_materials='EXPORT',export_yup=True,export_cameras=False,export_lights=False,export_apply=True,export_normals=True,export_tangents=True)
    meta['vertices']=sum(len(ob.data.vertices) for ob in bpy.context.scene.objects if ob.type=='MESH')
    meta['faces']=sum(len(ob.data.polygons) for ob in bpy.context.scene.objects if ob.type=='MESH')
    (output/(args.village+'.json')).write_text(json.dumps(meta,indent=2)+'\n')
    common.OUT.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(common.OUT/(args.village+'.blend')),compress=True)
    print('VILLAGE_BUILT',json.dumps({'id':args.village,'faces':meta['faces'],'vertices':meta['vertices'],'slice_buildings':meta['slice_buildings']}),flush=True)


if __name__=='__main__':main()
