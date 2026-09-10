extends SceneTree

const LeafWorldScript = preload("res://scripts/leaf_world.gd")
const VillageWorldScript = preload("res://scripts/village_world.gd")

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var village_id := _argument("--village=")
	if village_id.is_empty():
		_fail("Usage: godot --headless --path . --script tools/bake_runtime.gd -- --village=leaf")
		return
	if not village_id.is_valid_filename() or village_id.contains("/") or village_id.contains("\\"):
		_fail("Invalid village ID: " + village_id)
		return
	var world: Node3D
	if village_id == "leaf":
		if not FileAccess.file_exists("res://assets/villages/leaf.glb") or not FileAccess.file_exists("res://assets/village_v3.json"):
			_fail("Leaf source geometry or metadata is missing.")
			return
		world = LeafWorldScript.new()
		world.name = "LeafWorld"
		world.construct()
	else:
		var geometry_path := "res://assets/villages/%s.glb" % village_id
		var metadata_path := "res://assets/villages/%s.json" % village_id
		if not FileAccess.file_exists(geometry_path) or not FileAccess.file_exists(metadata_path):
			_fail("Generated village source is incomplete: " + village_id)
			return
		world = VillageWorldScript.new()
		world.name = "%sWorld" % village_id.capitalize()
		world.construct(village_id)
	if world.get_meta("village", {}).is_empty():
		world.free()
		_fail("World construction produced no runtime metadata.")
		return
	var expected := _snapshot(world)
	_clear_scene_paths(world)
	_assign_owners(world, world)
	var runtime_dir := ProjectSettings.globalize_path("res://assets/runtime")
	var directory_error := DirAccess.make_dir_recursive_absolute(runtime_dir)
	if directory_error != OK:
		world.free()
		_fail("Could not create runtime directory: " + error_string(directory_error))
		return
	var packed := PackedScene.new()
	var pack_error := packed.pack(world)
	if pack_error != OK:
		world.free()
		_fail("Could not pack runtime scene: " + error_string(pack_error))
		return
	var output_path := "res://assets/runtime/%s.scn" % village_id
	var save_error := ResourceSaver.save(packed, output_path)
	if save_error != OK:
		world.free()
		_fail("Could not save runtime scene: " + error_string(save_error))
		return
	world.free()
	world = null
	packed = null
	await process_frame
	var loaded := ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if loaded == null or not loaded.can_instantiate():
		_fail("Saved runtime scene cannot be reloaded.")
		return
	var restored := loaded.instantiate()
	loaded = null
	var actual := _snapshot(restored)
	var village_meta: Dictionary = restored.get_meta("village", {})
	var invalid_contents := (
		not restored.find_children("*", "CharacterBody3D", true, false).is_empty()
		or not restored.find_children("*", "CanvasLayer", true, false).is_empty()
	)
	if expected != actual or village_meta.get("id", "") != village_id or invalid_contents:
		restored.free()
		_fail("Reload validation failed: expected=%s actual=%s metadata_id=%s invalid_contents=%s" % [expected, actual, village_meta.get("id", ""), invalid_contents])
		return
	var file := FileAccess.open(output_path, FileAccess.READ)
	var file_bytes := file.get_length() if file else -1
	if file: file.close()
	print("RUNTIME_BAKED ", JSON.stringify({
		"id": village_id,
		"path": output_path,
		"bytes": file_bytes,
		"bookmarks": (village_meta.get("bookmarks", []) as Array).size(),
		"validated": actual
	}))
	restored.free()
	restored = null
	await process_frame
	quit(0)

func _assign_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_assign_owners(child, scene_root)

func _clear_scene_paths(node: Node) -> void:
	if not node.scene_file_path.is_empty():
		node.scene_file_path = ""
	for child in node.get_children():
		_clear_scene_paths(child)

func _snapshot(root: Node) -> Dictionary:
	return {
		"descendants": root.find_children("*", "", true, false).size(),
		"meshes": root.find_children("*", "MeshInstance3D", true, false).size(),
		"multimeshes": root.find_children("*", "MultiMeshInstance3D", true, false).size(),
		"collisions": root.find_children("*", "CollisionShape3D", true, false).size()
	}

func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).strip_edges().to_lower()
	return ""

func _fail(message: String) -> void:
	push_error(message)
	print("RUNTIME_BAKE_FAILED ", message)
	quit(1)
