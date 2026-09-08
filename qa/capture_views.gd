extends SceneTree

var output_dir:=""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):output_dir=arg.trim_prefix("--qa-out=")
	call_deferred("_run")

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or output_dir.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var world: Node3D=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.hud.hide()
	world.player.enabled=false
	world.player.set_physics_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for view: Array in [
		["ichiraku-front",Vector3(13,.205,143.6),Vector3(19.4,2.65,144)],
		["ichiraku-counter",Vector3(20.35,.3215,147.2),Vector3(22.65,1.75,142.8)],
		["ichiraku-kitchen",Vector3(23.0,.322,143.3),Vector3(18,1.4,144)],
		["ichiraku-oblique",Vector3(13.5,.205,150.5),Vector3(20,2.7,144)],
		["market-street",Vector3(13,.205,164),Vector3(15,2.3,135)],
		["market-rear",Vector3(32,.205,168),Vector3(30,2.3,142)]
	]:
		var direction: Vector3=view[2]-(view[1]+Vector3.UP*1.7)
		world.player.teleport_to(view[1],atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
		for _i in range(90):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output_dir+"/"+view[0]+".png")
		print("VIEW_SAVED ",view[0])
	quit()
