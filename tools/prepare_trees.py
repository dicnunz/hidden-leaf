"""Prepare geometry-preserving tree LODs from the original CC0 tree."""
import argparse
import bpy
import sys
import json
import math
import hashlib
import struct
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=ROOT / '.build/sources/tree_small_02/tree_small_02.blend')
parser.add_argument('--output', type=Path, default=ROOT / 'assets/vegetation')
parser.add_argument('--qa-output', type=Path, default=ROOT / '.build/qa/trees')
args, _ = parser.parse_known_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
SOURCE, OUTPUT, QA_OUTPUT = args.source.resolve(), args.output.resolve(), args.qa_output.resolve()


def inspect_source(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    rows = []
    for material_index, mat in enumerate(mesh.materials):
        polys = [p for p in mesh.polygons if p.material_index == material_index]
        parent = {}
        def find(v):
            parent.setdefault(v, v)
            while parent[v] != v:
                parent[v] = parent[parent[v]]
                v = parent[v]
            return v
        def union(a, b):
            a, b = find(a), find(b)
            parent[b] = a
        for p in polys:
            vertices = list(p.vertices)
            for v in vertices[1:]:
                union(vertices[0], v)
        components = Counter(find(v) for v in parent)
        polygon_components = Counter(find(p.vertices[0]) for p in polys)
        nodes = []
        if mat.use_nodes:
            nodes = [{'name': n.name, 'image': n.image.filepath if n.image else None}
                     for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE']
        rows.append({'material': mat.name, 'polygons': len(polys),
                     'triangles': sum(len(p.vertices)-2 for p in polys),
                     'polygon_sizes': dict(Counter(len(p.vertices) for p in polys)),
                     'connected_components': len(components),
                     'component_vertex_hist': dict(Counter(components.values())),
                     'component_polygon_hist': dict(Counter(polygon_components.values())),
                     'images': nodes})
    print('TREE_V3_SOURCE', json.dumps({'object': obj.name,
        'height': obj.dimensions.z, 'dimensions': list(obj.dimensions),
        'vertices': len(mesh.vertices), 'polygons': len(mesh.polygons),
        'triangles': len(mesh.loop_triangles), 'materials': rows}), flush=True)


def components_for_material(mesh, material_index):
    """Connected source pieces stay indivisible; no foliage edge collapse occurs."""
    polygons = [p for p in mesh.polygons if p.material_index == material_index]
    parent = {}
    def find(vertex):
        parent.setdefault(vertex, vertex)
        while parent[vertex] != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex
    for poly in polygons:
        a = find(poly.vertices[0])
        for vertex in poly.vertices[1:]:
            parent[find(vertex)] = a
    groups = defaultdict(list)
    for poly in polygons:
        groups[find(poly.vertices[0])].append(poly.index)
    rows = []
    for identifier, indices in groups.items():
        vertex_ids = {v for i in indices for v in mesh.polygons[i].vertices}
        coords = np.array([mesh.vertices[v].co[:] for v in vertex_ids])
        rows.append({'id': identifier, 'faces': indices, 'vertices': vertex_ids,
                     'center': coords.mean(axis=0), 'low': coords.min(axis=0),
                     'high': coords.max(axis=0),
                     'triangles': sum(len(mesh.polygons[i].vertices)-2 for i in indices),
                     'area': sum(mesh.polygons[i].area for i in indices)})
    return rows


def stable_hash(value):
    value = (int(value) ^ 0x9E3779B9) & 0xffffffff
    value = ((value ^ (value >> 16)) * 0x85EBCA6B) & 0xffffffff
    value = ((value ^ (value >> 13)) * 0xC2B2AE35) & 0xffffffff
    return ((value ^ (value >> 16)) & 0xffffffff) / 4294967296.0


def choose_foliage(components, triangle_budget, cell_size):
    """Stratified whole-piece thinning, with coverage and silhouette anchors.

    Preserve one complete source piece in every occupied canopy cell plus the
    extremal pieces. Fill each cell with the largest original surface per
    triangle first. Every chosen piece retains all its original coordinates,
    polygons, UVs and bends.
    """
    cells = defaultdict(list)
    for component in components:
        key = tuple(np.floor(component['center'] / cell_size).astype(int))
        cells[key].append(component)
    chosen = {}
    # All axis and diagonal extrema anchor the original canopy envelope.
    for x in (-1, 0, 1):
        for y in (-1, 0, 1):
            for z in (-1, 0, 1):
                if x == y == z == 0:
                    continue
                axis = np.array([x, y, z])
                component = max(components, key=lambda c: float(np.where(axis >= 0, c['high'], c['low']) @ axis))
                chosen[component['id']] = component
    for cell in cells.values():
        # Broad intact leaves are better coverage anchors than thin stem strips.
        component = max(cell, key=lambda c: c['area'] / math.sqrt(c['triangles']))
        chosen[component['id']] = component
    used = sum(c['triangles'] for c in chosen.values())
    if used > triangle_budget:
        raise RuntimeError(f'Coverage anchors cost {used}, above budget {triangle_budget}; enlarge cells.')
    ranked = []
    for cell in cells.values():
        cell.sort(key=lambda c: (-c['area']/c['triangles'], stable_hash(c['id'])))
        total = sum(c['triangles'] for c in cell)
        cumulative = 0
        for component in cell:
            fraction = (cumulative + component['triangles'] * .5) / total
            ranked.append((fraction, stable_hash(component['id']), component))
            cumulative += component['triangles']
    for _, _, component in sorted(ranked, key=lambda row: row[:2]):
        if component['id'] in chosen:
            continue
        if used + component['triangles'] <= triangle_budget:
            chosen[component['id']] = component
            used += component['triangles']
    return list(chosen.values()), len(cells)


def compensate_foliage(mesh, components, selected, cell_size, target_area, max_scale):
    """Enlarge intact bent leaf pieces within the source's 26-plane envelope.

    Each connected piece receives a uniform scale about its own centroid. This
    preserves its bend, UVs and authored corner normals, while filling some of
    the surface removed by distant whole-piece thinning. No pieces rotate to
    the camera, and no new image planes or enclosing canopy meshes are made.
    """
    axes = np.array([(x, y, z) for x in (-1, 0, 1) for y in (-1, 0, 1)
                     for z in (-1, 0, 1) if (x, y, z) != (0, 0, 0)], dtype=float)
    coords = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get('co', coords)
    coords = coords.reshape(-1, 3)
    leaf_ids = sorted({v for component in components for v in component['vertices']})
    leaf_coords = coords[leaf_ids]
    envelope = np.array([np.max(leaf_coords @ axis) for axis in axes])
    source_cells, selected_cells = Counter(), Counter()
    key_for = lambda component: tuple(np.floor(component['center'] / cell_size).astype(int))
    for component in components:
        source_cells[key_for(component)] += component['area']
    for component in selected:
        selected_cells[key_for(component)] += component['area']
    transforms, scales, expanded_area = {}, [], 0.0
    max_envelope_error = 0.0
    for component in selected:
        key = key_for(component)
        scale = min(max_scale, max(1.0, math.sqrt(target_area * source_cells[key] /
                                                 selected_cells[key])))
        center = component['center']
        points = coords[list(component['vertices'])]
        extent = np.max((points - center) @ axes.T, axis=0)
        positive = extent > 1e-9
        allowed = (envelope - center @ axes.T)[positive] / extent[positive]
        # Numerical envelope noise must never shrink the original piece.
        scale = min(scale, max(1.0, float(np.min(allowed))))
        transformed = center + (points - center) * scale
        max_envelope_error = max(max_envelope_error,
                                 float(np.max(transformed @ axes.T - envelope)))
        for vertex in component['vertices']:
            transforms[vertex] = (center, scale)
        scales.append(scale)
        expanded_area += component['area'] * scale * scale
    return transforms, {
        'source_leaf_area_target': target_area,
        'expanded_leaf_area_fraction': expanded_area / sum(c['area'] for c in components),
        'piece_scale_min': min(scales), 'piece_scale_median': float(np.median(scales)),
        'piece_scale_max': max(scales),
        'source_envelope_max_error_m': max_envelope_error,
        'uniform_centroid_expansion_preserves_bends_uvs_and_normals': True,
    }


def copy_polygons(source, face_indices, name, material, vertex_transforms=None):
    """Copy source polygons exactly, including every original corner UV."""
    original = source.data
    face_indices = sorted(face_indices)
    vertex_ids = sorted({v for i in face_indices for v in original.polygons[i].vertices})
    remap = {old: new for new, old in enumerate(vertex_ids)}
    verts = []
    for vertex in vertex_ids:
        point = np.array(original.vertices[vertex].co[:])
        if vertex_transforms and vertex in vertex_transforms:
            center, scale = vertex_transforms[vertex]
            point = center + (point - center) * scale
        verts.append(tuple(point))
    faces = [[remap[v] for v in original.polygons[i].vertices] for i in face_indices]
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.materials.append(material)
    uv = data.uv_layers.new(name=original.uv_layers.active.name)
    source_uv = original.uv_layers.active.data
    all_uv = np.array([source_uv[loop].uv[:] for i in face_indices
                       for loop in original.polygons[i].loop_indices], dtype=np.float32)
    uv.data.foreach_set('uv', all_uv.ravel())
    for new_face, source_index in zip(data.polygons, face_indices):
        new_face.use_smooth = original.polygons[source_index].use_smooth
    data.update()
    # The scan includes authored split normals across bark UV seams and bent
    # leaves. Smooth flags alone would recompute these and alter the shading.
    if original.has_custom_normals:
        source_normals = np.empty(len(original.loops)*3, dtype=np.float32)
        original.corner_normals.foreach_get('vector', source_normals)
        loop_ids = np.array([loop for i in face_indices
                             for loop in original.polygons[i].loop_indices])
        copied_normals = source_normals.reshape(-1, 3)[loop_ids]
        data.normals_split_custom_set(copied_normals.tolist())
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = source.matrix_world.copy()
    return obj


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def simplify_wood(obj, target):
    before = triangles(obj)
    if before <= target:
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new('Bark surface simplification', 'DECIMATE')
    modifier.ratio = target / before
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for face in obj.data.polygons:
        face.use_smooth = True
    obj.select_set(False)


def image_node(nodes, path, non_color=False):
    image = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        image.colorspace_settings.name = 'Non-Color'
    node = nodes.new('ShaderNodeTexImage')
    node.image = image
    return node


def make_materials():
    """Neutral original photographed albedo; runtime can use the same names."""
    paths = OUTPUT / 'textures'
    material_paths = {
        'branches': ('branch_diff_1k.png', 'branch_nor_gl_1k.png'),
        'leaves': ('leaves_diff_1k.png', 'leaves_nor_gl_1k.png'),
        'trunk': ('diff_1k.jpg', 'nor_gl_1k.png'),
    }
    results = {}
    for kind, (diffuse, normal) in material_paths.items():
        material = bpy.data.materials.new('tree_small_02_' + kind)
        material.use_nodes = True
        material.diffuse_color = (.19, .28, .105, 1) if kind == 'leaves' else (.31, .245, .18, 1)
        material.use_backface_culling = kind != 'leaves'
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = nodes.get('Principled BSDF')
        principled.inputs['Roughness'].default_value = .9
        principled.inputs['Specular IOR Level'].default_value = .22
        albedo = image_node(nodes, paths / ('tree_small_02_' + diffuse))
        links.new(albedo.outputs['Color'], principled.inputs['Base Color'])
        normal_tex = image_node(nodes, paths / ('tree_small_02_' + normal), True)
        normal_node = nodes.new('ShaderNodeNormalMap')
        normal_node.inputs['Strength'].default_value = .65 if kind == 'leaves' else 1.0
        links.new(normal_tex.outputs['Color'], normal_node.inputs['Color'])
        links.new(normal_node.outputs['Normal'], principled.inputs['Normal'])
        if kind == 'leaves':
            # The existing runtime texture combines the source alpha and diffuse.
            links.new(albedo.outputs['Alpha'], principled.inputs['Alpha'])
            material.surface_render_method = 'DITHERED'
        results[kind] = material
    return results


def glb_report(path):
    content = path.read_bytes()
    length, kind = struct.unpack_from('<II', content, 12)
    if kind != 0x4E4F534A:
        raise RuntimeError('GLB JSON chunk missing')
    document = json.loads(content[20:20+length])
    count = sum(document['accessors'][p['indices']]['count']//3
                for mesh in document['meshes'] for p in mesh['primitives'])
    return {'path': str(path), 'triangles': count, 'bytes': len(content),
            'sha256': hashlib.sha256(content).hexdigest(),
            'materials': [m['name'] for m in document.get('materials', [])]}


def export_objects(objects, path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    # The app supplies these exact PBR textures at runtime. Export named viewport
    # materials so each LOD does not embed another copy of the full texture set.
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB',
        use_selection=True, export_materials='VIEWPORT', export_yup=True,
        export_cameras=False, export_lights=False, export_apply=True)


def render_comparison(source, levels):
    """Actual multi-angle 3D renders. These are QA files, never runtime sprites."""
    QA_OUTPUT.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    available = {item.identifier for item in scene.render.bl_rna.properties['engine'].enum_items}
    scene.render.engine = 'CYCLES' if '--render-cpu' in sys.argv else ('BLENDER_EEVEE' if 'BLENDER_EEVEE' in available else 'BLENDER_EEVEE_NEXT')
    if scene.render.engine == 'CYCLES':
        scene.cycles.device = 'CPU'
        scene.cycles.samples = 16
        scene.cycles.use_denoising = True
        scene.render.threads_mode = 'FIXED'
        scene.render.threads = 3
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('Tree QA daylight')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value = (.68, .78, .96, 1)
    background.inputs['Strength'].default_value = .7
    light_data = bpy.data.lights.new('Tree QA sun', 'SUN')
    light_data.energy = 2.0
    light_data.angle = math.radians(15)
    sun = bpy.data.objects.new('Tree QA sun', light_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(32), math.radians(-18), math.radians(-35))
    camera_data = bpy.data.cameras.new('Tree QA camera')
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 5.35
    camera = bpy.data.objects.new('Tree QA camera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    corners = [source.matrix_world @ Vector(c) for c in source.bound_box]
    center = Vector([(min(v[i] for v in corners)+max(v[i] for v in corners))*.5 for i in range(3)])
    source_masks = {}
    all_trees = [source] + [obj for objects in levels.values() for obj in objects]
    for label, objects in {'source': [source], **levels}.items():
        if label in ('far', 'distant', 'horizon', 'baseline'):
            continue
        for obj in all_trees:
            obj.hide_render = obj not in objects
        for angle in (0, 90, 180, 270):
            theta = math.radians(angle)
            camera.location = center + Vector((math.sin(theta)*11, -math.cos(theta)*11, .9))
            camera.rotation_euler = (center-camera.location).to_track_quat('-Z', 'Y').to_euler()
            scene.render.filepath = str(QA_OUTPUT / f'{label}_{angle}.png')
            bpy.ops.render.render(write_still=True)
            print('TREE_V3_RENDER', scene.render.filepath, flush=True)
            saved = bpy.data.images.load(scene.render.filepath, check_existing=False)
            pixels = np.empty(saved.size[0]*saved.size[1]*4, dtype=np.float32)
            saved.pixels.foreach_get(pixels)
            alpha = pixels.reshape(saved.size[1],saved.size[0],4)[:, :, 3]
            mask = alpha > .5
            if label == 'source':
                source_masks[angle] = mask.copy()
            else:
                reference = source_masks[angle]
                print('TREE_V3_RENDER_COMPARISON', json.dumps({'lod':label, 'angle':angle,
                    'source_opaque_pixels':int(reference.sum()),
                    'new_opaque_pixels':int(mask.sum()),
                    'silhouette_pixel_recall':float(np.logical_and(mask,reference).sum()/reference.sum()),
                    'pixel_coverage_ratio':float(mask.sum()/reference.sum())}), flush=True)
            bpy.data.images.remove(saved)


def render_far_comparison(source, levels, footprints=(48, 96), qa_name='far_revision'):
    """CPU renders at the intended small screen footprints, never game assets."""
    output = QA_OUTPUT / qa_name
    output.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 3
    scene.render.use_persistent_data = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new('Distant tree QA daylight')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.68, .78, .96, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .7
    light_data = bpy.data.lights.new('Distant tree QA sun', 'SUN')
    light_data.energy = 2
    light_data.angle = math.radians(15)
    sun = bpy.data.objects.new('Distant tree QA sun', light_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(32), math.radians(-18), math.radians(-35))
    camera_data = bpy.data.cameras.new('Distant tree QA camera')
    camera_data.type = 'ORTHO'
    # The requested tree height fits inside a slightly wider square canvas.
    camera_data.ortho_scale = source.dimensions.z * 1.25
    camera = bpy.data.objects.new('Distant tree QA camera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    corners = [source.matrix_world @ Vector(c) for c in source.bound_box]
    center = Vector([(min(v[i] for v in corners) + max(v[i] for v in corners)) * .5
                     for i in range(3)])
    variants = {'source': [source], **levels}
    all_trees = [obj for objects in variants.values() for obj in objects]
    for material in source.data.materials:
        if 'leaves' not in material.name:
            continue
        nodes, links = material.node_tree.nodes, material.node_tree.links
        principled = nodes.get('Principled BSDF')
        alpha_source = principled.inputs['Alpha'].links[0].from_socket
        cutout = nodes.new('ShaderNodeMath')
        cutout.operation = 'GREATER_THAN'
        cutout.inputs[1].default_value = .34
        links.new(alpha_source, cutout.inputs[0])
        links.new(cutout.outputs[0], principled.inputs['Alpha'])
    rows = []
    for footprint in footprints:
        scene.render.resolution_x = scene.render.resolution_y = round(footprint * 1.25)
        for angle in range(0, 360, 45):
            theta = math.radians(angle)
            camera.location = center + Vector((math.sin(theta) * 11, -math.cos(theta) * 11, .9))
            camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
            reference = None
            for label, objects in variants.items():
                for obj in all_trees:
                    obj.hide_render = obj not in objects
                path = output / f'{label}_{footprint}_{angle}.png'
                scene.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                saved = bpy.data.images.load(str(path), check_existing=False)
                pixels = np.empty(saved.size[0] * saved.size[1] * 4, dtype=np.float32)
                saved.pixels.foreach_get(pixels)
                alpha = pixels.reshape(saved.size[1], saved.size[0], 4)[:, :, 3].copy()
                bpy.data.images.remove(saved)
                if label == 'source':
                    reference = alpha
                    continue
                mask, source_mask = alpha > .5, reference > .5
                row = {'lod': label, 'tree_height_px': footprint, 'angle': angle,
                       'source_alpha_area': float(reference.sum()),
                       'alpha_area': float(alpha.sum()),
                       'alpha_area_ratio': float(alpha.sum() / reference.sum()),
                       'weighted_recall': float(np.minimum(alpha, reference).sum() / reference.sum()),
                       'opaque_pixel_recall': float(np.logical_and(mask, source_mask).sum() / max(1, source_mask.sum())),
                       'opaque_pixel_iou': float(np.logical_and(mask, source_mask).sum() / max(1, np.logical_or(mask, source_mask).sum()))}
                rows.append(row)
                print('TREE_V3_FAR_QA', json.dumps(row), flush=True)
    report = {'method': f'Cycles CPU actual {list(footprints)} px tree height, 8 angles, common 0.34 alpha cutout, 32 samples',
              'limitation': 'CPU reference does not reproduce Godot texture mip selection, compression or alpha scissor exactly.',
              'rows': rows}
    (output / 'coverage.json').write_text(json.dumps(report, indent=2))
    print('TREE_V3_FAR_QA_SAVED', str(output / 'coverage.json'), flush=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    source = bpy.data.objects['tree_small_02_LOD1']
    inspect_source(source)
    if '--inspect' in sys.argv:
        return
    for obj in list(bpy.data.objects):
        if obj != source:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in bpy.data.collections:
        collection.hide_render = False
        collection.hide_viewport = False
    source.hide_set(False)
    source.hide_render = False
    source.hide_viewport = False
    bpy.context.view_layer.objects.active = source
    source.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    original_materials = [m.name for m in source.data.materials]
    materials = make_materials()
    foliage_index = next(i for i, name in enumerate(original_materials) if 'leaves' in name)
    components = components_for_material(source.data, foliage_index)
    original_leaf_triangles = sum(c['triangles'] for c in components)
    original_area = sum(c['area'] for c in components)
    levels = {}
    settings = [
        ('near', 230000, 22000, 6000, .14),
        ('mid', 50000, 5500, 1800, .25),
        ('far', 18500, 1100, 350, .32),
        ('distant', 6400, 1100, 350, .48),
        ('horizon', 2220, 220, 60, .65),
    ]
    if '--horizon-only' in sys.argv:
        settings = [row for row in settings if row[0] == 'horizon']
    elif '--far-only' in sys.argv:
        settings = [row for row in settings if row[0] in ('far', 'distant')]
    for lod, leaf_budget, branch_budget, trunk_budget, cell in settings:
        selected, occupied_cells = choose_foliage(components, leaf_budget, cell)
        leaf_faces = [i for component in selected for i in component['faces']]
        transforms, compensation = None, None
        if lod in ('far', 'distant', 'horizon'):
            area_target, max_scale = {'far': (.72, 2.2), 'distant': (.66, 2.9),
                                      'horizon': (.86, 6.0)}[lod]
            transforms, compensation = compensate_foliage(source.data, components, selected,
                cell, area_target, max_scale)
        leaf = copy_polygons(source, leaf_faces, f'Tree v3 {lod} leaves', materials['leaves'], transforms)
        objects = [leaf]
        branch_piece_report = None
        for index, name in enumerate(original_materials):
            if index == foliage_index:
                continue
            kind = 'branches' if 'branch' in name else 'trunk'
            faces = [p.index for p in source.data.polygons if p.material_index == index]
            if lod == 'horizon' and kind == 'branches':
                # Collapse cannot remove the last face of every disconnected
                # twig. Keep the principal source branch pieces first so this
                # screen-size tier spends its geometry on the canopy outline.
                branch_parts = components_for_material(source.data, index)
                retained = sorted(branch_parts, key=lambda c: c['area'], reverse=True)[:24]
                faces = [face for part in retained for face in part['faces']]
                branch_piece_report = {
                    'source_parts': len(branch_parts), 'retained_parts': len(retained),
                    'retained_original_area_fraction': sum(c['area'] for c in retained) /
                        sum(c['area'] for c in branch_parts),
                }
            obj = copy_polygons(source, faces, f'Tree v3 {lod} {kind}', materials[kind])
            simplify_wood(obj, branch_budget if kind == 'branches' else trunk_budget)
            objects.append(obj)
        levels[lod] = objects
        path = OUTPUT / f'tree_v3_{lod}.glb'
        export_objects(objects, path)
        report = glb_report(path)
        report.update({'lod': lod, 'source_height_m': source.dimensions.z,
                       'foliage_components_kept': len(selected),
                       'foliage_components_source': len(components),
                       'foliage_triangles': triangles(leaf),
                       'source_foliage_triangles': original_leaf_triangles,
                       'foliage_surface_area_fraction': sum(c['area'] for c in selected)/original_area,
                       'occupied_canopy_cells_preserved': occupied_cells,
                       'canopy_cell_m': cell,
                       'whole_component_coordinates_and_uvs_preserved': transforms is None,
                       'source_uvs_and_bent_piece_geometry_preserved': True,
                       'authored_leaf_corner_normals_preserved': leaf.data.has_custom_normals})
        if compensation:
            report['density_compensation'] = compensation
        if branch_piece_report:
            report['horizon_principal_branches'] = branch_piece_report
        print('TREE_V3_EXPORT', json.dumps(report), flush=True)
        for obj in objects:
            obj.hide_render = True
    # Match source and exports to the same neutral material setup for comparison.
    for index, name in enumerate(original_materials):
        source.data.materials[index] = materials['leaves' if 'leaves' in name else ('branches' if 'branch' in name else 'trunk')]
    if '--render' in sys.argv or '--render-cpu' in sys.argv:
        render_comparison(source, levels)
    if '--render-far-qa' in sys.argv:
        selected, _ = choose_foliage(components, 6400, .48)
        baseline = copy_polygons(source, [i for c in selected for i in c['faces']],
                                 'Tree v3 original far leaves', materials['leaves'])
        render_far_comparison(source, {'baseline': [baseline, *levels['distant'][1:]],
                                      'far': levels['far'], 'distant': levels['distant']})
    if '--render-horizon-qa' in sys.argv:
        render_far_comparison(source, {'horizon': levels['horizon']},
                              footprints=(32, 48), qa_name='horizon_revision')


if __name__ == '__main__':
    main()
