extends SceneTree

var world: Node3D
var results: Array=[]
var output_dir := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):output_dir=arg.trim_prefix("--qa-out=")
	call_deferred("_run")

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or output_dir.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.hud.set_paused(false)
	world.hud.hide()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for route: Array in [
		["Gate approach",Vector3(0,.24,394),Vector3(0,14,345),Vector3.FORWARD],
		["Market street",Vector3(13,.24,169),Vector3(21,2.5,145),Vector3.FORWARD],
		["Residence plaza",Vector3(0,.24,-174),Vector3(0,19,-234),Vector3.FORWARD]
	]:
		var direction: Vector3=route[2]-(route[1]+Vector3.UP*1.7)
		world.player.teleport_to(route[1],atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
		world.player.enabled=true
		world.player.qa_set_input(Vector2.ZERO)
		var warmup:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-warmup<1500:await process_frame
		# Initial macOS window focus may pause the player during shader warmup.
		world.player.enabled=true
		var start: Vector3=world.player.position
		var local_direction: Vector3=world.player.global_basis.inverse()*route[3]
		world.player.qa_set_input(Vector2(local_direction.x,local_direction.z))
		var last:=Time.get_ticks_usec()
		var began:=last
		var samples: Array[float]=[]
		while Time.get_ticks_usec()-began<7000000:
			await process_frame
			var now:=Time.get_ticks_usec()
			samples.append((now-last)/1000.)
			last=now
		world.player.qa_set_input(Vector2.ZERO)
		var finish: Vector3=world.player.position
		samples.sort()
		var total:=0.0
		for ms: float in samples:total+=ms
		var result: Dictionary={"route":route[0],"start":str(start),"finish":str(finish),"distance_m":start.distance_to(finish),"mean_fps":1000./(total/samples.size()),"p95_ms":samples[int(samples.size()*.95)],"p99_ms":samples[int(samples.size()*.99)],"max_ms":samples[-1],"frames":samples.size(),"on_floor_at_end":world.player.is_on_floor(),"quality":world.quality_index}
		results.append(result)
		print("MOVING_BENCHMARK ",JSON.stringify(result))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output_dir+"/"+str(results.size())+".png")
	var file:=FileAccess.open(output_dir+"/moving-benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"routes":results,"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(root.get_visible_rect().size),"timing":"monotonic wall clock while the actual CharacterBody3D walks using its explicit QA input interface"},"\t"))
	for result: Dictionary in results:
		if result.distance_m < 20.0 or not result.on_floor_at_end:
			push_error("Moving route failed: "+str(result.route))
			quit(1)
			return
	quit()
