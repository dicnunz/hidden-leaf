extends SceneTree

const World = preload("res://scripts/village_world.gd")
const Player = preload("res://scripts/player.gd")
var village_id := "sand"
var output_dir := ""
var selected_view := -1
var diagnostic := ""
var runtime_path := ""
var disable_ssao := false
var disable_occlusion := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--village="): village_id = arg.trim_prefix("--village=")
		if arg.begins_with("--qa-out="): output_dir = arg.trim_prefix("--qa-out=")
		if arg.begins_with("--view="): selected_view = int(arg.trim_prefix("--view="))
		if arg.begins_with("--diagnostic="): diagnostic = arg.trim_prefix("--diagnostic=")
		if arg.begins_with("--runtime="): runtime_path = arg.trim_prefix("--runtime=")
		if arg == "--disable-ssao": disable_ssao = true
		if arg == "--disable-occlusion": disable_occlusion = true
	call_deferred("run")

func run() -> void:
	var world: Node3D
	if runtime_path.is_empty():
		world = World.new()
	else:
		var packed := load(runtime_path) as PackedScene
		if packed == null:
			push_error("Preview scene could not load: " + runtime_path)
			quit(1)
			return
		world = packed.instantiate()
	root.add_child(world)
	if disable_occlusion: root.use_occlusion_culling = false
	if runtime_path.is_empty(): world.construct(village_id)
	var world_meta: Dictionary = world.get_meta("village", {})
	var sun: DirectionalLight3D = world.find_children("*", "DirectionalLight3D", true, false)[0]
	var environment: Environment = world.find_children("*", "WorldEnvironment", true, false)[0].environment
	if diagnostic == "shadows_off": sun.shadow_enabled = false
	if diagnostic == "ssao_off" or disable_ssao: environment.ssao_enabled = false
	if diagnostic == "normals_off":
		for mat: Material in world.materials.values():
			if mat is ShaderMaterial: mat.set_shader_parameter("relief",0.0)
	if diagnostic == "bias":
		sun.shadow_bias = 0.8
		sun.shadow_normal_bias = 3.0
	var player := Player.new()
	root.add_child(player)
	player.camera.far = 1800.0
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_2X
	if diagnostic == "temporal":
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.use_taa = true
		sun.shadow_bias = 0.2
		sun.shadow_normal_bias = 1.5
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results: Array = []
	if not output_dir.is_empty(): DirAccess.make_dir_recursive_absolute(output_dir)
	for index in world_meta.bookmarks.size():
		if selected_view >= 0 and index != selected_view: continue
		var point: Dictionary = world_meta.bookmarks[index]
		var position := World.vector(point.position)
		var direction := World.vector(point.target) - (position + Vector3.UP*1.7)
		player.teleport_to(position,atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
		player.enabled = false
		player.set_physics_process(false)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec()-start<2000: await process_frame
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in range(180):
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last = now
		samples.sort()
		var sum := 0.0
		for sample in samples: sum += sample
		results.append({"view":point.name,"mean_ms":sum/samples.size(),"p95_ms":samples[int(samples.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		if not output_dir.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir.path_join("%s-%d.png" % [village_id,results.size()]))
	print("VILLAGE_PREVIEW ",JSON.stringify(results))
	if not output_dir.is_empty():
		FileAccess.open(output_dir.path_join("preview.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()
