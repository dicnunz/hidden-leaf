extends SceneTree

var stage: Node3D
var camera: Camera3D
var left: Node3D
var right: Node3D
var report: Array = []
const OUTPUT := 'res://.build/foliage-views'

func _initialize() -> void:
	call_deferred('_run')

func _material(name_text: String, optimized: bool) -> Material:
	var base := 'res://assets/vegetation/textures/tree_small_02_'
	if name_text.contains('leaves'):
		var material := ShaderMaterial.new()
		material.shader = load('res://scripts/canopy.gdshader')
		material.set_shader_parameter('leaf_color', load('res://assets/vegetation/optimized_leaves_color.png' if optimized else base + 'leaves_diff_1k.png'))
		material.set_shader_parameter('leaf_normal', load('res://assets/vegetation/optimized_leaves_normal.png' if optimized else base + 'leaves_nor_gl_1k.png'))
		return material
	var material := StandardMaterial3D.new()
	var branch := name_text.contains('branch')
	material.albedo_texture = load(base + ('branch_diff_1k.png' if branch else 'diff_1k.jpg'))
	material.normal_enabled = true
	material.normal_texture = load(base + ('branch_nor_gl_1k.png' if branch else 'nor_gl_1k.png'))
	material.roughness = .9
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

func _materials(node: Node, optimized: bool) -> void:
	if node is MeshInstance3D:
		node.layers = 2 if optimized else 1
		for i in range(node.mesh.get_surface_count()):
			var material: Material = node.mesh.surface_get_material(i)
			node.set_surface_override_material(i, _material(material.resource_name, optimized))
	for child in node.get_children(): _materials(child, optimized)

func _tree(path: String, optimized: bool) -> Node3D:
	var node: Node3D = load(path).instantiate()
	_materials(node, optimized)
	stage.add_child(node)
	return node

func _label(text_value: String, x: float) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(x, 24)
	label.add_theme_font_size_override('font_size', 24)
	root.add_child(label)

func _run() -> void:
	root.size = Vector2i(1600,900)
	root.scaling_3d_scale = 1.0
	root.use_taa = true
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.42,.58,.73)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.68,.76,.85)
	environment.ambient_light_energy = .65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46,-32,0)
	sun.light_color = Color(1,.94,.84)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300,300)
	ground.mesh = plane
	ground.layers = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.22,.27,.16)
	material.roughness = 1.0
	ground.material_override = material
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.near = .05
	stage.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for distance_value: float in [8.0,20.0,45.0]:
		var lod := 'near' if distance_value < 32.0 else 'mid'
		left = _tree('res://assets/vegetation/tree_v3_%s.glb' % lod, false)
		right = _tree('res://assets/vegetation/optimized_%s.glb' % lod, true)
		# Natural source tree height is 4.564 m. Both specimens retain unit scale.
		camera.position = Vector3(0,2.3,distance_value)
		camera.rotation = Vector3.ZERO
		for angle: float in [0.0,90.0]:
			left.rotation_degrees.y = angle
			right.rotation_degrees.y = angle
			for variant: String in ['original','optimized']:
				left.visible = variant == 'original'
				right.visible = variant == 'optimized'
				for frame in range(60): await process_frame
				await RenderingServer.frame_post_draw
				var path := OUTPUT + '/%02dm_%03ddeg_%s.png' % [int(distance_value),int(angle),variant]
				var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
				assert(error == OK)
				report.append({'distance_m':distance_value,'angle_degrees':angle,'variant':variant,'lod':lod,'path':path,'draw_calls':Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),'primitives':Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),'frame_time_ms':Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
		left.queue_free()
		right.queue_free()
		await process_frame
	var file := FileAccess.open(OUTPUT + '/report.json', FileAccess.WRITE)
	file.store_string(JSON.stringify({'note':'Paired visual diagnostic only; frame timings are not sustained performance acceptance. Unit-scale source trees, identical camera and tree transform in sequential original/optimized snapshots. Native 1600x900 TAA.','views':report},'\t'))
	print('FOLIAGE_COMPARISON ', JSON.stringify(report))
	quit()
