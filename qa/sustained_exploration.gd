extends "res://qa/sustained_benchmark.gd"

## Exercises the actual packaged-scene loader, persistent controller and renderer.
## --villages=leaf,sand,leaf tests replacement and return to the original world.
## Missing villages fail explicitly. Short diagnostic runs cannot pass acceptance.
const VILLAGE_ROUTES := {
	"leaf": ROUTES,
	"sand": [
		{"name":"Sand avenue", "start":Vector3(0,.24,72), "end":Vector3(0,.24,42)},
		{"name":"Kazekage approach", "start":Vector3(0,.24,-15), "end":Vector3(0,.24,15)},
		{"name":"Clay district", "start":Vector3(-9,.24,42), "end":Vector3(-9,.24,12)}
	]
}

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or output_dir.is_empty():
		printerr("Requires --qa --qa-out=<directory> [--villages=leaf,sand,leaf].")
		quit(2)
		return
	var village_ids := PackedStringArray(["leaf","sand","leaf"])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--villages="):
			village_ids = argument.trim_prefix("--villages=").split(",", false)
	if village_ids.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	world = load("res://exploration.tscn").instantiate()
	root.add_child(world)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var failures: Array[String] = []
	var switches: Array = []
	for village_id in village_ids:
		if not VILLAGE_ROUTES.has(village_id):
			failures.append(village_id + ": no validated traversal route")
			continue
		var load_started := Time.get_ticks_usec()
		# Initial startup already requests Leaf. Subsequent requests use the same
		# application handler as its menu and retain all failure checks.
		if not world.session.is_loading() and world.current_id != village_id:
			world._request_village(village_id)
		while world.session.is_loading() and Time.get_ticks_usec()-load_started < 60000000:
			await process_frame
		if world.current_id != village_id or world.session.is_loading():
			failures.append(village_id + ": load failed or exceeded 60 seconds")
			continue
		await RenderingServer.frame_post_draw
		var load_ms := (Time.get_ticks_usec()-load_started)/1000.0
		switches.append({"id":village_id,"load_to_first_draw_ms":load_ms,
			"resident_worlds":world.session.get_child_count()})
		if world.session.get_child_count() != 1:
			failures.append(village_id + ": expected exactly one resident world")
		world._set_paused(false)
		world.menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sample_rss("village_ready", village_id)
		for route: Dictionary in VILLAGE_ROUTES[village_id]:
			var measurement := await _run_route(route)
			measurement["village"] = village_id
			results.append(measurement)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir+"/%s-route-%d.png" % [village_id, results.size()])
			if measurement.reversals < 2:
				failures.append(village_id + "/" + str(route.name) + ": fewer than two traversals")
			if measurement.blocked_events_1s > 0 or not measurement.on_floor_at_end:
				failures.append(village_id + "/" + str(route.name) + ": traversal failed")
			if measurement.mean_ms > 16.7:
				failures.append(village_id + "/" + str(route.name) + ": mean frame time exceeds 16.7 ms")
			if measurement.frames_over_50_ms > 0:
				failures.append(village_id + "/" + str(route.name) + ": severe frame spikes require review")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output_dir+"/"+village_id+"-final.png")
	if route_duration_seconds < 60.0 or warmup_seconds < 10.0:
		failures.append("Diagnostic duration cannot pass sustained acceptance")
	var report := {"godot":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(),
		"viewport":str(root.get_visible_rect().size),"internal_render_scale":root.scaling_3d_scale,
		"taa":root.use_taa,"switches":switches,"routes":results,"rss_samples":rss_samples,
		"failures":failures,"passed":failures.is_empty(),
		"scope":"Only the named villages and routes were exercised. This does not constitute all-five release acceptance."}
	var file := FileAccess.open(output_dir+"/sustained-exploration.json",FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("EXPLORATION_BENCHMARK ",JSON.stringify({"path":output_dir,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
