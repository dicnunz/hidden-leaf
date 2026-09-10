extends Node3D
## Spatial tree batches retain each source placement and independent trunk physics.
## Every LOD in a cell shares an exact custom bound and therefore its range pivot.
const CELL_SIZE := 24.0
const SOURCE_HEIGHT := 4.5640373
const LOD_DISTANCES := [0.0, 32.0, 105.0, 220.0, 400.0, 1300.0]
var statistics: Dictionary = {}

func configure(trees: Array, lod_meshes: Array, add_collider: Callable) -> void:
	assert(lod_meshes.size() == 5)
	var cells: Dictionary = {}
	for d: Dictionary in trees:
		var key := Vector2i(floori(float(d.x) / CELL_SIZE), floori(float(d.y) / CELL_SIZE))
		if not cells.has(key): cells[key] = []
		cells[key].append(d)
		if Vector2(d.x, d.y).length() < 358.0 and add_collider.is_valid():
			add_collider.call(Vector3(d.x, d.z + d.collider_height / 2.0, -d.y), d.trunk_radius, d.collider_height)
	var source_bound: AABB = lod_meshes[0].get_aabb()
	for mesh: Mesh in lod_meshes:
		source_bound = source_bound.merge(mesh.get_aabb())
	var batch_count := 0
	for key: Vector2i in cells:
		var center := Vector3((key.x + 0.5) * CELL_SIZE, 0.0, -(key.y + 0.5) * CELL_SIZE)
		var transforms: Array[Transform3D] = []
		var bound := AABB()
		for d: Dictionary in cells[key]:
			var scale_value: float = d.height / SOURCE_HEIGHT
			var tr := Transform3D(Basis(Vector3.UP, d.rotation).scaled(Vector3.ONE * scale_value), Vector3(d.x, d.z, -d.y) - center)
			transforms.append(tr)
			var tree_bound: AABB = tr * source_bound
			bound = tree_bound if transforms.size() == 1 else bound.merge(tree_bound)
		# Wind displacement in the source shader scales with each instance.
		bound = bound.grow(0.6)
		for lod in range(5):
			var batch := _batch(lod_meshes[lod], transforms, bound, center)
			batch.name = 'Trees_%d_%d_lod%d' % [key.x, key.y, lod]
			batch.visibility_range_begin = LOD_DISTANCES[lod]
			batch.visibility_range_end = LOD_DISTANCES[lod + 1]
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch_count += 1
		var shadow := _batch(lod_meshes[2], transforms, bound, center)
		shadow.name = 'TreeShadows_%d_%d' % [key.x, key.y]
		shadow.visibility_range_end = 130.0
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		batch_count += 1
	statistics = {'trees': trees.size(), 'cells': cells.size(), 'batches': batch_count, 'cell_size': CELL_SIZE}

func _batch(mesh: Mesh, transforms: Array[Transform3D], bound: AABB, center: Vector3) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()): multi.set_instance_transform(i, transforms[i])
	multi.custom_aabb = bound
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.custom_aabb = bound
	instance.position = center
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)
	return instance
