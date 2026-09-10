extends Node3D

## Configures original generated geometry. The editor bake stores the resulting
## scene so ordinary exploration does not rebuild materials or collision shapes.
var meta: Dictionary = {}
var environment: Environment
var sun: DirectionalLight3D
var materials: Dictionary = {}
var geometry: Node3D

func construct(id: String) -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/villages/%s.json" % id))
	geometry = load("res://assets/villages/%s.glb" % id).instantiate()
	add_child(geometry)
	configure_meshes(geometry)
	for shape: Dictionary in meta.get("colliders", []):
		var body := StaticBody3D.new()
		body.position = vector(shape.position)
		body.rotation.y = float(shape.get("yaw", 0.0))
		var collision := CollisionShape3D.new()
		if shape.shape == "cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = shape.radius
			cylinder.height = shape.height
			collision.shape = cylinder
		else:
			var box := BoxShape3D.new()
			box.size = vector(shape.size)
			collision.shape = box
		body.add_child(collision)
		add_child(body)
	for bounds: Dictionary in meta.get("occluders", []):
		var occluder := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = vector(bounds.size)
		occluder.occluder = box
		occluder.position = vector(bounds.position)
		occluder.rotation.y = float(bounds.get("yaw",0.0))
		add_child(occluder)
	create_environment(id)
	set_meta("village", meta)

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func configure_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var role: Dictionary = meta.get("mesh_roles", {}).get(str(node.name), {})
		# Large, thin ground bounds produced false occlusion in actual street views.
		# Keep this inexpensive surface visible while buildings retain culling.
		mesh_node.ignore_occlusion_culling = not bool(role.get("occlusion_culling", true))
		for index in range(mesh_node.mesh.get_surface_count()):
			var original := mesh_node.mesh.surface_get_material(index)
			if original:
				mesh_node.set_surface_override_material(index, material(original.resource_name))
		# Geometry remains visible throughout the settlement. Imported mesh LOD
		# supplies detail reduction; whole-building disappearance is not a LOD.
		if not role.get("shadow", true):
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if role.get("collision", false):
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = mesh_node.mesh.create_trimesh_shape()
			body.add_child(shape)
			mesh_node.add_child(body)
	for child in node.get_children():
		configure_meshes(child)

func material(source_name: String) -> Material:
	var key := source_name.split(".")[0]
	if materials.has(key):
		return materials[key]
	var rgba: Array = meta.get("materials", {}).get(key, [0.5, 0.5, 0.5, 1.0])
	var tint := Color(pow(float(rgba[0]), 1.0/1.55), pow(float(rgba[1]), 1.0/1.55), pow(float(rgba[2]), 1.0/1.55))
	var texture_set := "plastered_wall"
	var tile := 2.8
	if key in ["sand_stucco", "sand_rose", "sand_pale", "sand_trim"]:
		texture_set = "worn_cracked_plaster"
		tile = 1.8
	if "rock" in key or "strata" in key:
		texture_set = "rock_boulder_dry"
		tile = 7.0
	elif "ground" in key:
		texture_set = "sand_01" if key.begins_with("sand") else "brown_mud_rocks_01"
		tile = 1.5 if key.begins_with("sand") else 3.0
	elif "wood" in key:
		texture_set = "medieval_wood"
	elif "cloth" in key:
		texture_set = "rough_linen"
		tile = 0.6
	if "shadow" in key or key in ["glass", "metal"]:
		var simple := StandardMaterial3D.new()
		simple.albedo_color = tint
		simple.roughness = 0.76
		materials[key] = simple
		return simple
	var result := ShaderMaterial.new()
	result.shader = load("res://scripts/masonry.gdshader")
	var base := "res://assets/textures/%s/%s" % [texture_set, texture_set]
	result.set_shader_parameter("surface_color", load(base+"_diff_2k.jpg"))
	result.set_shader_parameter("surface_normal", load(base+"_nor_gl_2k.jpg"))
	result.set_shader_parameter("surface_roughness", load(base+"_rough_2k.jpg"))
	result.set_shader_parameter("pigment", tint)
	result.set_shader_parameter("metres_per_repeat", tile)
	result.set_shader_parameter("scan_weight", 0.75 if "rock" in key or "ground" in key else 0.55)
	result.set_shader_parameter("relief", 0.40 if "rock" in key or "ground" in key else 0.24)
	result.set_shader_parameter("mineral", 0.25 if "rock" in key or "ground" in key else 0.0)
	result.set_shader_parameter("patch_wear", 1.0 if texture_set == "worn_cracked_plaster" else 0.0)
	materials[key] = result
	return result

func create_environment(id: String) -> void:
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
	environment.ambient_light_energy = 0.65
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.1
	environment.fog_enabled = true
	environment.fog_density = 0.00075
	environment.fog_light_color = Color(0.74,0.66,0.49)
	environment.fog_sky_affect = 0.15
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38,-38,0)
	sun.light_color = Color(1.0,0.91,0.75)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 130.0
	sun.shadow_normal_bias = 0.8
	add_child(sun)
