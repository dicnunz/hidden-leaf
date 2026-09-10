extends SceneTree

## Sand-only CPU preparation, then editor bake in an isolated project:
## godot --headless --path . --script res://tools/bake_static_world.gd
## godot --headless --editor --path .build/static-bake --import
## godot --editor --path .build/static-bake
## The editor plugin writes assets/runtime/sand-lit.scn; root project.godot is untouched.
const World = preload("res://scripts/village_world.gd")
var meshes: Array = []
var started := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("_verify" if "--verify" in OS.get_cmdline_user_args() else "_prepare")

func _verify() -> void:
	var packed := load("res://assets/runtime/sand-lit.scn") as PackedScene
	if packed == null:_fail("Lit scene cannot load");return
	var world := packed.instantiate()
	root.add_child(world)
	var data: LightmapGIData = world.get_node("BakedLighting").light_data
	var sun: DirectionalLight3D = world.get_node("Sun")
	var textures: Array = []
	for texture: TextureLayered in data.get_lightmap_textures():
		textures.append({"width":texture.get_width(),"height":texture.get_height(),"layers":texture.get_layers()})
	var passed := data.get_user_count()==446 and not textures.is_empty() and sun.light_energy==0.0 and not sun.shadow_enabled
	for texture: Dictionary in textures:passed=passed and texture.width>0 and texture.height>0 and texture.layers>0
	var result := {"passed":passed,"users":data.get_user_count(),"textures":textures,"sun_energy":sun.light_energy,"sun_shadows":sun.shadow_enabled,"mode":"headless persisted scene and texture resource validation; visual gate remains separate"}
	var file := FileAccess.open("res://load-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("STATIC_WORLD_LOAD ",JSON.stringify(result))
	quit(0 if passed else 1)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _geometry_stats(mesh: ArrayMesh) -> Dictionary:
	var vertices := mesh.get_faces()
	var degenerate := 0
	var area := 0.0
	for i in range(0,vertices.size(),3):
		var value := (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()*.5
		area += value
		if value < .00000001:degenerate += 1
	return {"triangles":vertices.size()/3,"degenerate":degenerate,"area":area,"bounds":mesh.get_aabb()}

func _visit(node: Node, scene_root: Node) -> bool:
	for child in node.get_children():
		child.owner = scene_root
		if not _visit(child, scene_root): return false
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var original := instance.mesh as ArrayMesh
		if original == null:
			push_error("Non-ArrayMesh encountered: " + str(node.name));return false
		var label := str(node.name).to_lower()
		var coarse := "skyline" in label or "escarpment" in label or "ground" in label
		var texel := 1.0 if coarse else .18
		var copy := original.duplicate() as ArrayMesh
		var before := _geometry_stats(original)
		var triangles_before: int = before.triangles
		var began := Time.get_ticks_msec()
		var error := copy.lightmap_unwrap(instance.global_transform, texel)
		if error != OK:
			push_error("UV2 unwrap failed for " + str(node.name) + ": " + error_string(error));return false
		var after := _geometry_stats(copy)
		var triangles_after: int = after.triangles
		var removed: int = triangles_before-triangles_after
		if removed<0 or removed>int(before.degenerate) or absf(float(before.area)-float(after.area))>maxf(.0001,float(before.area)*.000001):
			push_error("UV2 unwrap changed nondegenerate geometry for " + str(node.name)+": "+JSON.stringify({"before":before,"after":after}));return false
		instance.mesh = copy
		instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		meshes.append({"name":node.name,"texel_m":texel,"triangles":triangles_after,"zero_area_triangles_removed":removed,"uv2_hint":str(copy.lightmap_size_hint),"unwrap_ms":Time.get_ticks_msec()-began})
		if meshes.size()%20 == 0:print("STATIC_UV2_PROGRESS ", meshes.size())
	return true

func _link(target: String, destination: String) -> bool:
	if DirAccess.dir_exists_absolute(destination): return true
	return OS.execute("/bin/ln", PackedStringArray(["-s",target,destination])) == 0

func _prepare() -> void:
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	var original_hash := FileAccess.get_sha256("res://project.godot")
	DirAccess.make_dir_recursive_absolute("res://assets/runtime")
	DirAccess.make_dir_recursive_absolute("res://.build/static-bake/addons")
	var world := World.new()
	world.name = "SandWorld"
	root.add_child(world)
	world.construct("sand")
	world.geometry.scene_file_path = ""
	if not _visit(world, world):
		_fail("Static world preparation stopped at mesh failure");return
	world.sun.light_bake_mode = Light3D.BAKE_STATIC
	var lightmap := LightmapGI.new()
	lightmap.name = "BakedLighting"
	lightmap.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lightmap.bounces = 2
	lightmap.use_denoiser = true
	lightmap.directional = true
	lightmap.max_texture_size = 4096
	lightmap.set_generate_probes(LightmapGI.GENERATE_PROBES_DISABLED)
	lightmap.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
	var data := LightmapGIData.new()
	var data_path := "res://assets/runtime/sand-lighting.lmbake"
	if ResourceSaver.save(data,data_path) != OK:
		_fail("Cannot save lightmap placeholder");return
	data.take_over_path(data_path)
	lightmap.light_data = data
	world.add_child(lightmap)
	lightmap.owner = world
	world.set_meta("static_bake", {"expected_meshes":meshes.size(),"sun_disabled_after_bake":true,"ssao_retained_pending_visual_gate":true})
	var scene := PackedScene.new()
	if scene.pack(world) != OK or ResourceSaver.save(scene,"res://assets/runtime/sand-prelight.scn") != OK:
		_fail("Cannot save prepared Sand scene");return
	var isolated := ProjectSettings.globalize_path("res://.build/static-bake")
	var root_path := ProjectSettings.globalize_path("res://")
	for folder: String in ["assets","scripts"]:
		if not _link(root_path.path_join(folder),isolated.path_join(folder)):
			_fail("Cannot link source resources into isolated project");return
	if not _link(root_path.path_join("addons/static_bake"),isolated.path_join("addons/static_bake")):
		_fail("Cannot link bake adapter");return
	var settings := project_text.replace('run/main_scene="res://main.tscn"','run/main_scene="res://assets/runtime/sand-prelight.scn"')
	settings += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/static_bake/plugin.cfg")\n'
	var config := FileAccess.open(isolated.path_join("project.godot"),FileAccess.WRITE)
	config.store_string(settings);config.close()
	if FileAccess.file_exists(isolated.path_join("bake-result.json")):DirAccess.remove_absolute(isolated.path_join("bake-result.json"))
	var report := {"meshes":meshes,"mesh_count":meshes.size(),"elapsed_ms":Time.get_ticks_msec()-started,"source_project_sha256":original_hash,"project_unchanged":original_hash==FileAccess.get_sha256("res://project.godot"),"quality":"medium","bounces":2,"denoiser":true,"directional":true,"scene":"res://assets/runtime/sand-prelight.scn"}
	var file := FileAccess.open(isolated.path_join("prepare.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("STATIC_WORLD_PREPARED ",JSON.stringify({"meshes":meshes.size(),"elapsed_ms":report.elapsed_ms,"project_unchanged":report.project_unchanged}))
	quit()
