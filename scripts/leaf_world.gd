extends Node3D
class_name LeafWorld

const ForestScript = preload("res://scripts/forest.gd")
const SOURCE_META := "res://assets/village_v3.json"
const SOURCE_GEOMETRY := "res://assets/villages/leaf.glb"
const TREE_MODELS := [
	"optimized_near.glb", "optimized_mid.glb", "optimized_far.glb",
	"tree_v3_distant.glb", "tree_v3_horizon.glb"
]

var environment: Environment
var sun: DirectionalLight3D
var meta: Dictionary = {}
var bookmarks: Array = []
var geometry: Node3D
var forest: Node3D
var material_cache: Dictionary = {}
var tree_materials: Dictionary = {}
var world_meshes := 0
var world_faces := 0
var trees: Array = []

## Builds the original Leaf settlement for editor/runtime baking. This script has
## no automatic construction path; a deserialized runtime scene is already ready.
func construct() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_META))
	if meta.is_empty():
		push_error("Leaf metadata could not be read.")
		return
	bookmarks = _leaf_bookmarks()
	_create_environment()
	geometry = load(SOURCE_GEOMETRY).instantiate()
	geometry.name = "Geometry"
	add_child(geometry)
	_configure_meshes(geometry)
	_create_landmark_lights()
	_create_collisions()
	_create_forest()
	_create_groundcover()
	set_meta("village", {
		"id": "leaf",
		"name": "Konohagakure",
		"era": meta.get("era", ""),
		"bookmarks": bookmarks,
		"mesh_instances": world_meshes,
		"triangles": world_faces,
		"trees": trees.size()
	})

func _leaf_bookmarks() -> Array:
	return [
		{"name": "Main Gate", "position": [0.0, 0.22, 394.0], "target": [0.0, 15.0, 345.0]},
		{"name": "Ichiraku", "position": [13.0, 0.24, 143.6], "target": [19.4, 2.65, 144.0]},
		{"name": "Hokage residence", "position": [0.0, 0.22, -174.0], "target": [0.0, 22.0, -234.0]},
		{"name": "Arena", "position": [-225.0, 0.22, -47.0], "target": [-225.0, 8.0, -90.0]},
		{"name": "Academy", "position": [-92.0, 0.22, -123.0], "target": [-92.0, 6.0, -160.0]},
		{"name": "Overlook", "position": [-50.0, 149.8757, -322.0], "target": [0.0, 25.0, 40.0]}
	]

func _create_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/sky.hdr")
	sky_material.energy_multiplier = 0.8
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.38
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.ssao_radius = 1.1
	environment.ssao_intensity = 1.25
	environment.ssao_power = 1.15
	environment.ssao_enabled = true
	environment.ssil_enabled = false
	environment.ssil_radius = 3.5
	environment.ssil_intensity = 0.65
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.69, 0.78, 0.85)
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.00042
	environment.fog_sky_affect = 0.40
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 130.0
	sun.shadow_bias = 0.2
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = 0.35
	add_child(sun)

func _create_landmark_lights() -> void:
	for landmark: Dictionary in meta.landmarks.landmarks:
		for source: Dictionary in landmark.get("runtime_lights", []):
			var light := OmniLight3D.new()
			var p: Array = source.position
			var color: Array = source.color
			light.name = source.name
			light.position = Vector3(p[0], p[2], -p[1])
			light.light_color = Color(color[0], color[1], color[2])
			light.light_energy = source.energy
			light.light_cull_mask = 2
			light.omni_range = source.range_m
			light.omni_attenuation = 1.4
			light.shadow_enabled = source.shadow
			light.shadow_bias = 0.02
			light.shadow_normal_bias = 0.15
			add_child(light)

func _material(name_text: String) -> Material:
	var key := name_text.split(".")[0]
	if material_cache.has(key):
		return material_cache[key]
	if key in ["road", "earth", "grass", "plateau"]:
		var ground := ShaderMaterial.new()
		ground.shader = load("res://scripts/ground.gdshader")
		var texture_set := "forest_ground_04" if key in ["grass", "plateau"] else "brown_mud_rocks_01"
		var source := "res://assets/textures/%s/%s" % [texture_set, texture_set]
		ground.set_shader_parameter("ground_color", load(source + "_diff_2k.jpg"))
		ground.set_shader_parameter("ground_normal", load(source + "_nor_gl_2k.jpg"))
		ground.set_shader_parameter("earth_tint", Color(0.63, 0.53, 0.37) if key == "road" else (Color(0.52, 0.43, 0.29) if key == "earth" else Color(0.29, 0.35, 0.18)))
		ground.set_shader_parameter("detail_strength", 0.30 if key == "road" else 0.40)
		ground.set_shader_parameter("texture_scale", 0.27)
		material_cache[key] = ground
		return ground
	var result := StandardMaterial3D.new()
	result.resource_name = key
	var rgba: Array = meta.materials.get(key, [0.5, 0.5, 0.5, 1.0])
	var tint := Color(pow(rgba[0], 0.65), pow(rgba[1], 0.65), pow(rgba[2], 0.65))
	result.albedo_color = tint * Color(1.15, 1.15, 1.15)
	if key.begins_with("ichiraku_"):
		result.albedo_color = Color(rgba[0], rgba[1], rgba[2]) * Color(1.05, 1.05, 1.05)
	result.roughness = 0.87
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var texture_set := ""
	var uv_repeats_per_metre := 0.35
	if key in ["plaster", "cream", "white", "ochre", "peach", "sage", "red"]:
		texture_set = "plastered_wall"; uv_repeats_per_metre = 0.42
	elif key in ["fabric", "ichiraku_cloth"]:
		texture_set = "rough_linen"; uv_repeats_per_metre = 1.6
	elif key.begins_with("roof"):
		texture_set = "clay_roof_tiles_03"; uv_repeats_per_metre = 0.42
	elif key in ["wood", "wood_light", "trim", "bark"]:
		texture_set = "medieval_wood"; uv_repeats_per_metre = 0.5
	elif key in ["road", "earth"]:
		texture_set = "brown_mud_rocks_01"; uv_repeats_per_metre = 0.30
	elif key in ["grass", "plateau"]:
		texture_set = "forest_ground_04"; uv_repeats_per_metre = 0.2
	elif key in ["stone", "cliff", "rock_light", "rock_shadow", "cliff_stratum"] or key.begins_with("monument"):
		texture_set = "rock_boulder_dry"; uv_repeats_per_metre = 0.16 if key.begins_with("monument") else 0.10
	if not texture_set.is_empty():
		var base := "res://assets/textures/%s/%s" % [texture_set, texture_set]
		result.albedo_texture = load(base + "_diff_2k.jpg")
		result.normal_enabled = true
		result.normal_texture = load(base + "_nor_gl_2k.jpg")
		result.normal_scale = 0.38 if key.begins_with("monument") else 0.75
		result.roughness_texture = load(base + "_rough_2k.jpg")
		result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		# leaf.glb carries author-projected metric UVs. Scale those UVs directly.
		result.uv1_triplanar = false
		result.uv1_world_triplanar = false
		result.uv1_scale = Vector3.ONE * uv_repeats_per_metre
		if key.begins_with("roof"):
			result.albedo_texture = load(base + "_rough_2k.jpg")
			result.albedo_color = tint * Color(1.28, 1.28, 1.28)
			result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if key in ["fabric", "ichiraku_cloth"]:
		result.albedo_texture = null
		result.normal_scale = 0.12
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if key == "roof_teal":
		result.albedo_texture = null
		result.normal_scale = 0.10
		result.roughness = 0.63
		result.metallic = 0.16
	if key in ["plaster", "cream", "white", "ochre", "peach", "sage", "red"]:
		result.normal_scale = 0.16
	if key == "glass":
		result.albedo_color = Color(0.11, 0.18, 0.19); result.metallic = 0.4; result.roughness = 0.24
	if key == "metal":
		result.metallic = 0.8; result.roughness = 0.32
	if key == "ichiraku_chrome":
		result.metallic = 0.84; result.roughness = 0.29
	if key == "ichiraku_seat": result.roughness = 0.40
	if key in ["ichiraku_roof", "ichiraku_roof_faded"]:
		result.metallic = 0.18; result.roughness = 0.67
	if key == "water":
		result.albedo_color = Color(0.10, 0.26, 0.25); result.roughness = 0.12; result.metallic = 0.5
	if key == "glow":
		result.emission_enabled = true; result.emission = Color(1.0, 0.54, 0.15); result.emission_energy_multiplier = 1.5
	material_cache[key] = result
	return result

func _configure_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		world_meshes += 1
		for index in range(mesh_node.mesh.get_surface_count()):
			var original := mesh_node.mesh.surface_get_material(index)
			if original:
				mesh_node.set_surface_override_material(index, _material(original.resource_name))
		world_faces += mesh_node.mesh.get_faces().size() / 3
		var label := str(mesh_node.name)
		if label.contains("Ichiraku"): mesh_node.layers = 3
		if label.begins_with("Village"):
			mesh_node.visibility_range_end = 720.0
			mesh_node.visibility_range_end_margin = 50.0
		if label.contains("ground") or label.contains("gardens"):
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flexible_cloth := label.contains("ichiraku_cloth") or label.contains("ichiraku_ink")
		if not flexible_cloth and (label.contains("Landmark") or label.contains("Main gate") or label.contains("defensive wall") or label.contains("Hokage Residence") or label.contains("weathered continuous") or label.contains("ground") or label.contains("gardens") or label.contains("Market lane")):
			var body := StaticBody3D.new()
			var collision := CollisionShape3D.new()
			collision.shape = mesh_node.mesh.create_trimesh_shape()
			body.add_child(collision)
			mesh_node.add_child(body)
	for child in node.get_children():
		_configure_meshes(child)

func _add_box(position_value: Vector3, size: Vector3, yaw: float = 0.0, occlude: bool = false) -> void:
	var body := StaticBody3D.new()
	body.position = position_value
	body.rotation.y = yaw
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	if occlude:
		var occluder := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = size * 0.96
		occluder.occluder = box
		body.add_child(occluder)

func _add_cylinder(position_value: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = position_value
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _create_collisions() -> void:
	_add_box(Vector3(0.0, -0.45, 0.0), Vector3(12000.0, 0.90, 12000.0))
	_add_box(Vector3(0.0, 0.08, 55.0), Vector3(22.0, 0.20, 610.0))
	for d: Dictionary in meta.districts.colliders:
		var position_value := Vector3(d.x, d.z, -d.y)
		if d.shape == "cylinder":
			_add_cylinder(position_value, d.radius, d.height)
			var occluder := OccluderInstance3D.new()
			var box := BoxOccluder3D.new()
			box.size = Vector3(d.radius * 1.32, d.height * 0.95, d.radius * 1.32)
			occluder.occluder = box
			occluder.position = position_value
			add_child(occluder)
		else:
			_add_box(position_value, Vector3(d.width, d.height, d.depth), d.rotation_z, d.height > 3.0)
	for plant: Dictionary in meta.districts.get("planting", []):
		_add_cylinder(Vector3(plant.x, plant.z - 0.49 + 0.2825, -plant.y), 0.39, 0.565)

func _tree_material(material_name: String) -> Material:
	var kind := "leaves_cards" if material_name.contains("leaves_cards") else ("leaves" if material_name.contains("leaves") else ("branch" if material_name.contains("branch") else "trunk"))
	if tree_materials.has(kind):
		return tree_materials[kind]
	var base := "res://assets/vegetation/textures/tree_small_02_"
	var result: Material
	if kind in ["leaves", "leaves_cards"]:
		var leaf := ShaderMaterial.new()
		leaf.shader = load("res://scripts/canopy.gdshader")
		if kind == "leaves_cards":
			leaf.set_shader_parameter("leaf_color", load("res://assets/vegetation/optimized_leaves_color.png"))
			leaf.set_shader_parameter("leaf_normal", load("res://assets/vegetation/optimized_leaves_normal.png"))
		else:
			leaf.set_shader_parameter("leaf_color", load(base + "leaves_diff_1k.png"))
			leaf.set_shader_parameter("leaf_normal", load(base + "leaves_nor_gl_1k.png"))
		result = leaf
	else:
		var bark := StandardMaterial3D.new()
		bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		bark.roughness = 0.9
		bark.albedo_texture = load(base + ("branch_diff_1k.png" if kind == "branch" else "diff_1k.jpg"))
		bark.normal_enabled = true
		bark.normal_texture = load(base + ("branch_nor_gl_1k.png" if kind == "branch" else "nor_gl_1k.png"))
		result = bark
	tree_materials[kind] = result
	return result

func _collect_tree_mesh(node: Node, transform_value: Transform3D, merged: ArrayMesh) -> void:
	var transform_next := transform_value
	if node is Node3D:
		transform_next = transform_value * node.transform
	if node is MeshInstance3D:
		for index in range(node.mesh.get_surface_count()):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.append_from(node.mesh, index, transform_next)
			var source_material: Material = node.mesh.surface_get_material(index)
			surface.set_material(_tree_material(source_material.resource_name if source_material else "trunk"))
			surface.commit(merged)
	for child in node.get_children():
		_collect_tree_mesh(child, transform_next, merged)

func _create_forest() -> void:
	trees = meta.landscape.forest_trees + meta.gardens.village_trees + meta.landmarks.trees + meta.districts.get("courtyard_trees", [])
	var lod_meshes: Array = []
	for filename: String in TREE_MODELS:
		var source_scene: Node3D = load("res://assets/vegetation/" + filename).instantiate()
		var merged := ArrayMesh.new()
		_collect_tree_mesh(source_scene, Transform3D.IDENTITY, merged)
		source_scene.free()
		lod_meshes.append(merged)
	forest = ForestScript.new()
	forest.name = "Forest"
	add_child(forest)
	forest.configure(trees, lod_meshes, _add_cylinder)
	_create_street_plants(lod_meshes[2])

func _create_street_plants(plant_mesh: Mesh) -> void:
	var plants: Array = meta.districts.get("planting", []).duplicate()
	plants.append_array(meta.gardens.village_shrubs)
	plants.append_array(meta.districts.get("courtyard_shrubs", []))
	var cells: Dictionary = {}
	for d: Dictionary in plants:
		var key := Vector2i(floori(d.x / 32.0), floori(d.y / 32.0))
		if not cells.has(key): cells[key] = []
		cells[key].append(d)
	for key: Vector2i in cells:
		var center := Vector3(key.x * 32.0 + 16.0, 0.0, -key.y * 32.0 - 16.0)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = plant_mesh
		multi.instance_count = cells[key].size()
		for index in range(multi.instance_count):
			var d: Dictionary = cells[key][index]
			var height_value := float(d.get("height", 1.2))
			var scale_value := Vector3(height_value / 4.0, height_value / 4.5640373, height_value / 4.0)
			multi.set_instance_transform(index, Transform3D(Basis(Vector3.UP, float(d.get("rotation", 0.0))).scaled(scale_value), Vector3(d.x, float(d.get("z", 0.05)), -d.y) - center))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.position = center
		instance.visibility_range_end = 90.0
		add_child(instance)

func _create_groundcover() -> void:
	var grass_source: Node3D = load("res://assets/vegetation/grass.glb").instantiate()
	var meshes := grass_source.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		grass_source.free()
		return
	var mesh: Mesh = meshes[0].mesh
	var grass_material := StandardMaterial3D.new()
	grass_material.albedo_texture = load("res://assets/vegetation/grass_albedo_alpha.png")
	grass_material.normal_enabled = true
	grass_material.normal_texture = load("res://assets/vegetation/grass_normal.jpg")
	grass_material.albedo_color = Color(0.72, 0.81, 0.56)
	grass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grass_material.alpha_scissor_threshold = 0.42
	grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass_material.roughness = 0.95
	grass_material.backlight_enabled = true
	grass_material.backlight = Color(0.15, 0.21, 0.07)
	grass_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	grass_source.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42389
	var cells: Dictionary = {}
	for d: Dictionary in meta.gardens.village_shrubs:
		var key := Vector2i(floori(d.x / 40.0), floori(d.y / 40.0))
		if not cells.has(key): cells[key] = []
		for _index in range(12):
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * 0.75
			var position_value := Vector3(d.x + sin(angle) * radius, d.z + 0.03, -d.y + cos(angle) * radius)
			var scale_value := rng.randf_range(0.6, 1.1)
			cells[key].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value), position_value))
	for key: Vector2i in cells:
		var center := Vector3(key.x * 40.0 + 20.0, 0.0, -key.y * 40.0 - 20.0)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = cells[key].size()
		for index in range(multi.instance_count):
			var transform_value: Transform3D = cells[key][index]
			transform_value.origin -= center
			multi.set_instance_transform(index, transform_value)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.position = center
		instance.material_override = grass_material
		instance.visibility_range_end = 90.0
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
