extends SceneTree

## Differential rendered diagnostic for the original Hidden Leaf scene.
## Each mode is applied in isolation and restored before the next one.
##
## godot --path . --resolution 1600x900 --script res://qa/render_diagnostics.gd -- \
##   --qa --qa-out=<absolute-directory> [--warmup=3] [--sample-frames=120]

const LOCATIONS := [
	{"name":"Gate","bookmark":0},
	{"name":"Market","bookmark":1}
]
const MODES := ["baseline","ssao_off","shadows_off","forest_hidden","untextured_override"]

var world: Node3D
var output_dir := ""
var warmup_seconds := 3.0
var sample_frames := 120
var results: Array = []
var forest_nodes: Array[GeometryInstance3D] = []
var render_nodes: Array[GeometryInstance3D] = []
var neutral_material: StandardMaterial3D

func _initialize() -> void:
	output_dir=ProjectSettings.globalize_path("res://.build/diagnostics")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			output_dir=arg.trim_prefix("--qa-out=")
		elif arg.begins_with("--warmup="):
			warmup_seconds=maxf(0.0,float(arg.trim_prefix("--warmup=")))
		elif arg.begins_with("--sample-frames="):
			sample_frames=maxi(30,int(arg.trim_prefix("--sample-frames=")))
	call_deferred("_run")

func _percentile(sorted_samples: Array[float], fraction: float) -> float:
	if sorted_samples.is_empty():return 0.0
	return sorted_samples[clampi(int(floor((sorted_samples.size()-1)*fraction)),0,sorted_samples.size()-1)]

func _mean(samples: Array[float]) -> float:
	if samples.is_empty():return 0.0
	var total:=0.0
	for value: float in samples:total+=value
	return total/samples.size()

func _mesh_from_instance(node: GeometryInstance3D) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	if node is MultiMeshInstance3D:
		var multimesh: MultiMesh=(node as MultiMeshInstance3D).multimesh
		return multimesh.mesh if multimesh!=null else null
	return null

func _material_looks_like_tree(material: Material) -> bool:
	if material==null:return false
	if material.resource_name.to_lower().contains("tree"):return true
	if material is ShaderMaterial:
		var shader: Shader=(material as ShaderMaterial).shader
		if shader!=null and shader.resource_path.ends_with("/canopy.gdshader"):return true
	if material is BaseMaterial3D:
		var base_material:=material as BaseMaterial3D
		for texture: Texture2D in [base_material.albedo_texture,base_material.normal_texture]:
			if texture!=null and texture.resource_path.contains("tree_small_02_"):return true
	return false

func _is_forest_node(node: GeometryInstance3D) -> bool:
	# Runtime forest and street-tree instances are direct main-scene children.
	# Imported village buildings live below the GLB scene root and are excluded.
	if node.get_parent()!=world:return false
	if _material_looks_like_tree(node.material_override):return true
	var mesh:=_mesh_from_instance(node)
	if mesh==null:return false
	for surface in range(mesh.get_surface_count()):
		if _material_looks_like_tree(mesh.surface_get_material(surface)):return true
	return false

func _collect_render_nodes(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var geometry:=node as GeometryInstance3D
		render_nodes.append(geometry)
		if _is_forest_node(geometry):forest_nodes.append(geometry)
	for child: Node in node.get_children():_collect_render_nodes(child)

func _apply_mode(mode: String) -> Dictionary:
	var restore: Dictionary={}
	match mode:
		"baseline":
			pass
		"ssao_off":
			restore["ssao_enabled"]=world.environment.ssao_enabled
			world.environment.ssao_enabled=false
		"shadows_off":
			restore["shadow_enabled"]=world.sun.shadow_enabled
			world.sun.shadow_enabled=false
		"forest_hidden":
			var visibility: Array[bool]=[]
			for node: GeometryInstance3D in forest_nodes:
				visibility.append(node.visible)
				node.visible=false
			restore["visibility"]=visibility
		"untextured_override":
			var materials: Array[Material]=[]
			for node: GeometryInstance3D in render_nodes:
				materials.append(node.material_override)
				node.material_override=neutral_material
			restore["materials"]=materials
	return restore

func _restore_mode(mode: String, restore: Dictionary) -> void:
	match mode:
		"ssao_off":
			world.environment.ssao_enabled=bool(restore.ssao_enabled)
		"shadows_off":
			world.sun.shadow_enabled=bool(restore.shadow_enabled)
		"forest_hidden":
			var visibility: Array=restore.visibility
			for index in range(forest_nodes.size()):forest_nodes[index].visible=bool(visibility[index])
		"untextured_override":
			var materials: Array=restore.materials
			for index in range(render_nodes.size()):render_nodes[index].material_override=materials[index]

func _warm() -> void:
	var began:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-began<int(warmup_seconds*1000000.0):await process_frame

func _luminance(color: Color) -> float:
	return color.r*.2126+color.g*.7152+color.b*.0722

func _capture_with_dark_metric(path: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var save_error:=image.save_png(path)
	var near_black:=0
	var isolated_black:=0
	var sampled:=0
	# Sample the full-size render on a regular grid. The isolated measure counts
	# dark pixels whose immediate neighbors are materially brighter.
	for y in range(2,image.get_height()-2,4):
		for x in range(2,image.get_width()-2,4):
			var center:=_luminance(image.get_pixel(x,y))
			sampled+=1
			if center<.035:
				near_black+=1
				var neighbor_mean:=(_luminance(image.get_pixel(x-1,y))+_luminance(image.get_pixel(x+1,y))+_luminance(image.get_pixel(x,y-1))+_luminance(image.get_pixel(x,y+1)))*.25
				if neighbor_mean>.10:isolated_black+=1
	return {"path":path,"save_error":save_error,"sampled_pixels":sampled,
		"near_black_fraction":float(near_black)/maxi(sampled,1),
		"isolated_near_black_fraction":float(isolated_black)/maxi(sampled,1)}

func _measure(location: Dictionary, mode: String) -> Dictionary:
	world.visit_bookmark(int(location.bookmark))
	world.player.velocity=Vector3.ZERO
	world.player.enabled=false
	world.player.set_physics_process(false)
	await _warm()
	var frame_times: Array[float]=[]
	var process_times: Array[float]=[]
	var physics_times: Array[float]=[]
	var draw_calls: Array[float]=[]
	var primitives: Array[float]=[]
	var active_objects: Array[float]=[]
	var collision_pairs: Array[float]=[]
	var islands: Array[float]=[]
	var last_usec:=Time.get_ticks_usec()
	for frame in range(sample_frames):
		await process_frame
		var now_usec:=Time.get_ticks_usec()
		frame_times.append((now_usec-last_usec)/1000.0)
		last_usec=now_usec
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		active_objects.append(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
		collision_pairs.append(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
		islands.append(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
	var sorted: Array[float]=frame_times.duplicate();sorted.sort()
	var slug:=str(location.name).to_lower()+"__"+mode
	var capture:=await _capture_with_dark_metric(output_dir+"/"+slug+".png")
	return {"location":location.name,"bookmark":location.bookmark,"mode":mode,
		"player_position":str(world.player.global_position),"warmup_seconds":warmup_seconds,"frames":sample_frames,
		"mean_ms":_mean(frame_times),"mean_fps":1000.0/_mean(frame_times),"p50_ms":_percentile(sorted,.50),
		"p95_ms":_percentile(sorted,.95),"p99_ms":_percentile(sorted,.99),"max_ms":sorted[-1],
		"mean_process_ms":_mean(process_times),"mean_physics_process_ms":_mean(physics_times),
		"mean_draw_calls":_mean(draw_calls),"mean_primitives":_mean(primitives),
		"mean_physics_3d_active_objects":_mean(active_objects),
		"mean_physics_3d_collision_pairs":_mean(collision_pairs),"mean_physics_3d_islands":_mean(islands),
		"screenshot":capture}

func _diagnose() -> Array:
	var diagnoses: Array=[]
	for location: Dictionary in LOCATIONS:
		var location_results: Array=[]
		for result: Dictionary in results:
			if result.location==location.name:location_results.append(result)
		if location_results.is_empty():continue
		var baseline: Dictionary=location_results[0]
		var comparisons: Array=[]
		var best_mode:="baseline"
		var best_improvement:=0.0
		var stipple_candidate:="baseline"
		var best_stipple_reduction:=0.0
		for result: Dictionary in location_results:
			if result.mode=="baseline":continue
			var frame_improvement:=100.0*(float(baseline.mean_ms)-float(result.mean_ms))/maxf(float(baseline.mean_ms),.0001)
			var process_improvement:=100.0*(float(baseline.mean_process_ms)-float(result.mean_process_ms))/maxf(float(baseline.mean_process_ms),.0001)
			var draw_reduction:=100.0*(float(baseline.mean_draw_calls)-float(result.mean_draw_calls))/maxf(float(baseline.mean_draw_calls),1.0)
			var stipple_reduction:=float(baseline.screenshot.isolated_near_black_fraction)-float(result.screenshot.isolated_near_black_fraction)
			comparisons.append({"mode":result.mode,"frame_time_improvement_percent":frame_improvement,
				"process_time_improvement_percent":process_improvement,"draw_call_reduction_percent":draw_reduction,
				"isolated_near_black_fraction_reduction":stipple_reduction})
			if frame_improvement>best_improvement:best_improvement=frame_improvement;best_mode=result.mode
			if stipple_reduction>best_stipple_reduction:best_stipple_reduction=stipple_reduction;stipple_candidate=result.mode
		diagnoses.append({"location":location.name,"largest_frame_time_improvement":best_mode,
			"largest_frame_time_improvement_percent":best_improvement,
			"stipple_candidate_by_isolated_dark_pixel_reduction":stipple_candidate,
			"stipple_metric_reduction":best_stipple_reduction,"comparisons":comparisons,
			"interpretation":"SSAO or shadows implicates pixel/shadow cost; forest_hidden with draw-call reduction implicates forest scene overhead; untextured_override implicates texture/material shader cost. Confirm stipple attribution in paired screenshots."})
	return diagnoses

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args():
		printerr("Render diagnostics require explicit --qa.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	world=load("res://main.tscn").instantiate()
	root.add_child(world)
	# Allow deferred preferences to run, then select the original adaptive preset
	# without saving it and force the diagnostic's exact rendered window size.
	for frame in range(4):await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	world.set_quality(0)
	world.hud.set_paused(false)
	world.hud.hide()
	world.player.enabled=false
	world.player.set_physics_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	neutral_material=StandardMaterial3D.new()
	neutral_material.albedo_color=Color(.62,.62,.62)
	neutral_material.roughness=1.0
	_collect_render_nodes(world)
	if forest_nodes.is_empty() or render_nodes.is_empty():
		printerr("Render-node classification failed: forest=%d render=%d"%[forest_nodes.size(),render_nodes.size()])
		quit(2)
		return
	for location: Dictionary in LOCATIONS:
		for mode: String in MODES:
			var restore:=_apply_mode(mode)
			var result:=await _measure(location,mode)
			results.append(result)
			_restore_mode(mode,restore)
			await process_frame
			print("RENDER_DIAGNOSTIC ",JSON.stringify(result))
	var output:={"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),
		"display_server":DisplayServer.get_name(),"quality_index":world.quality_index,
		"viewport":str(root.get_visible_rect().size),"window_size":str(DisplayServer.window_get_size()),
		"internal_render_scale":root.scaling_3d_scale,"internal_render_size":str(root.get_visible_rect().size*root.scaling_3d_scale),
		"forest_nodes_hidden":forest_nodes.size(),"render_nodes_neutralized":render_nodes.size(),
		"warmup_seconds":warmup_seconds,"sample_frames":sample_frames,
		"timing":"monotonic wall clock between rendered process frames; modes applied individually and restored before the next measurement",
		"results":results,"diagnoses":_diagnose()}
	var file:=FileAccess.open(output_dir+"/render-diagnostics.json",FileAccess.WRITE)
	if file==null:
		printerr("Cannot write render diagnostics JSON: ",FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify(output,"\t"));file.close()
	print("RENDER_DIAGNOSTICS_RESULT ",JSON.stringify({"result":output_dir+"/render-diagnostics.json","captures":results.size()}))
	quit()
