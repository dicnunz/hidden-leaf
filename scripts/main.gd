extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/explorer_hud.gd")
const BOOKMARKS = [
	["Main Gate", Vector3(0,.22,394), Vector3(0,15,345)],
	["Ichiraku", Vector3(13,.24,143.6), Vector3(19.4,2.65,144)],
	["Hokage residence", Vector3(0,.22,-174), Vector3(0,22,-234)],
	["Arena", Vector3(-225,.22,-47), Vector3(-225,8,-90)],
	["Academy", Vector3(-92,.22,-123), Vector3(-92,6,-160)],
	["Overlook", Vector3(-50,149.8757,-322), Vector3(0,25,40)]
]
var player: CharacterBody3D
var hud: CanvasLayer
var environment: Environment
var sun: DirectionalLight3D
var meta: Dictionary
var material_cache: Dictionary = {}
var tree_materials: Dictionary = {}
var quality_index := 0
var world_meshes := 0
var world_faces := 0
var load_started := Time.get_ticks_msec()
var ready_ms := 0
var location_timer := 0.0
var qa := false
var bench := false
var bench_frame := 0
var bench_last_usec := 0
var bench_phase := 0
var frame_samples: Array[float] = []
var bench_results: Array = []
var qa_out := ""
var trees: Array = []

func _ready() -> void:
	DisplayServer.window_set_title("Hidden Leaf Explorer")
	qa = "--qa" in OS.get_cmdline_user_args()
	bench = qa and "--benchmark" in OS.get_cmdline_user_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="): qa_out = arg.trim_prefix("--qa-out=")
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v3.json"))
	_create_environment()
	var world: Node3D = load("res://assets/village_v3.glb").instantiate()
	add_child(world)
	_configure_meshes(world)
	_create_landmark_lights()
	_create_collisions()
	_create_forest()
	_create_groundcover()
	player = PlayerScript.new()
	add_child(player)
	player.camera.far = 1600
	hud = HudScript.new()
	add_child(hud)
	hud.setup(player)
	hud.bookmark_selected.connect(visit_bookmark)
	hud.quality_changed.connect(set_quality)
	visit_bookmark(0 if bench else 1)
	set_quality(0)
	get_viewport().size_changed.connect(func(): set_quality(quality_index))
	ready_ms = Time.get_ticks_msec() - load_started
	print("EXPLORER_READY ",JSON.stringify({"load_ms":ready_ms,"mesh_instances":world_meshes,"triangles":world_faces,"trees":trees.size(),"renderer":RenderingServer.get_current_rendering_method()}))
	if bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		hud.set_paused(false)
		player.enabled = false
		player.set_physics_process(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if "--high" in OS.get_cmdline_user_args(): set_quality(1)
		if "--performance" in OS.get_cmdline_user_args(): set_quality(2)

func _create_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky.hdr")
	sky_mat.energy_multiplier = .8
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = .38
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.ssao_radius = 1.1
	environment.ssao_intensity = 1.25
	environment.ssao_power = 1.15
	environment.ssil_enabled = true
	environment.ssil_radius = 3.5
	environment.ssil_intensity = .65
	environment.fog_enabled = true
	environment.fog_light_color = Color(.69,.78,.85)
	environment.fog_light_energy = .7
	environment.fog_density = .00042
	environment.fog_sky_affect = .40
	var env := WorldEnvironment.new()
	env.environment = environment
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color(1.0,.94,.84)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 130
	sun.shadow_bias = .1
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = .35
	add_child(sun)

func _create_landmark_lights() -> void:
	for landmark: Dictionary in meta.landmarks.landmarks:
		for source: Dictionary in landmark.get("runtime_lights",[]):
			var light:=OmniLight3D.new()
			var p: Array=source.position
			var color: Array=source.color
			light.name=source.name
			light.position=Vector3(p[0],p[2],-p[1])
			light.light_color=Color(color[0],color[1],color[2])
			light.light_energy=source.energy
			light.light_cull_mask=2
			light.omni_range=source.range_m
			light.omni_attenuation=1.4
			light.shadow_enabled=source.shadow
			light.shadow_bias=.02
			light.shadow_normal_bias=.15
			add_child(light)

func _material(name_text: String) -> Material:
	var key := name_text.split(".")[0]
	if material_cache.has(key): return material_cache[key]
	if key in ["road","earth","grass","plateau"]:
		var ground:=ShaderMaterial.new()
		ground.shader=load("res://scripts/ground.gdshader")
		var texset: String="forest_ground_04" if key in ["grass","plateau"] else "brown_mud_rocks_01"
		var source: String="res://assets/textures/"+texset+"/"+texset
		ground.set_shader_parameter("ground_color",load(source+"_diff_2k.jpg"))
		ground.set_shader_parameter("ground_normal",load(source+"_nor_gl_2k.jpg"))
		ground.set_shader_parameter("earth_tint",Color(.63,.53,.37) if key=="road" else (Color(.52,.43,.29) if key=="earth" else Color(.29,.35,.18)))
		ground.set_shader_parameter("detail_strength",.30 if key=="road" else .40)
		ground.set_shader_parameter("texture_scale",.27)
		material_cache[key]=ground
		return ground
	var m := StandardMaterial3D.new()
	m.resource_name = key
	var rgba: Array = meta.materials.get(key,[.5,.5,.5,1])
	var tint := Color(pow(rgba[0],.65),pow(rgba[1],.65),pow(rgba[2],.65))
	m.albedo_color = tint * Color(1.15,1.15,1.15)
	if key.begins_with("ichiraku_"):
		m.albedo_color=Color(rgba[0],rgba[1],rgba[2])*Color(1.05,1.05,1.05)
	m.roughness = .87
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var texture_set := ""
	var tiling := .35
	if key in ["plaster","cream","white","ochre","peach","sage","red"]: texture_set="plastered_wall";tiling=.42
	elif key in ["fabric","ichiraku_cloth"]: texture_set="rough_linen";tiling=1.6
	elif key.begins_with("roof"): texture_set="clay_roof_tiles_03";tiling=.42
	elif key in ["wood","wood_light","trim","bark"]: texture_set="medieval_wood";tiling=.5
	elif key in ["road","earth"]: texture_set="brown_mud_rocks_01";tiling=.30
	elif key in ["grass","plateau"]: texture_set="forest_ground_04";tiling=.2
	elif key in ["stone","cliff","rock_light","rock_shadow","cliff_stratum"] or key.begins_with("monument"): texture_set="rock_boulder_dry";tiling=.16 if key.begins_with("monument") else .10
	if texture_set != "":
		var base := "res://assets/textures/"+texture_set+"/"+texture_set
		m.albedo_texture = load(base+"_diff_2k.jpg")
		m.normal_enabled = true
		m.normal_texture = load(base+"_nor_gl_2k.jpg")
		m.normal_scale = .38 if key.begins_with("monument") else .75
		m.roughness_texture = load(base+"_rough_2k.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE*tiling
		m.uv1_triplanar_sharpness = 4.0
		if key.begins_with("roof"):
			m.albedo_texture=load(base+"_rough_2k.jpg")
			m.albedo_color=tint*Color(1.28,1.28,1.28)
			m.cull_mode=BaseMaterial3D.CULL_DISABLED
	if key in ["fabric","ichiraku_cloth"]:
		m.albedo_texture=null
		m.normal_scale=.12
		m.cull_mode=BaseMaterial3D.CULL_DISABLED
	if key=="roof_teal":
		m.albedo_texture=null
		m.normal_scale=.10
		m.roughness=.63
		m.metallic=.16
	if key in ["plaster","cream","white","ochre","peach","sage","red"]:m.normal_scale=.16
	if key=="glass":
		m.albedo_color=Color(.11,.18,.19)
		m.metallic=.4
		m.roughness=.24
	if key=="metal": m.metallic=.8;m.roughness=.32
	if key=="ichiraku_chrome":m.metallic=.84;m.roughness=.29
	if key=="ichiraku_seat":m.roughness=.40
	if key in ["ichiraku_roof","ichiraku_roof_faded"]:m.metallic=.18;m.roughness=.67
	if key=="water":
		m.albedo_color=Color(.10,.26,.25);m.roughness=.12;m.metallic=.5
	if key=="glow":
		m.emission_enabled=true;m.emission=Color(1,.54,.15);m.emission_energy_multiplier=1.5
	material_cache[key] = m
	return m

func _configure_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		world_meshes += 1
		for i in range(node.mesh.get_surface_count()):
			var m: Material = node.mesh.surface_get_material(i)
			if m: node.set_surface_override_material(i,_material(m.resource_name))
		world_faces += node.mesh.get_faces().size()/3
		var label: String = node.name
		if label.contains("Ichiraku"):node.layers=3
		if label.begins_with("Village"):
			node.visibility_range_end = 720.0
			node.visibility_range_end_margin = 50.0
		if label.contains("ground") or label.contains("gardens"):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Use authored geometry only for the open, walkable landmark structures and terrain.
		var flexible_cloth:=label.contains("ichiraku_cloth") or label.contains("ichiraku_ink")
		if not flexible_cloth and (label.contains("Landmark") or label.contains("Main gate") or label.contains("defensive wall") or label.contains("Hokage Residence") or label.contains("weathered continuous") or label.contains("ground") or label.contains("gardens") or label.contains("Market lane")):
			var body := StaticBody3D.new()
			var collision := CollisionShape3D.new()
			collision.shape = node.mesh.create_trimesh_shape()
			body.add_child(collision)
			node.add_child(body)
	for child in node.get_children():
		_configure_meshes(child)

func _add_box(position_value: Vector3,size: Vector3,yaw: float=0.0,occlude: bool=false) -> void:
	var body := StaticBody3D.new()
	body.position=position_value;body.rotation.y=yaw
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size;collision.shape=shape;body.add_child(collision);add_child(body)
	if occlude:
		var occluder := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size=size*.96;occluder.occluder=box;body.add_child(occluder)

func _add_cylinder(position_value: Vector3,radius: float,height: float) -> void:
	var body := StaticBody3D.new()
	body.position=position_value
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius=radius;shape.height=height;collision.shape=shape;body.add_child(collision);add_child(body)

func _create_collisions() -> void:
	_add_box(Vector3(0,-.45,0),Vector3(12000,.90,12000))
	# Sidewalks and avenue share a smooth 18cm ground surface, avoiding per-paver physics.
	_add_box(Vector3(0,.08,55),Vector3(22,.20,610))
	for d: Dictionary in meta.districts.colliders:
		var pos:=Vector3(d.x,d.z,-d.y)
		if d.shape=="cylinder":
			_add_cylinder(pos,d.radius,d.height)
			var occluder := OccluderInstance3D.new()
			var box := BoxOccluder3D.new()
			box.size=Vector3(d.radius*1.32,d.height*.95,d.radius*1.32)
			occluder.occluder=box;occluder.position=pos;add_child(occluder)
		else:_add_box(pos,Vector3(d.width,d.height,d.depth),d.rotation_z,d.height>3)
	for plant: Dictionary in meta.districts.get("planting",[]):
		_add_cylinder(Vector3(plant.x,plant.z-.49+.2825,-plant.y),.39,.565)

func _tree_material(mat_name: String) -> Material:
	var kind := "leaves" if mat_name.contains("leaves") else ("branch" if mat_name.contains("branch") else "trunk")
	if tree_materials.has(kind): return tree_materials[kind]
	var base := "res://assets/vegetation/textures/tree_small_02_"
	var result: Material
	if kind=="leaves":
		var leaf:=ShaderMaterial.new()
		leaf.shader=load("res://scripts/canopy.gdshader")
		leaf.set_shader_parameter("leaf_color",load(base+"leaves_diff_1k.png"))
		leaf.set_shader_parameter("leaf_normal",load(base+"leaves_nor_gl_1k.png"))
		result=leaf
	else:
		var m:=StandardMaterial3D.new()
		m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.roughness=.9
		m.albedo_texture=load(base+("branch_diff_1k.png" if kind=="branch" else "diff_1k.jpg"))
		m.normal_enabled=true
		m.normal_texture=load(base+("branch_nor_gl_1k.png" if kind=="branch" else "nor_gl_1k.png"))
		result=m
	tree_materials[kind]=result
	return result

func _collect_tree_mesh(node: Node,transform_value: Transform3D,merged: ArrayMesh) -> void:
	var transform_next := transform_value
	if node is Node3D:transform_next=transform_value*node.transform
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.append_from(node.mesh,i,transform_next)
			surface.set_material(_tree_material(node.mesh.surface_get_material(i).resource_name))
			surface.commit(merged)
	for child in node.get_children():_collect_tree_mesh(child,transform_next,merged)

func _create_forest() -> void:
	trees = meta.landscape.forest_trees + meta.gardens.village_trees + meta.landmarks.trees + meta.districts.get("courtyard_trees",[])
	var lod_meshes: Array[ArrayMesh]=[]
	for filename: String in ["tree_v3_near.glb","tree_v3_mid.glb","tree_v3_far.glb","tree_v3_distant.glb","tree_v3_horizon.glb"]:
		var scene: Node3D=load("res://assets/vegetation/"+filename).instantiate()
		var merged:=ArrayMesh.new()
		_collect_tree_mesh(scene,Transform3D.IDENTITY,merged)
		scene.free()
		lod_meshes.append(merged)
	# Forward+ batches instances that share these meshes and materials while
	# retaining a separate culling bound for each real tree.
	for d: Dictionary in trees:
		var scale_value: float=d.height/4.5640373
		var tr:=Transform3D(Basis(Vector3.UP,d.rotation).scaled(Vector3.ONE*scale_value),Vector3(d.x,d.z,-d.y))
		if Vector2(d.x,d.y).length()<358:
			_add_cylinder(Vector3(d.x,d.z+d.collider_height/2.,-d.y),d.trunk_radius,d.collider_height)
		for lod in range(5):
			var instance:=MeshInstance3D.new()
			instance.mesh=lod_meshes[lod];instance.transform=tr
			instance.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
			instance.visibility_range_begin=[0.,32.,105.,220.,400.][lod]
			instance.visibility_range_end=[32.,105.,220.,400.,1300.][lod]
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
		var shadow:=MeshInstance3D.new()
		shadow.mesh=lod_meshes[2];shadow.transform=tr
		shadow.visibility_range_end=130
		shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadow.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(shadow)
	_create_street_plants(lod_meshes[2])

func _create_street_plants(plant_mesh: Mesh) -> void:
	var plants: Array=meta.districts.get("planting",[])
	plants+=meta.gardens.village_shrubs
	plants+=meta.districts.get("courtyard_shrubs",[])
	var cells: Dictionary={}
	for d: Dictionary in plants:
		var key:=Vector2i(floor(d.x/32.),floor(d.y/32.))
		if not cells.has(key):cells[key]=[]
		cells[key].append(d)
	for key: Vector2i in cells:
		var center:=Vector3(key.x*32+16,0,-key.y*32-16)
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=plant_mesh
		mm.instance_count=cells[key].size()
		for i in range(mm.instance_count):
			var d: Dictionary=cells[key][i]
			var height_value: float=float(d.get("height",1.2))
			var scale_value:=Vector3(height_value/4.0,height_value/4.5640373,height_value/4.0)
			mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,float(d.get("rotation",0.0))).scaled(scale_value),Vector3(d.x,float(d.get("z",.05)),-d.y)-center))
		var instance:=MultiMeshInstance3D.new();instance.multimesh=mm;instance.position=center
		instance.visibility_range_end=90
		add_child(instance)

func _create_groundcover() -> void:
	var grass_source: Node3D=load("res://assets/vegetation/grass.glb").instantiate()
	var meshes:=grass_source.find_children("*","MeshInstance3D",true,false)
	if meshes.is_empty(): grass_source.free();return
	var mesh: Mesh=meshes[0].mesh
	var mat:=StandardMaterial3D.new()
	mat.albedo_texture=load("res://assets/vegetation/grass_albedo_alpha.png")
	mat.normal_enabled=true
	mat.normal_texture=load("res://assets/vegetation/grass_normal.jpg")
	mat.albedo_color=Color(.72,.81,.56)
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold=.42
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.roughness=.95
	mat.backlight_enabled=true;mat.backlight=Color(.15,.21,.07)
	mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	grass_source.free()
	var rng:=RandomNumberGenerator.new();rng.seed=42389
	var cells: Dictionary={}
	for d: Dictionary in meta.gardens.village_shrubs:
		var key:=Vector2i(floor(d.x/40.),floor(d.y/40.))
		if not cells.has(key): cells[key]=[]
		for i in range(12):
			var angle:=rng.randf_range(0,TAU)
			var rad:=sqrt(rng.randf())*.75
			var pos:=Vector3(d.x+sin(angle)*rad,d.z+.03,-d.y+cos(angle)*rad)
			var scale_value:=rng.randf_range(.6,1.1)
			cells[key].append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*scale_value),pos))
	for key: Vector2i in cells:
		var center:=Vector3(key.x*40+20,0,-key.y*40-20)
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh
		mm.instance_count=cells[key].size()
		for i in range(mm.instance_count):
			var tr: Transform3D=cells[key][i];tr.origin-=center;mm.set_instance_transform(i,tr)
		var instance:=MultiMeshInstance3D.new();instance.multimesh=mm;instance.position=center
		instance.material_override=mat
		instance.visibility_range_end=90
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)

func set_quality(index: int) -> void:
	quality_index=index
	var viewport:=get_viewport()
	viewport.msaa_3d=Viewport.MSAA_2X if index==1 else Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_FXAA
	var pixels: float=viewport.get_visible_rect().size.x*viewport.get_visible_rect().size.y
	var cap: float=921600.0 if index==0 else 705600.0
	viewport.scaling_3d_scale=1.0 if index==1 else clampf(sqrt(cap/maxf(pixels,1.)),.5,1.)
	viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	environment.ssao_enabled=index!=2
	environment.ssil_enabled=index==1
	sun.directional_shadow_max_distance=180 if index==1 else (85 if index==0 else 65)

func visit_bookmark(index: int) -> void:
	var item: Array=BOOKMARKS[index]
	var direction: Vector3=item[2]-(item[1]+Vector3.UP*1.7)
	var yaw:=atan2(-direction.x,-direction.z)
	var pitch:=atan2(direction.y,Vector2(direction.x,direction.z).length())
	player.teleport_to(item[1],yaw,pitch)
	hud.update_location(item[0])

func _process(delta: float) -> void:
	if not is_instance_valid(player):return
	if player.position.y < -15:visit_bookmark(0)
	location_timer+=delta
	if location_timer>1:
		location_timer=0
		var name_text: String="Village streets"
		var nearest: float=80
		for item: Array in BOOKMARKS:
			var distance: float=player.position.distance_to(item[1])
			if distance<nearest:nearest=distance;name_text=item[0]
		hud.update_location(name_text)
	if bench:_benchmark_step(delta)

func _benchmark_step(_delta: float) -> void:
	var now_usec:=Time.get_ticks_usec()
	var frame_ms: float=(now_usec-bench_last_usec)/1000.0 if bench_last_usec>0 else 0.0
	bench_last_usec=now_usec
	hud.hide()
	bench_frame+=1
	# Keep the camera stationary for comparable GPU timing at six authored landmarks.
	player.velocity=Vector3.ZERO
	player.position=BOOKMARKS[bench_phase][1]
	if bench_frame>120:frame_samples.append(frame_ms)
	if bench_frame==90 and qa_out!="":
		_capture(qa_out+"/"+str(bench_phase)+".png")
	if bench_frame>=360:
		frame_samples.sort()
		var total:=0.0
		for sample: float in frame_samples:total+=sample
		var result: Dictionary={"location":BOOKMARKS[bench_phase][0],"mean_fps":1000.0/(total/frame_samples.size()),"p95_ms":frame_samples[int(frame_samples.size()*.95)],"p99_ms":frame_samples[int(frame_samples.size()*.99)],"max_ms":frame_samples[-1],"median_ms":frame_samples[frame_samples.size()/2],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		bench_results.append(result);print("BENCHMARK ",JSON.stringify(result))
		bench_phase+=1;bench_frame=0;frame_samples.clear()
		if bench_phase>=BOOKMARKS.size():
			if qa_out!="":
				var file:=FileAccess.open(qa_out+"/benchmark.json",FileAccess.WRITE)
				file.store_string(JSON.stringify({"timing":"monotonic wall clock between rendered process frames","locations":bench_results,"quality":quality_index,"viewport":str(get_viewport().get_visible_rect().size),"render_scale":get_viewport().scaling_3d_scale,"renderer":RenderingServer.get_current_rendering_method(),"load_ms":ready_ms},"\t"))
			get_tree().quit()
		else:visit_bookmark(bench_phase)

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
