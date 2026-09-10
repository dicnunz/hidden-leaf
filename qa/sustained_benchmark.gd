extends SceneTree

## Rendered sustained movement benchmark.
##
## Run with:
## godot --path . --resolution 1600x900 --script res://qa/sustained_benchmark.gd -- \
##   --qa --qa-out=<absolute-directory> [--route-duration=60] [--warmup=10]

const ROUTES := [
	{"name":"Gate approach","start":Vector3(0,.24,394),"end":Vector3(0,.24,366.13)},
	{"name":"Market street","start":Vector3(13,.24,169),"end":Vector3(13,.24,141.28)},
	{"name":"Residence plaza","start":Vector3(0,.24,-174),"end":Vector3(0,.24,-201.76)}
]

var world: Node3D
var output_dir := ""
var route_duration_seconds := 60.0
var warmup_seconds := 10.0
var script_started_usec := Time.get_ticks_usec()
var startup_wall_ms := 0.0
var results: Array = []
var rss_samples: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			output_dir = arg.trim_prefix("--qa-out=")
		elif arg.begins_with("--route-duration="):
			route_duration_seconds = maxf(1.0, float(arg.trim_prefix("--route-duration=")))
		elif arg.begins_with("--duration-seconds="):
			route_duration_seconds = maxf(1.0, float(arg.trim_prefix("--duration-seconds=")))
		elif arg.begins_with("--warmup="):
			warmup_seconds = maxf(0.0, float(arg.trim_prefix("--warmup=")))
		elif arg.begins_with("--warmup-seconds="):
			warmup_seconds = maxf(0.0, float(arg.trim_prefix("--warmup-seconds=")))
	call_deferred("_run")

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func _percentile(sorted_samples: Array[float], percentile: float) -> float:
	if sorted_samples.is_empty():
		return 0.0
	var index := clampi(int(floor((sorted_samples.size()-1)*percentile)),0,sorted_samples.size()-1)
	return sorted_samples[index]

func _sample_rss(label_text: String, route_name: String) -> void:
	var output: Array = []
	var exit_code := OS.execute("/bin/ps",["-o","rss=","-p",str(OS.get_process_id())],output,true)
	var rss_kb := 0
	if exit_code==0 and not output.is_empty():
		rss_kb = int(str(output[0]).strip_edges())
	rss_samples.append({
		"label":label_text,"route":route_name,"elapsed_ms":(Time.get_ticks_usec()-script_started_usec)/1000.0,
		"rss_kb":rss_kb,"rss_bytes":rss_kb*1024,"command":"/bin/ps -o rss= -p <godot-pid>","exit_code":exit_code
	})

func _set_route_input(target: Vector3) -> float:
	# A benchmark window losing focus must not silently turn a movement run into
	# a stationary measurement. The QA interface still gates all injected input.
	world.player.enabled=true
	var offset: Vector3=target-world.player.global_position
	offset.y=0
	var distance: float=offset.length()
	var local_direction: Vector3=world.player.global_basis.inverse()*(offset.normalized() if distance>.001 else Vector3.ZERO)
	world.player.qa_set_input(Vector2(local_direction.x,local_direction.z))
	return distance

func _walk_bidirectional(route: Dictionary, duration_seconds: float, record: bool) -> Dictionary:
	var target_index := 1
	var target: Vector3=route.end
	var last_position: Vector3=world.player.global_position
	var last_usec:=Time.get_ticks_usec()
	var began_usec:=last_usec
	var frame_times: Array[float]=[]
	var distance_walked:=0.0
	var reversals:=0
	var blocked_frames:=0
	var blocked_duration_ms:=0.0
	var blocked_events:=0
	var consecutive_blocked_ms:=0.0
	var blocked_event_open:=false
	var side_collision_frames:=0
	var left_floor_frames:=0
	while Time.get_ticks_usec()-began_usec<int(duration_seconds*1000000.0):
		var target_distance:=_set_route_input(target)
		await process_frame
		var now_usec:=Time.get_ticks_usec()
		var frame_ms: float=(now_usec-last_usec)/1000.0
		last_usec=now_usec
		var position: Vector3=world.player.global_position
		var frame_distance:=_horizontal_distance(position,last_position)
		distance_walked+=frame_distance
		last_position=position
		if record:
			frame_times.append(frame_ms)
			if not world.player.is_on_floor():left_floor_frames+=1
			var side_contact:=false
			for collision_index in range(world.player.get_slide_collision_count()):
				var collision: KinematicCollision3D=world.player.get_slide_collision(collision_index)
				if absf(collision.get_normal().y)<.65:side_contact=true
			if side_contact:side_collision_frames+=1
			var blocked_now:=target_distance>1.0 and frame_distance<.002 and Vector2(world.player.velocity.x,world.player.velocity.z).length()<.12
			if blocked_now:
				blocked_frames+=1
				blocked_duration_ms+=frame_ms
				consecutive_blocked_ms+=frame_ms
				if consecutive_blocked_ms>=1000.0 and not blocked_event_open:
					blocked_events+=1
					blocked_event_open=true
			else:
				consecutive_blocked_ms=0.0
				blocked_event_open=false
		if _horizontal_distance(position,target)<.35:
			reversals+=1
			target_index=1-target_index
			target=route.end if target_index==1 else route.start
	world.player.qa_set_input(Vector2.ZERO)
	return {"frame_times_ms":frame_times,"distance_walked_m":distance_walked,"reversals":reversals,
		"blocked_frames":blocked_frames,"blocked_duration_ms":blocked_duration_ms,"blocked_events":blocked_events,
		"side_collision_frames":side_collision_frames,"left_floor_frames":left_floor_frames}

func _run_route(route: Dictionary) -> Dictionary:
	var direction: Vector3=route.end-(route.start+Vector3.UP*1.7)
	world.player.teleport_to(route.start,atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
	world.player.enabled=true
	world.player.qa_set_input(Vector2.ZERO)
	await process_frame
	_sample_rss("before_warmup",route.name)
	var warmup:=await _walk_bidirectional(route,warmup_seconds,false)
	_sample_rss("after_warmup",route.name)
	var measurement_start: Vector3=world.player.global_position
	var measurement:=await _walk_bidirectional(route,route_duration_seconds,true)
	var measurement_end: Vector3=world.player.global_position
	_sample_rss("after_measurement",route.name)
	var raw: Array[float]=measurement.frame_times_ms
	var sorted: Array[float]=raw.duplicate()
	sorted.sort()
	var total:=0.0
	var over_33:=0
	var over_50:=0
	var over_100:=0
	for ms: float in raw:
		total+=ms
		if ms>33.3:over_33+=1
		if ms>50.0:over_50+=1
		if ms>100.0:over_100+=1
	var mean_ms:=total/maxf(raw.size(),1)
	var result: Dictionary={
		"route":route.name,"duration_seconds":route_duration_seconds,"warmup_seconds":warmup_seconds,
		"start":str(route.start),"end":str(route.end),"corridor_length_m":_horizontal_distance(route.start,route.end),
		"measurement_start":str(measurement_start),"measurement_end":str(measurement_end),
		"distance_walked_m":measurement.distance_walked_m,"warmup_distance_m":warmup.distance_walked_m,
		"reversals":measurement.reversals,"warmup_reversals":warmup.reversals,
		"frames":raw.size(),"mean_ms":mean_ms,"mean_fps":1000.0/mean_ms if mean_ms>0 else 0.0,
		"p50_ms":_percentile(sorted,.50),"p95_ms":_percentile(sorted,.95),"p99_ms":_percentile(sorted,.99),
		"max_ms":sorted[-1] if not sorted.is_empty() else 0.0,
		"frames_over_33_3_ms":over_33,"frames_over_50_ms":over_50,"frames_over_100_ms":over_100,
		"blocked_frames":measurement.blocked_frames,"blocked_duration_ms":measurement.blocked_duration_ms,
		"blocked_events_1s":measurement.blocked_events,"side_collision_frames":measurement.side_collision_frames,
		"left_floor_frames":measurement.left_floor_frames,"on_floor_at_end":world.player.is_on_floor(),
		"quality_index":world.get("quality_index"),"viewport":str(root.get_visible_rect().size),
		"internal_render_scale":root.scaling_3d_scale,"raw_frame_times_ms":raw
	}
	print("SUSTAINED_BENCHMARK ",JSON.stringify(result.duplicate().merged({"raw_frame_times_ms":"written to JSON (%d samples)"%raw.size()},true)))
	return result

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or output_dir.is_empty():
		printerr("Sustained benchmark requires --qa and --qa-out=<absolute-directory>.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	world=load("res://main.tscn").instantiate()
	root.add_child(world)
	# Let deferred saved-preference application complete, then select the project's
	# original adaptive quality preset without writing the user's preferences.
	for frame in range(4):await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	world.set_quality(0)
	world.hud.set_paused(false)
	world.hud.hide()
	world.player.enabled=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await RenderingServer.frame_post_draw
	startup_wall_ms=(Time.get_ticks_usec()-script_started_usec)/1000.0
	_sample_rss("startup_ready","all")
	for route: Dictionary in ROUTES:
		results.append(await _run_route(route))
	var failures: Array[String]=[]
	for result: Dictionary in results:
		if int(result.reversals)<2:failures.append(str(result.route)+": fewer than two completed traversals")
		if int(result.blocked_events_1s)>0:failures.append(str(result.route)+": blocked movement event")
		if not bool(result.on_floor_at_end):failures.append(str(result.route)+": ended off floor")
	var output:={
		"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),
		"display_server":DisplayServer.get_name(),"quality_index":world.quality_index,
		"viewport":str(root.get_visible_rect().size),"window_size":str(DisplayServer.window_get_size()),
		"internal_render_scale":root.scaling_3d_scale,"internal_render_size":str(root.get_visible_rect().size*root.scaling_3d_scale),
		"startup_wall_ms_script_to_first_post_draw":startup_wall_ms,"world_ready_ms":world.ready_ms,
		"route_duration_seconds":route_duration_seconds,"warmup_seconds":warmup_seconds,
		"timing":"raw monotonic wall-clock intervals between rendered process frames while the actual CharacterBody3D controller walks bidirectionally",
		"blocked_definition":"frame: target farther than 1m, horizontal displacement below 2mm, and horizontal speed below 0.12m/s; event: at least 1 continuous second",
		"memory_sampling":"real Godot process RSS from /bin/ps outside timed measurement windows; external sampler log may provide higher cadence",
		"rss_samples":rss_samples,"routes":results,"failures":failures,"failure_count":failures.size()
	}
	var file:=FileAccess.open(output_dir+"/sustained-benchmark.json",FileAccess.WRITE)
	if file==null:
		printerr("Cannot write sustained benchmark JSON: ",FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify(output,"\t"))
	file.close()
	print("SUSTAINED_RESULT ",JSON.stringify({"result":output_dir+"/sustained-benchmark.json","failure_count":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
