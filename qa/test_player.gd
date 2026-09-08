extends SceneTree

## Run with: godot --headless --path <project> --script res://qa/test_player.gd --fixed-fps 60 -- --qa
## Tests traverse physics fixtures using the gated controller input, with teleports only
## to independent fixture starting points. All movement/collision/jump assertions use physics.
var player: CharacterBody3D
var world: Node3D
var failures: Array[String] = []
var checks := 0

class RenderProbe extends Node:
	var target: CharacterBody3D
	var samples: Array[Dictionary] = []
	func _ready() -> void:
		process_priority = 1000
	func _process(delta: float) -> void:
		# Run after the player's render callback, observing actual camera transforms.
		samples.append({"camera": target.camera.global_position, "body": target.global_position,
			"expected": target.get_global_transform_interpolated().origin + Vector3.UP * 1.70,
			"tick": Engine.get_physics_frames(), "delta": delta})

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures.append(message)
		printerr("FAIL ", message)

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)

func _reset(position: Vector3) -> void:
	player.teleport_to(position)
	player.enabled = true
	await _frames(15)

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args():
		printerr("The physics suite requires the explicit --qa argument.")
		quit(2)
		return
	physics_interpolation = true
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(0,-.5,0),Vector3(240,1,240))
	_box(Vector3(0,1.5,-8),Vector3(8,3,.5))
	for i in range(3):
		var height := .30 * (i+1)
		_box(Vector3(12,height/2.0,-4.0-i*2.0),Vector3(4,height,2))
	_box(Vector3(24,.30,-4),Vector3(4,.60,2))
	# Low ceiling prevents stepping into an overhead obstacle in this separate lane.
	_box(Vector3(36,.15,-4),Vector3(4,.30,2))
	_box(Vector3(36,2.11,-3.8),Vector3(4,.40,3.6))
	player = load("res://scripts/player.gd").new()
	world.add_child(player)
	await _reset(Vector3(-32,.25,12))
	_check(player.camera != null and is_equal_approx(player.camera.fov,80.0),"Camera is created with 80 degree FOV")
	_check(player.is_on_floor(),"Capsule settles onto the ground")
	_check(absf(player.global_position.y) < .015,"Body origin remains at feet level")
	_check(player.qa_set_input(Vector2(0,-1)),"Explicit --qa enables deliberate input injection")
	await _frames(1)
	_check(absf(player.velocity.z) > .05 and absf(player.velocity.z) < 1.0,"Walking accelerates smoothly from rest")
	await _frames(119)
	var walking_distance: float = 12.0-player.global_position.z
	_check(walking_distance > 7.25 and walking_distance < 8.35,"Two seconds walking travels about 7.7m (%.3f)" % walking_distance)
	player.qa_set_input(Vector2.ZERO)
	await _frames(15)
	_check(Vector2(player.velocity.x,player.velocity.z).length() < .01,"Release decelerates fully without sliding")
	await _reset(Vector3(-32,.25,12))
	player.qa_set_input(Vector2(0,-1),true)
	await _frames(120)
	var running_distance: float = 12.0-player.global_position.z
	_check(running_distance > 16.1 and running_distance < 18.35,"Two seconds sprinting respects 9m/s speed (%.3f)" % running_distance)
	await _reset(Vector3(-32,.25,12))
	player.qa_set_input(Vector2(1,-1))
	await _frames(120)
	var diagonal_distance: float = Vector2(player.global_position.x+32,player.global_position.z-12).length()
	_check(absf(diagonal_distance-walking_distance)<.13,"Diagonal movement has the same speed as straight movement")
	await _reset(Vector3(0,.25,0))
	player.qa_set_input(Vector2(0,-1),true)
	await _frames(150)
	_check(player.global_position.z > -7.60 and player.global_position.z < -7.15,"Sprinting stops at a solid wall (z %.3f)" % player.global_position.z)
	_check(absf(player.global_position.y)<.04,"Wall contact does not climb or lift the capsule")
	await _reset(Vector3(-16,.25,0))
	player.qa_set_input(Vector2.ZERO,false,true)
	var peak := 0.0
	for i in range(75):
		await _frames(1)
		peak = maxf(peak,player.global_position.y)
	_check(peak > .65 and peak < 1.15,"Jump produces a physical arc under gravity (peak %.3fm)" % peak)
	_check(player.is_on_floor() and absf(player.global_position.y)<.02,"Jump lands back on the floor")
	await _reset(Vector3(12,.25,0))
	player.qa_set_input(Vector2(0,-1))
	var stair_peak := 0.0
	var previous_y: float = player.global_position.y
	var largest_step := 0.0
	for i in range(160):
		await _frames(1)
		stair_peak = maxf(stair_peak,player.global_position.y)
		largest_step = maxf(largest_step,player.global_position.y-previous_y)
		previous_y = player.global_position.y
	_check(stair_peak > .86 and player.global_position.z < -9.3,"Walks up three 0.30m steps and across the stair fixture (peak %.3f, z %.3f)" % [stair_peak,player.global_position.z])
	_check(largest_step <= .361,"Stepping never exceeds the configured 0.35m rise (%.3f)" % largest_step)
	await _reset(Vector3(24,.25,0))
	player.qa_set_input(Vector2(0,-1))
	await _frames(120)
	_check(player.global_position.z > -2.95 and player.global_position.y < .10,"A 0.60m obstacle cannot be auto-stepped")
	await _reset(Vector3(36,.25,0))
	player.qa_set_input(Vector2(0,-1))
	await _frames(120)
	_check(player.global_position.z > -2.9 and player.global_position.y < .10,"Step cast respects low ceiling clearance")
	await _reset(Vector3(-32,.25,12))
	player.qa_set_input(Vector2(0,-1))
	await _frames(20)
	player.set_paused(true)
	var pause_position: Vector3 = player.global_position
	player.qa_set_input(Vector2(0,-1),true,true)
	await _frames(30)
	_check(player.global_position.distance_to(pause_position) < .015,"Paused controller ignores movement and jump injection")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED,"Pausing releases the mouse")
	player.set_paused(false)
	await _frames(30)
	_check(player.global_position.distance_to(pause_position) < .015,"Resume clears held input without moving unexpectedly")
	player.qa_set_input(Vector2(0,-1))
	await _frames(30)
	_check(player.global_position.z < pause_position.z-1,"Fresh input works after resuming")
	player.teleport_to(Vector3(-32,.25,12))
	player.qa_apply_look(Vector2(100,50))
	var look_one := Vector2(player.camera.global_rotation.y,player.camera.global_rotation.x)
	player.teleport_to(Vector3(-32,.25,12))
	for i in range(100): player.qa_apply_look(Vector2(1,.5))
	var look_many := Vector2(player.camera.global_rotation.y,player.camera.global_rotation.x)
	_check(look_one.distance_to(look_many)<.00002,"Mouse response is independent of event batching and frame time")
	player.qa_apply_look(Vector2(0,999999))
	_check(absf(player.camera.global_rotation.x)<=deg_to_rad(85.01),"Vertical look clamps safely at 85 degrees")
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not player.enabled and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED,"Focus loss pauses and releases the cursor without recapture")
	# Exercise saved preferences in an isolated file, leaving the user's config alone.
	var preference_path := "user://qa-explorer-%d.cfg" % Time.get_ticks_usec()
	var preferences := ConfigFile.new()
	preferences.set_value("display", "quality", 2)
	preferences.set_value("display", "fullscreen", false)
	preferences.set_value("controls", "sensitivity", 1.45)
	preferences.save(preference_path)
	# Instantiate the actual HUD as a parse/runtime contract check.
	var hud: CanvasLayer = load("res://scripts/explorer_hud.gd").new()
	hud.set("_preferences_path", preference_path)
	root.add_child(hud)
	hud.setup(player)
	var applied_quality: Array[int] = [0]
	hud.quality_changed.connect(func(index: int): applied_quality[0] = index)
	hud.update_location("Ichiraku")
	await _frames(2)
	_check(hud.paused and not player.enabled,"HUD starts with deliberate user-controlled entry")
	var reticle: Control = hud.get_node("ExplorerInterface/Reticle")
	var summary: Control = hud.get_node("ExplorerInterface/LocationSummary")
	var viewport_size := root.get_visible_rect().size
	_check(reticle.get_global_rect().get_center().distance_to(viewport_size * .5) < 1.0,"Reticle is exactly centered in the viewport")
	_check(summary.global_position.y > viewport_size.y - 110.0 and summary.global_position.y < viewport_size.y - 40.0,"Location label is anchored inside the lower-left viewport")
	hud.set_paused(false)
	await _frames(2)
	_check(not hud.paused and player.enabled,"HUD Resume enables the controller")
	hud.set_paused(true)
	_check(applied_quality[0] == 2 and is_equal_approx(player.sensitivity, .0022 * 1.45), "Saved quality applies after setup and restores player sensitivity")
	var sensitivity_widget: HSlider = hud.find_child("LookSensitivity", true, false)
	var quality_widget: OptionButton = hud.find_child("GraphicsQuality", true, false)
	var fullscreen_widget: CheckBox = hud.find_child("Fullscreen", true, false)
	_check(is_equal_approx(sensitivity_widget.value, 1.45) and quality_widget.selected == 2 and not fullscreen_widget.button_pressed, "Startup widgets match all saved preferences")
	# Drive the actual widgets, then inspect the on-disk config they saved.
	sensitivity_widget.value = 1.65
	quality_widget.select(1)
	quality_widget.item_selected.emit(1)
	fullscreen_widget.button_pressed = true
	var saved := ConfigFile.new()
	var saved_ok := saved.load(preference_path) == OK
	_check(saved_ok and saved.get_value("display", "quality") == 1 and saved.get_value("display", "fullscreen") == true and is_equal_approx(float(saved.get_value("controls", "sensitivity")), 1.65), "Widget changes persist graphics, sensitivity and fullscreen to disk")
	hud.queue_free()
	await _frames(2)
	var restored: CanvasLayer = load("res://scripts/explorer_hud.gd").new()
	restored.set("_preferences_path", preference_path)
	root.add_child(restored)
	restored.setup(player)
	var restored_quality: Array[int] = [0]
	restored.quality_changed.connect(func(index: int): restored_quality[0] = index)
	await _frames(2)
	var restored_slider: HSlider = restored.find_child("LookSensitivity", true, false)
	var restored_fullscreen: CheckBox = restored.find_child("Fullscreen", true, false)
	_check(restored_quality[0] == 1 and is_equal_approx(restored_slider.value, 1.65) and restored_fullscreen.button_pressed and restored.paused, "A fresh HUD restores preferences and preserves deliberate entry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preference_path))
	await _test_camera_interpolation()
	print("PLAYER_QA_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_camera_interpolation() -> void:
	_check(player.camera.top_level and player.camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Camera is world-space with automatic interpolation disabled")
	var destination := Vector3(-48, 3.25, 12)
	player.teleport_to(destination, .70, -.25)
	var expected_eye := destination + Vector3.UP * 1.70
	var expected_rotation := Basis.from_euler(Vector3(-.25, .70, 0.0))
	_check(player.camera.global_position.distance_to(expected_eye) < .00001 and player.camera.global_basis.is_equal_approx(expected_rotation), "Teleport immediately updates world-space eye position and full view orientation")
	var physics_tick := Engine.get_physics_frames()
	var body_rotation := player.global_rotation
	player.qa_apply_look(Vector2(120,-35))
	var expected_yaw: float = .70 - 120.0 * player.sensitivity
	var expected_pitch: float = -.25 + 35.0 * player.sensitivity
	var expected_look := Basis.from_euler(Vector3(expected_pitch, expected_yaw, 0.0))
	_check(Engine.get_physics_frames() == physics_tick and player.global_rotation.is_equal_approx(body_rotation) and player.camera.global_basis.is_equal_approx(expected_look), "Mouse look reaches the camera immediately without rotating the physics body between ticks")
	await _frames(1)
	_check(absf(angle_difference(player.global_rotation.y, expected_yaw)) < .00001, "Pending body yaw is applied on the next physics tick")
	var original_physics_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 10
	await _reset(Vector3(-48,.25,12))
	player.qa_set_input(Vector2(0,-1))
	await _frames(8)
	var probe := RenderProbe.new()
	probe.target = player
	root.add_child(probe)
	for i in range(240):
		await process_frame
	var samples := probe.samples
	var between_tick_motion := 0
	var same_tick_pairs := 0
	var maximum_camera_step := 0.0
	var maximum_body_step := 0.0
	var maximum_alignment_error := 0.0
	var accumulated_delta := 0.0
	for sample in samples:
		accumulated_delta += float(sample["delta"])
		maximum_alignment_error = maxf(maximum_alignment_error, sample["camera"].distance_to(sample["expected"]))
	for i in range(1, samples.size()):
		var camera_step: float = samples[i]["camera"].distance_to(samples[i-1]["camera"])
		var body_step: float = samples[i]["body"].distance_to(samples[i-1]["body"])
		maximum_camera_step = maxf(maximum_camera_step, camera_step)
		maximum_body_step = maxf(maximum_body_step, body_step)
		if samples[i]["tick"] == samples[i-1]["tick"]:
			same_tick_pairs += 1
			if camera_step > .0001 and body_step < .00001:
				between_tick_motion += 1
	var render_hz: float = float(samples.size()) / accumulated_delta
	_check(samples.size() >= 200 and render_hz >= 50.0 and maximum_alignment_error < .00002, "Every render sample follows the body's interpolated position at 10Hz physics (alignment error %.6fm)" % maximum_alignment_error)
	_check(same_tick_pairs > samples.size() * .70 and between_tick_motion == same_tick_pairs, "Camera continues moving smoothly on every sampled render frame between physics ticks (%d/%d)" % [between_tick_motion,same_tick_pairs])
	_check(maximum_body_step > .35 and maximum_camera_step < .10, "Low-rate 0.4m body increments become sub-0.1m render increments (%.5fm)" % maximum_camera_step)
	print("CAMERA_INTERPOLATION_RESULT ", JSON.stringify({"physics_hz":10,"observed_render_hz":render_hz,"samples":samples.size(),"between_tick_motion":between_tick_motion,"same_tick_pairs":same_tick_pairs,"maximum_camera_frame_m":maximum_camera_step,"maximum_body_tick_m":maximum_body_step,"maximum_alignment_error_m":maximum_alignment_error}))
	probe.queue_free()
	player.qa_clear_input()
	Engine.physics_ticks_per_second = original_physics_rate
