extends Node

## Owns one instantiated village. Registry maps village IDs to PackedScene paths.
## request_village() returns false and emits failed for invalid/busy requests.
## Busy requests never replace the accepted request. Connect switched to place
## the persistent player; keep that player outside this node.
## release_village() frees the active tree immediately (only while idle).
## Threaded loads cannot be cancelled; keep this node alive until is_loading()
## becomes false. No PackedScene references are retained after instantiation.
signal loading(id: String, progress: float)
signal switched(id: String, root: Node)
signal failed(id: String, message: String)

var registry: Dictionary = {}
var current_id := ""
var current_root: Node
var _pending_id := ""
var _pending_path := ""

func _ready() -> void:
	set_process(not _pending_id.is_empty())

func is_loading() -> bool:
	return not _pending_id.is_empty()

func request_village(id: String) -> bool:
	if is_loading():
		failed.emit(id, "A village is already loading; request ignored.")
		return false
	if id.is_empty() or not registry.has(id) or not registry[id] is String or str(registry[id]).is_empty():
		failed.emit(id, "Unknown village ID or invalid scene path.")
		return false
	var path: String = registry[id]
	var error := ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_IGNORE)
	if error != OK:
		failed.emit(id, "Could not start scene load: " + error_string(error))
		return false
	_pending_id = id
	_pending_path = path
	set_process(true)
	loading.emit(id, 0.0)
	return true

func _process(_delta: float) -> void:
	if not is_loading():
		set_process(false)
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_pending_path, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		loading.emit(_pending_id, float(progress[0]) if not progress.is_empty() else 0.0)
		return
	var id := _pending_id
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		# Drain failed requests too, releasing the loader's task bookkeeping.
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(_pending_path)
		_finish_request()
		failed.emit(id, "Scene load failed; current village preserved.")
		return
	var scene := ResourceLoader.load_threaded_get(_pending_path) as PackedScene
	if scene == null or not scene.can_instantiate():
		_finish_request()
		failed.emit(id, "Resource is not an instantiable PackedScene; current village preserved.")
		return
	loading.emit(id, 1.0)
	# Immediate free prevents a frame with two worlds and their physics bodies.
	_free_current()
	current_root = scene.instantiate()
	scene = null
	if current_root == null:
		_finish_request()
		failed.emit(id, "Scene instantiation failed.")
		return
	current_id = id
	add_child(current_root)
	_finish_request()
	switched.emit(id, current_root)

func _finish_request() -> void:
	_pending_id = ""
	_pending_path = ""
	set_process(false)

func _free_current() -> void:
	if is_instance_valid(current_root):
		remove_child(current_root)
		current_root.free()
	current_root = null
	current_id = ""

func release_village() -> bool:
	if is_loading():
		return false
	_free_current()
	return true
