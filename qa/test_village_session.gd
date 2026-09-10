extends SceneTree

## Headless loader lifecycle test; creates and removes tiny user:// fixtures.
## godot --headless --path . --script res://qa/test_village_session.gd
const Session = preload("res://scripts/village_session.gd")
var failures := 0
var transitions: Array[String] = []
var errors: Array[String] = []
var fixture_dir := ""
var session: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _fixture(label: String) -> String:
	var node := Node3D.new()
	node.name = label
	var scene := PackedScene.new()
	_check(scene.pack(node) == OK, "Pack fixture " + label)
	node.free()
	var path := fixture_dir.path_join(label + ".tscn")
	_check(ResourceSaver.save(scene, path) == OK, "Save fixture " + label)
	return path

func _wait_idle() -> void:
	var started := Time.get_ticks_msec()
	while session.is_loading() and Time.get_ticks_msec() - started < 10000:
		await process_frame
		_check(session.get_child_count() <= 1, "At most one root during loading")
	_check(not session.is_loading(), "Threaded load completed before timeout")

func _run() -> void:
	fixture_dir = "user://village-session-" + str(Time.get_ticks_usec())
	_check(DirAccess.make_dir_recursive_absolute(fixture_dir) == OK, "Create fixture directory")
	var a := _fixture("A")
	var b := _fixture("B")
	session = Session.new()
	session.registry = {"a": a, "b": b, "broken": fixture_dir.path_join("missing.tscn")}
	root.add_child(session)
	session.switched.connect(func(id: String, village: Node):
		transitions.append(id)
		_check(session.get_child_count() == 1 and village == session.current_root, "One root when switched"))
	session.failed.connect(func(id: String, _message: String): errors.append(id))
	_check(not session.request_village("unknown"), "Reject unknown ID")
	_check(session.request_village("a"), "Accept A")
	_check(not session.request_village("b"), "Ignore overlapping B")
	_check(not session.release_village(), "Reject release while loading")
	await _wait_idle()
	_check(session.current_id == "a", "Accepted request wins overlap")
	var previous: Node = session.current_root
	_check(session.request_village("b"), "Accept B")
	await _wait_idle()
	_check(not is_instance_valid(previous), "A root immediately freed")
	_check(session.current_id == "b", "B active")
	_check(session.request_village("a"), "Accept A again")
	await _wait_idle()
	_check(transitions == ["a", "b", "a"], "A to B to A transitions")
	previous = session.current_root
	# Missing-resource engine diagnostics are expected in this negative test.
	session.request_village("broken")
	await _wait_idle()
	_check(session.current_root == previous and is_instance_valid(previous), "Failed load preserves root")
	_check(session.current_id == "a", "Failed load preserves ID")
	_check(errors.has("unknown") and errors.has("b") and errors.has("broken"), "Failure signals identify rejected requests")
	_check(session.release_village(), "Release idle village")
	_check(session.get_child_count() == 0 and not is_instance_valid(previous), "Release frees root")
	_check(session.current_id.is_empty(), "Release clears ID")
	session.free()
	DirAccess.remove_absolute(a)
	DirAccess.remove_absolute(b)
	DirAccess.remove_absolute(fixture_dir)
	print("VILLAGE_SESSION_TEST ", JSON.stringify({"failures": failures, "transitions": transitions}))
	quit(0 if failures == 0 else 1)
