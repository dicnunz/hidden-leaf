extends CharacterBody3D
class_name LeafExplorerPlayer

## Coordinates: feet at the body origin; forward is local -Z.
signal pause_requested

const BODY_HEIGHT := 1.80
const BODY_RADIUS := 0.31
const EYE_HEIGHT := 1.70
const WALK_SPEED := 4.0
const RUN_SPEED := 9.0
const JUMP_SPEED := 6.0
const GRAVITY := 20.0
const MAX_STEP_HEIGHT := 0.35
const DEFAULT_SENSITIVITY := 0.0022

var camera: Camera3D
var enabled := false
var sensitivity := DEFAULT_SENSITIVITY
var _pitch := 0.0
var _view_yaw := 0.0
var _step_visual_offset := 0.0
var _step_visual_previous := 0.0
var _resume_holdoff := 0.0
var _qa_allowed := false
var _qa_override := false
var _qa_move := Vector2.ZERO
var _qa_sprint := false
var _qa_jump := false
var _bindings := ["move_left", "move_right", "move_forward", "move_backward", "jump", "sprint"]

func _ready() -> void:
	_qa_allowed = "--qa" in OS.get_cmdline_user_args()
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.38
	floor_stop_on_slope = true
	floor_constant_speed = true
	max_slides = 6
	safe_margin = 0.002
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var collider := CollisionShape3D.new()
	collider.name = "BodyCapsule"
	collider.shape = shape
	collider.position.y = BODY_HEIGHT * 0.5
	add_child(collider)
	camera = Camera3D.new()
	camera.name = "Eyes"
	# Keep render-rate mouse look outside the body's automatic interpolation.
	# A child with interpolation OFF still inherits interpolated parents unless
	# it is top-level, so both settings are intentional.
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 80.0
	camera.near = 0.06
	camera.far = 2400.0
	camera.current = true
	add_child(camera)
	_view_yaw = global_rotation.y
	# Prime Godot's interpolated transform tracking before the first render frame.
	get_global_transform_interpolated()
	camera.global_position = global_position + Vector3.UP * EYE_HEIGHT
	camera.global_rotation = Vector3(_pitch, _view_yaw, 0.0)
	_ensure_actions()
	Input.use_accumulated_input = false

func _ensure_actions() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP], "move_backward": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT]
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.1)
		for key: int in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _resume_holdoff > 0.0:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.screen_relative)
		get_viewport().set_input_as_handled()

func _apply_look(motion: Vector2) -> void:
	# Mouse deltas are already displacements. Never multiply them by frame time.
	_view_yaw = wrapf(_view_yaw - motion.x * sensitivity, -PI, PI)
	_pitch = clampf(_pitch - motion.y * sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
	if is_instance_valid(camera):
		camera.global_rotation = Vector3(_pitch, _view_yaw, 0.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree():
		set_paused(true)
		pause_requested.emit()

func set_paused(value: bool) -> void:
	enabled = not value
	_clear_input()
	velocity.x = 0.0
	velocity.z = 0.0
	_resume_holdoff = 0.12 if not value else 0.0
	# Called by the explicit start/resume button. Focus-in never captures the cursor.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _clear_input() -> void:
	for action: String in _bindings:
		if InputMap.has_action(action):
			Input.action_release(action)
	_qa_move = Vector2.ZERO
	_qa_sprint = false
	_qa_jump = false
	_qa_override = false

func teleport_to(destination: Vector3, yaw: float = 0.0, pitch: float = 0.0) -> void:
	global_position = destination
	_view_yaw = wrapf(yaw, -PI, PI)
	global_rotation = Vector3(0.0, _view_yaw, 0.0)
	_pitch = clampf(pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
	velocity = Vector3.ZERO
	_step_visual_offset = 0.0
	_step_visual_previous = 0.0
	_clear_input()
	reset_physics_interpolation()
	if is_instance_valid(camera):
		camera.global_position = destination + Vector3.UP * EYE_HEIGHT
		camera.global_rotation = Vector3(_pitch, _view_yaw, 0.0)
		camera.reset_physics_interpolation()

func _process(_delta: float) -> void:
	var visual_step := _step_visual_offset
	if get_tree().physics_interpolation:
		visual_step = lerpf(_step_visual_previous, _step_visual_offset, Engine.get_physics_interpolation_fraction())
	camera.global_position = get_global_transform_interpolated().origin + Vector3.UP * (EYE_HEIGHT + visual_step)
	camera.global_rotation = Vector3(_pitch, _view_yaw, 0.0)

func _physics_process(delta: float) -> void:
	# Apply pending movement direction only on physics ticks. The camera has
	# already responded to the mouse independently, on the input/render side.
	global_rotation = Vector3(0.0, _view_yaw, 0.0)
	_step_visual_previous = _step_visual_offset
	_resume_holdoff = maxf(0.0, _resume_holdoff - delta)
	var accepting_input := enabled and _resume_holdoff <= 0.0 and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (_qa_allowed and _qa_override))
	var movement := Vector2.ZERO
	var sprinting := false
	var jumping := false
	if accepting_input:
		if _qa_allowed and _qa_override:
			movement = _qa_move.limit_length(1.0)
			sprinting = _qa_sprint
			jumping = _qa_jump
			_qa_jump = false
		else:
			movement = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
			sprinting = Input.is_action_pressed("sprint")
			jumping = Input.is_action_just_pressed("jump")
	var direction := global_basis * Vector3(movement.x, 0.0, movement.y)
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var desired := direction * (RUN_SPEED if sprinting else WALK_SPEED)
	var grounded := is_on_floor()
	var acceleration := 27.0 if grounded else 9.0
	if movement.is_zero_approx():
		acceleration = 34.0 if grounded else 4.0
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(desired.x, desired.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if grounded and velocity.y < 0.0:
		velocity.y = -0.10
	else:
		velocity.y -= GRAVITY * delta
	if jumping and grounded:
		velocity.y = JUMP_SPEED
	# Step up only from a grounded, non-jumping state. Collision casts check headroom,
	# forward clearance and an actual walkable landing, so walls cannot be climbed.
	if grounded and velocity.y <= 0.0 and horizontal.length_squared() > 0.001:
		_try_step(Vector3(velocity.x, 0.0, velocity.z) * delta)
	move_and_slide()
	_step_visual_offset = lerpf(_step_visual_offset, 0.0, 1.0 - exp(-18.0 * delta))
	if absf(_step_visual_offset) < 0.0001:
		_step_visual_offset = 0.0

func _try_step(horizontal_motion: Vector3) -> bool:
	var blocking := KinematicCollision3D.new()
	if not test_move(global_transform, horizontal_motion, blocking):
		return false
	if blocking.get_normal().y > cos(floor_max_angle):
		return false
	var raised := global_transform
	var lift := Vector3.UP * (MAX_STEP_HEIGHT + 0.015)
	if test_move(raised, lift):
		return false
	raised.origin += lift
	# Probe far enough for the capsule center to reach the tread. A single-frame
	# displacement would hit the rounded capsule edge and misclassify it as a wall.
	var forward_probe := horizontal_motion.normalized() * maxf(horizontal_motion.length(), BODY_RADIUS + 0.08)
	if test_move(raised, forward_probe):
		return false
	raised.origin += forward_probe
	var landing := KinematicCollision3D.new()
	if not test_move(raised, Vector3.DOWN * (MAX_STEP_HEIGHT + 0.075), landing):
		return false
	if landing.get_normal().y < cos(floor_max_angle):
		return false
	var rise := (raised.origin + landing.get_travel()).y - global_position.y
	if rise <= 0.015 or rise > MAX_STEP_HEIGHT + 0.008:
		return false
	global_position.y += rise + 0.002
	_step_visual_offset = maxf(-MAX_STEP_HEIGHT, _step_visual_offset - rise)
	return true

## Deliberate test interface. No injection takes effect without the explicit --qa flag.
func qa_set_input(movement: Vector2, sprinting: bool = false, jump_once: bool = false) -> bool:
	if not _qa_allowed:
		return false
	_qa_override = true
	_qa_move = movement
	_qa_sprint = sprinting
	_qa_jump = _qa_jump or jump_once
	return true

func qa_apply_look(displacement: Vector2) -> bool:
	if not _qa_allowed:
		return false
	_apply_look(displacement)
	return true

func qa_clear_input() -> bool:
	if not _qa_allowed:
		return false
	_qa_override = false
	_qa_move = Vector2.ZERO
	_qa_sprint = false
	_qa_jump = false
	return true
