@tool
extends EditorPlugin

## Only enabled by the isolated .build/static-bake project, never the live project.
func _enter_tree() -> void:
	call_deferred("_run")

func _button(node: Node) -> Button:
	if node is Button and node.text == "Bake Lightmaps":return node
	for child in node.get_children():
		var found := _button(child)
		if found:return found
	return null

func _finish(result: Dictionary) -> void:
	var file := FileAccess.open("res://bake-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("STATIC_WORLD_BAKE ",JSON.stringify(result))
	get_tree().quit(0 if result.get("passed",false) else 1)

func _run() -> void:
	# First run the documented headless --import pass; never bake within importer callbacks.
	if "--import" in OS.get_cmdline_args():return
	if FileAccess.file_exists("res://bake-result.json"):return
	for i in range(8):await get_tree().process_frame
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():await get_tree().process_frame
	EditorInterface.open_scene_from_path("res://assets/runtime/sand-prelight.scn")
	for i in range(8):await get_tree().process_frame
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null:
		_finish({"passed":false,"error":"Prepared scene not opened"});return
	var lightmap: LightmapGI = scene.get_node("BakedLighting")
	EditorInterface.edit_node(lightmap)
	for i in range(4):await get_tree().process_frame
	var button := _button(EditorInterface.get_base_control())
	if button == null or button.disabled:
		_finish({"passed":false,"error":"Built-in bake button unavailable"});return
	var verified := false
	for connection: Dictionary in button.get_signal_connection_list("pressed"):
		var callback: Callable = connection.callable
		if callback.get_method() == "_bake":verified=true
	if not verified:
		_finish({"passed":false,"error":"Unexpected editor callback"});return
	var started := Time.get_ticks_msec()
	print("STATIC_WORLD_BAKE_STARTED ",int(scene.get_meta("static_bake").expected_meshes))
	button.pressed.emit()
	var data := lightmap.light_data
	var expected: int = scene.get_meta("static_bake").expected_meshes
	if data == null or data.get_user_count()!=expected or data.get_lightmap_textures().is_empty():
		_finish({"passed":false,"error":"Bake did not produce expected mesh users/textures","elapsed_ms":Time.get_ticks_msec()-started,"expected_meshes":expected,"users":data.get_user_count() if data else 0});return
	var sun: DirectionalLight3D = scene.get_node("Sun")
	sun.light_energy=0.0
	sun.shadow_enabled=false
	# SSAO stays enabled until an actual image confirms baked occlusion.
	var packed := PackedScene.new()
	if packed.pack(scene)!=OK or ResourceSaver.save(packed,"res://assets/runtime/sand-lit.scn")!=OK:
		_finish({"passed":false,"error":"Cannot save lit scene"});return
	_finish({"passed":true,"users":data.get_user_count(),"textures":data.get_lightmap_textures().size(),"elapsed_ms":Time.get_ticks_msec()-started,"scene":"res://assets/runtime/sand-lit.scn","dynamic_sun":false,"ssao_retained":true,"button_callback_verified":verified})
