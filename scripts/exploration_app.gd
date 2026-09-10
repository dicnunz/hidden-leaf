extends Node3D
class_name ExplorationApp

const PlayerScript = preload("res://scripts/player.gd")
const MenuScript = preload("res://scripts/exploration_menu.gd")
const SessionScript = preload("res://scripts/village_session.gd")

const REGISTRY := {
	"leaf": "res://assets/runtime/leaf.scn",
	"sand": "res://assets/runtime/sand.scn",
	"mist": "res://assets/runtime/mist.scn",
	"cloud": "res://assets/runtime/cloud.scn",
	"stone": "res://assets/runtime/stone.scn"
}

var player: LeafExplorerPlayer
var menu: CanvasLayer
var session: Node
var current_world: Node
var current_id := ""
var current_bookmarks: Array = []
var environment: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	_configure_display()
	session = SessionScript.new()
	session.name = "VillageSession"
	session.registry = REGISTRY.duplicate()
	add_child(session)
	session.loading.connect(_on_loading)
	session.switched.connect(_on_switched)
	session.failed.connect(_on_failed)

	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.camera.far = 2400.0
	player.pause_requested.connect(func(): _set_paused(true))
	player.set_paused(true)

	menu = MenuScript.new()
	menu.name = "ExplorationMenu"
	add_child(menu)
	menu.pause_requested.connect(_set_paused)
	menu.village_requested.connect(_request_village)
	menu.bookmark_requested.connect(_visit_bookmark)
	menu.sensitivity_changed.connect(_set_sensitivity)
	menu.fullscreen_changed.connect(_set_fullscreen)
	menu.set_paused(true)
	_request_village("leaf")

func _configure_display() -> void:
	var viewport := get_viewport()
	viewport.use_taa = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_scale = 1.0
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Village Explorer")
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(Vector2i(1600, 900))

func _request_village(id: String) -> void:
	if session.is_loading():
		# The session owns the accepted request. A second click cannot replace it.
		return
	if id == current_id and is_instance_valid(current_world):
		menu.set_error("This village is already open.")
		return
	_set_paused(true)
	var scene_path := str(REGISTRY.get(id, ""))
	if scene_path.is_empty():
		menu.set_error("Unknown village: " + id)
		return
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		menu.set_error("%s has not been built yet. The current village is unchanged." % id.capitalize())
		print("EXPLORATION_LOAD_FAILED ", JSON.stringify({"id": id, "message": "runtime scene missing", "preserved": is_instance_valid(current_world)}))
		return
	if not session.request_village(id) and not session.is_loading():
		player.set_paused(true)

func _on_loading(id: String, progress: float) -> void:
	menu.set_loading(id, progress)

func _on_failed(id: String, message: String) -> void:
	# Busy rejections leave the accepted load and its disabled menu intact.
	if session.is_loading():
		return
	menu.set_error("%s: %s" % [id.capitalize(), message])
	player.set_paused(true)
	print("EXPLORATION_LOAD_FAILED ", JSON.stringify({"id": id, "message": message, "preserved": is_instance_valid(current_world)}))

func _on_switched(id: String, world_root: Node) -> void:
	current_id = id
	current_world = world_root
	var village_meta: Dictionary = world_root.get_meta("village", {})
	current_bookmarks = village_meta.get("bookmarks", [])
	_refresh_world_references(world_root)
	_apply_world_graphics()
	menu.set_current_village(id, str(village_meta.get("name", id.capitalize())))
	menu.set_bookmarks(current_bookmarks)
	if current_bookmarks.is_empty():
		menu.set_error("This runtime scene has no spawn bookmark.")
		player.set_paused(true)
		return
	_visit_bookmark(0)
	_set_paused(true)
	print("EXPLORATION_SWITCHED ", JSON.stringify({"id": id, "bookmarks": current_bookmarks.size(), "resident_worlds": session.get_child_count()}))
	if "--qa-exit-after-load" in OS.get_cmdline_user_args():
		get_tree().quit(0)

func _refresh_world_references(world_root: Node) -> void:
	environment = null
	sun = null
	var environments := world_root.find_children("*", "WorldEnvironment", true, false)
	if not environments.is_empty():
		environment = (environments[0] as WorldEnvironment).environment
	var directional_lights := world_root.find_children("*", "DirectionalLight3D", true, false)
	if not directional_lights.is_empty():
		sun = directional_lights[0] as DirectionalLight3D

func _apply_world_graphics() -> void:
	var viewport := get_viewport()
	viewport.use_taa = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_scale = 1.0
	if is_instance_valid(sun):
		sun.shadow_enabled = true
		sun.shadow_bias = 0.2
		sun.shadow_normal_bias = 1.5

func _visit_bookmark(index: int) -> void:
	if index < 0 or index >= current_bookmarks.size():
		return
	var bookmark: Dictionary = current_bookmarks[index]
	var position_value := _vector(bookmark.get("position", [0.0, 0.2, 0.0]))
	var target := _vector(bookmark.get("target", [0.0, 1.7, -1.0]))
	var direction := target - (position_value + Vector3.UP * LeafExplorerPlayer.EYE_HEIGHT)
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.teleport_to(position_value, yaw, pitch)
	menu.set_location(str(bookmark.get("name", "Village streets")))

func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _set_paused(value: bool) -> void:
	if not value and not is_instance_valid(current_world):
		menu.set_error("No village is ready to explore.")
		value = true
	player.set_paused(value)
	menu.set_paused(value)
	if not value:
		menu.reveal_hint()

func _set_sensitivity(multiplier: float) -> void:
	player.sensitivity = LeafExplorerPlayer.DEFAULT_SENSITIVITY * multiplier

func _set_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	if not enabled:
		DisplayServer.window_set_size(Vector2i(1600, 900))

func _process(_delta: float) -> void:
	if is_instance_valid(current_world) and player.position.y < -15.0 and not current_bookmarks.is_empty():
		_visit_bookmark(0)
