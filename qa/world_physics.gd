extends SceneTree

## Integrated world physics QA. This instantiates the actual main scene and uses only
## the controller's explicit --qa input gate. No fixture replacement, GUI, or GPU benchmark.
## godot --headless --path . --script res://qa/world_physics.gd --fixed-fps 60 -- --qa
const RESULT_PATH := "user://qa/world_physics_results.json"
var world: Node3D
var player: CharacterBody3D
var checks: Array[Dictionary] = []
var evidence: Dictionary = {}
var started_usec := Time.get_ticks_usec()
var simulated_frames := 0

func _initialize() -> void:
	call_deferred("_run")

func _vec(v: Vector3) -> Array:
	return [snappedf(v.x,.0001),snappedf(v.y,.0001),snappedf(v.z,.0001)]

func _frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame
		simulated_frames += 1

func _check(passed: bool, name_text: String, detail: Dictionary = {}) -> void:
	checks.append({"name":name_text,"passed":passed,"evidence":detail})
	print("WORLD_QA ","PASS " if passed else "FAIL ",name_text)

func _collider_path(collider: Object) -> String:
	return str(collider.get_path()) if collider is Node else str(collider)

func _ground(position_value: Vector3, depth: float = 12.0) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(position_value+Vector3(0,2.4,0),position_value-Vector3(0,depth,0),1)
	query.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"hit":false}
	return {"hit":true,"position":_vec(hit.position),"normal":_vec(hit.normal),"collider":_collider_path(hit.collider),"feet_above_surface_m":snappedf(position_value.y-hit.position.y,.0001)}

func _overlaps_at(position_value: Vector3) -> Array[String]:
	# Shrink the query slightly so ordinary resting floor and wall contact is allowed.
	var shape := CapsuleShape3D.new()
	shape.radius = .295
	shape.height = 1.76
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY,position_value+Vector3(0,.91,0))
	query.exclude = [player.get_rid()]
	var hits := world.get_world_3d().direct_space_state.intersect_shape(query,12)
	var paths: Array[String] = []
	for hit: Dictionary in hits: paths.append(_collider_path(hit.collider))
	return paths

func _body_overlaps() -> Array[String]:
	return _overlaps_at(player.global_position)

func _add_monument_visibility_proxies(node: Node) -> int:
	# The app excludes monument portraits from gameplay collision. Add ray-only copies
	# on a QA layer, so a reported view cannot look through the visible carved heads.
	var count := 0
	if node is MeshInstance3D:
		var portrait := false
		for i in range(1,6):
			portrait=portrait or str(node.name).begins_with("Hokage %d " % i)
		if portrait:
			var body := StaticBody3D.new()
			body.name="QA_VisibleMonument_%d" % node.get_instance_id()
			body.collision_layer=1<<20;body.collision_mask=0
			var collider := CollisionShape3D.new()
			collider.shape=node.mesh.create_trimesh_shape()
			body.add_child(collider);root.add_child(body)
			body.global_transform=node.global_transform
			count+=1
	for child in node.get_children(): count+=_add_monument_visibility_proxies(child)
	return count

func _find_safe_overlook() -> void:
	var ray_proxy_count := _add_monument_visibility_proxies(world)
	await _frames(2)
	var candidates: Array[Dictionary]=[]
	var center := Vector3(0,20,0)
	# Earliest front-to-back stable point in a 0..30m strip; no structures are added.
	for by2 in range(600,681):
		var by:=by2*.5
		for xx in range(0,31,2):
			var query:=PhysicsRayQueryParameters3D.create(Vector3(xx,210,-by),Vector3(xx,130,-by),1)
			var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.normal.y<.75 or hit.position.y<145: continue
			var floor_point: Vector3=hit.position
			var supported:=true
			var minimum_normal_y: float=hit.normal.y
			for offset: Vector3 in [Vector3(.55,0,0),Vector3(-.55,0,0),Vector3(0,0,.55),Vector3(0,0,-.55)]:
				var q:=PhysicsRayQueryParameters3D.create(floor_point+offset+Vector3.UP*2,floor_point+offset-Vector3.UP*2,1)
				var support:=world.get_world_3d().direct_space_state.intersect_ray(q)
				if support.is_empty() or support.normal.y<.72 or absf(support.position.y-floor_point.y)>.50:
					supported=false
					break
				minimum_normal_y=minf(minimum_normal_y,support.normal.y)
			if not supported or not _overlaps_at(floor_point+Vector3.UP*.05).is_empty(): continue
			var sight:=PhysicsRayQueryParameters3D.create(floor_point+Vector3.UP*1.7,center,1|(1<<20))
			var obstruction:=world.get_world_3d().direct_space_state.intersect_ray(sight)
			if not obstruction.is_empty(): continue
			candidates.append({"godot_ground":_vec(floor_point),"blender_ground":[floor_point.x,by,floor_point.y],
				"bookmark_suggestion":_vec(floor_point+Vector3.UP*.22),"normal":_vec(hit.normal),
				"minimum_support_normal_y":minimum_normal_y,"clear_eye_ray_to":_vec(center),"support_radius_m":.55})
		if candidates.size()>=12: break
	var verified: Array[Dictionary]=[]
	for candidate in candidates.slice(0,6):
		var position_array: Array=candidate.bookmark_suggestion
		var initial:=Vector3(position_array[0],position_array[1],position_array[2])
		await _settle(initial,120)
		candidate["settled_after_2_seconds"]=_vec(player.position)
		candidate["on_floor"]=player.is_on_floor()
		candidate["drift_m"]=Vector2(player.position.x-initial.x,player.position.z-initial.z).length()
		candidate["body_overlaps"]=_body_overlaps()
		candidate["stable"]=player.is_on_floor() and float(candidate.drift_m)<.08 and _body_overlaps().is_empty()
		verified.append(candidate)
	evidence.safe_overlook_search={"search_bounds_blender_xy":[0,30,300,340],"step_m":[2,.5],
		"monument_ray_only_proxies":ray_proxy_count,"candidates":candidates,"physically_verified":verified}
	print("WORLD_QA SAFE_OVERLOOK ",JSON.stringify({"verified_candidates":verified.size(),"nearest":verified[0] if not verified.is_empty() else {}}))

func _settle(position_value: Vector3, frames: int = 45) -> void:
	player.teleport_to(position_value)
	player.enabled = true
	await _frames(frames)

func _stop() -> void:
	player.qa_set_input(Vector2.ZERO)
	await _frames(20)

func _move(direction_value: Vector3, frames: int, label_text: String) -> Dictionary:
	var start := player.global_position
	var local_direction: Vector3 = player.global_basis.inverse()*direction_value.normalized()
	var accepted: bool = player.qa_set_input(Vector2(local_direction.x,local_direction.z))
	var trace: Array = [_vec(start)]
	var contacts: Dictionary = {}
	var on_floor_frames := 0
	var minimum_y: float = start.y
	var maximum_y: float = start.y
	var peak_horizontal_speed := 0.0
	var finite := true
	var peak_single_frame_motion := 0.0
	var previous := start
	for i in range(frames):
		await _frames(1)
		var current := player.global_position
		finite = finite and current.is_finite() and player.velocity.is_finite()
		minimum_y = minf(minimum_y,current.y)
		maximum_y = maxf(maximum_y,current.y)
		peak_horizontal_speed = maxf(peak_horizontal_speed,Vector2(player.velocity.x,player.velocity.z).length())
		peak_single_frame_motion = maxf(peak_single_frame_motion,current.distance_to(previous))
		previous = current
		if player.is_on_floor(): on_floor_frames += 1
		if i%60 == 59 or i == frames-1: trace.append(_vec(current))
		for j in range(player.get_slide_collision_count()):
			var collision := player.get_slide_collision(j)
			if absf(collision.get_normal().y)<.65:
				contacts[_collider_path(collision.get_collider())]=_vec(collision.get_normal())
	var ending := player.global_position
	var delta := ending-start
	var output := {"start":_vec(start),"end":_vec(ending),"frames":frames,"simulated_seconds":frames/60.0,
		"horizontal_distance_m":snappedf(Vector2(delta.x,delta.z).length(),.0001),
		"progress_along_input_m":snappedf(delta.dot(direction_value.normalized()),.0001),
		"height_range_m":[snappedf(minimum_y,.0001),snappedf(maximum_y,.0001)],
		"on_floor_fraction":float(on_floor_frames)/frames,"peak_horizontal_speed_mps":peak_horizontal_speed,
		"peak_single_frame_motion_m":peak_single_frame_motion,"finite":finite,"input_accepted":accepted,
		"side_contacts":contacts,"trace_one_sample_per_second":trace,"ground_at_end":_ground(ending),
		"body_overlaps_at_end":_body_overlaps()}
	evidence[label_text]=output
	return output

func _walk_to(target: Vector3, frame_limit: int, label_text: String) -> Dictionary:
	# Closed-loop controller input reaches narrow authored aisles without teleporting.
	var start := player.position
	var previous := start
	var peak_motion := 0.0
	var finite := true
	var contacts: Dictionary = {}
	var trace: Array = [_vec(start)]
	var frames := 0
	for i in range(frame_limit):
		var delta := target-player.position
		delta.y=0
		var distance := delta.length()
		var horizontal_speed := Vector2(player.velocity.x,player.velocity.z).length()
		if distance<.012 and horizontal_speed<.10: break
		var direction := delta.normalized() if distance>.001 else Vector3.ZERO
		var local: Vector3=player.global_basis.inverse()*direction
		player.qa_set_input(Vector2(local.x,local.z)*minf(1.0,distance*2.0))
		await _frames(1)
		frames+=1
		finite=finite and player.position.is_finite() and player.velocity.is_finite()
		peak_motion=maxf(peak_motion,player.position.distance_to(previous))
		previous=player.position
		if i%30==29: trace.append(_vec(player.position))
		for j in range(player.get_slide_collision_count()):
			var collision:=player.get_slide_collision(j)
			if absf(collision.get_normal().y)<.65:
				contacts[_collider_path(collision.get_collider())]=_vec(collision.get_normal())
	await _stop()
	trace.append(_vec(player.position))
	var residual:=Vector2(player.position.x-target.x,player.position.z-target.z).length()
	var result: Dictionary={"start":_vec(start),"target":_vec(target),"end":_vec(player.position),
		"frames":frames,"residual_m":residual,"reached":residual<.08,"on_floor":player.is_on_floor(),
		"finite":finite,"peak_single_frame_motion_m":peak_motion,"side_contacts":contacts,
		"body_overlaps_at_end":_body_overlaps(),"trace":trace,"ground_at_end":_ground(player.position)}
	evidence[label_text]=result
	return result

func _ichiraku_local(point: Vector3) -> Vector3:
	return Vector3(18.0+point.y,.20+point.z,144.0+point.x)

func _bookmarks() -> void:
	var summary: Array = []
	for i in range(world.BOOKMARKS.size()):
		var bookmark: Array = world.BOOKMARKS[i]
		world.visit_bookmark(i)
		player.enabled = true
		var initial := player.global_position
		var ray_initial := _ground(initial,180)
		await _frames(180)
		var ending := player.global_position
		var overlaps := _body_overlaps()
		var drift := Vector2(ending.x-initial.x,ending.z-initial.z).length()
		var allowed_drop := 6.0 if str(bookmark[0])=="Overlook" else .40
		var detail := {"bookmark":bookmark[0],"requested":_vec(initial),"settled":_vec(ending),
			"vertical_drop_m":initial.y-ending.y,"horizontal_drift_m":drift,"on_floor":player.is_on_floor(),
			"initial_ground_ray":ray_initial,"ground_ray":_ground(ending),"body_overlaps":overlaps}
		summary.append(detail)
		_check(player.is_on_floor() and ending.is_finite() and absf(initial.y-ending.y)<=allowed_drop and drift<.20 and overlaps.is_empty(),
			"Bookmark %s lands on nearby unobstructed ground" % bookmark[0],detail)
	evidence.bookmarks=summary

func _gate_route() -> void:
	world.visit_bookmark(0)
	player.enabled = true
	await _frames(45)
	var first := await _move(Vector3.FORWARD,620,"gate_first_40m")
	_check(float(first.progress_along_input_m)>40.0 and absf(player.position.x)<.10,"Main gate approach walks 40m without hitting an invisible wall",first)
	var crossing := await _move(Vector3.FORWARD,330,"gate_arch_crossing")
	_check(player.position.z<333.0 and absf(player.position.x)<.10 and player.is_on_floor(),"Main gate arch and open doors permit complete passage",crossing)
	await _stop()

func _house_wall() -> void:
	var selected: Dictionary = {}
	for house: Dictionary in world.meta.districts.buildings:
		if house.type=="rect" and house.get("curated_market",false) and house.x>20 and house.x<30 and house.y>-190 and house.y<-165:
			selected=house
			break
	if selected.is_empty():
		_check(false,"A representative rectangular house was selected from current metadata")
		return
	var collider: Dictionary=selected.collision_footprint
	var center := Vector3(collider.x,0,-collider.y)
	var yaw: float=collider.rotation_z
	# Blender local front (0,-1,0), mapped to Godot coordinates (x,z,-y).
	var outward := Vector3(sin(yaw),0,cos(yaw))
	var start := center+outward*(float(collider.depth)/2.0+6.0)+Vector3.UP*.24
	await _settle(start)
	var ray_query := PhysicsRayQueryParameters3D.create(start+Vector3.UP,center+Vector3.UP,1)
	var wall_hit := world.get_world_3d().direct_space_state.intersect_ray(ray_query)
	var route := await _move(-outward,210,"house_wall_contact")
	var normal_clearance: float=(player.position-center).dot(outward)-float(collider.depth)/2.0
	route["building_id"]=selected.building_id
	route["wall_clearance_to_capsule_center_m"]=normal_clearance
	route["physical_wall_ray_hit"]=not wall_hit.is_empty()
	_check(not wall_hit.is_empty() and normal_clearance>.25 and normal_clearance<.40 and float(route.progress_along_input_m)>4.9 and float(route.progress_along_input_m)<6.1,"House wall blocks walking at the real façade",route)
	var retreat := await _move(outward,90,"house_wall_retreat")
	_check(float(retreat.progress_along_input_m)>5.4,"Player can retreat after contacting a house wall",retreat)
	await _stop()

func _ichiraku() -> void:
	var shop: Dictionary={}
	for place: Dictionary in world.meta.landmarks.landmarks:
		if place.name=="Ichiraku Ramen": shop=place
	_check(not shop.is_empty() and int(shop.get("dimensions_m",{}).get("stools",0))==6 and absf(float(shop.get("floor_world_z",0))-.3215)<.005,
		"Ichiraku metadata describes the six-stool v3 shop",shop)
	var seats: Array=[]
	var all_seats_solid:=true
	for i in range(6):
		var center:=_ichiraku_local(Vector3(-3.06+i*1.045,.20,0))
		var query:=PhysicsRayQueryParameters3D.create(Vector3(center.x,1.35,center.z),Vector3(center.x,.50,center.z),1)
		query.exclude=[player.get_rid()]
		var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
		var valid:=not hit.is_empty() and absf(float(hit.position.y)-.978)<.035
		all_seats_solid=all_seats_solid and valid
		seats.append({"index":i,"center_xz":[center.x,center.z],"hit":not hit.is_empty(),
			"height":hit.position.y if not hit.is_empty() else null,
			"collider":_collider_path(hit.collider) if not hit.is_empty() else ""})
	_check(all_seats_solid,"All six Ichiraku stool seats have physical surfaces at the authored height",{"seats":seats,"expected_world_y":.978})
	world.visit_bookmark(1)
	player.enabled=true
	await _frames(45)
	var street_start:=player.position
	var aligned:=await _walk_to(_ichiraku_local(Vector3(3.18,-5,.04)),150,"ichiraku_street_to_end_aisle")
	_check(bool(aligned.reached) and player.position.x<14 and player.position.distance_to(street_start)>3.0,
		"Ichiraku bookmark can walk along the street to the counter-end aisle",aligned)
	var entry:=await _walk_to(_ichiraku_local(Vector3(3.18,2.80,.1215)),240,"ichiraku_front_ramp_and_end_aisle")
	_check(bool(entry.reached) and player.position.x>20.6 and player.is_on_floor() and absf(player.position.y-.3215)<.065 and _body_overlaps().is_empty(),
		"Ichiraku front ramp and 0.75m counter-end aisle permit entry to the kitchen",entry)
	var kitchen:=await _walk_to(_ichiraku_local(Vector3(.075,2.80,.1215)),140,"ichiraku_kitchen_crossing")
	_check(bool(kitchen.reached) and _body_overlaps().is_empty(),"Ichiraku kitchen aisle permits lateral walking behind the counter",kitchen)
	var counter:=await _move(Vector3.LEFT,65,"ichiraku_counter_contact")
	var clearance:=player.position.x-19.70
	counter["counter_back_world_x"]=19.70
	counter["clearance_to_capsule_center_m"]=clearance
	_check(clearance>.27 and clearance<.39 and float(counter.progress_along_input_m)>.65 and float(counter.progress_along_input_m)<1.0 and not counter.side_contacts.is_empty(),
		"Ichiraku counter blocks the walking capsule at its actual kitchen edge",counter)
	var retreat:=await _move(Vector3.RIGHT,27,"ichiraku_counter_retreat")
	_check(float(retreat.progress_along_input_m)>1.30 and player.position.x>21.25,
		"Ichiraku counter contact allows a clean retreat",retreat)
	await _stop()
	var door_alignment:=await _walk_to(_ichiraku_local(Vector3(2.72,3.50,.1215)),150,"ichiraku_rear_door_alignment")
	_check(bool(door_alignment.reached),"Ichiraku rear doorway can be reached from the kitchen",door_alignment)
	var rear:=await _walk_to(_ichiraku_local(Vector3(2.72,6.80,.005)),140,"ichiraku_rear_door_exit")
	_check(bool(rear.reached) and player.position.x>24.5 and player.is_on_floor() and absf(player.position.y-.205)<.065 and _body_overlaps().is_empty(),
		"Ichiraku rear doorway and ramp open onto the real market ground",rear)
	var back_inside:=await _walk_to(_ichiraku_local(Vector3(2.72,3.20,.1215)),140,"ichiraku_rear_door_return")
	var end_alignment:=await _walk_to(_ichiraku_local(Vector3(3.18,2.80,.1215)),100,"ichiraku_exit_aisle_alignment")
	var front_exit:=await _walk_to(_ichiraku_local(Vector3(3.18,-5,.005)),240,"ichiraku_front_exit")
	_check(bool(back_inside.reached) and bool(end_alignment.reached) and bool(front_exit.reached) and player.position.x<14 and _body_overlaps().is_empty(),
		"Both Ichiraku door routes permit a complete return to the street",front_exit)
	# Seat spacing leaves 0.507m between cushions, below the capsule's 0.62m
	# diameter. Test the solid cushion directly, keeping the intended end aisle separate.
	await _settle(_ichiraku_local(Vector3(.075,-3,.04)))
	var stool_start: Dictionary={"position":_vec(player.position),"on_floor":player.is_on_floor(),"overlaps":_body_overlaps()}
	_check(player.is_on_floor() and _body_overlaps().is_empty(),"Ichiraku stool test starts on unobstructed street ground",stool_start)
	var stool:=await _move(Vector3.RIGHT,90,"ichiraku_stool_contact")
	var seat_center:=_ichiraku_local(Vector3(.075,.20,.732))
	var seat_distance:=Vector2(player.position.x-seat_center.x,player.position.z-seat_center.z).length()
	stool["seat_center"]=_vec(seat_center)
	stool["seat_center_distance_m"]=seat_distance
	_check(seat_distance>.54 and seat_distance<.65 and float(stool.progress_along_input_m)>2.3 and float(stool.progress_along_input_m)<2.9 and not stool.side_contacts.is_empty(),
		"Ichiraku stool cushion stays solid to the walking capsule",stool)
	var stool_retreat:=await _move(Vector3.LEFT,60,"ichiraku_stool_retreat")
	_check(float(stool_retreat.progress_along_input_m)>3.4 and player.position.x<14.5,
		"Ichiraku stool contact does not trap the player",stool_retreat)
	await _stop()

func _market_lanes() -> void:
	var metadata: Dictionary=world.meta.districts
	_check(int(metadata.count)==metadata.buildings.size() and int(metadata.count)>=550 and int(metadata.faces)<=900000,
		"Current district metadata describes the denser bounded-geometry village",
		{"buildings":metadata.count,"faces":metadata.faces,"market_walkways":metadata.get("market_walkways",[])})
	for lane: Dictionary in [{"name":"front","x":15.0},{"name":"rear","x":30.0}]:
		await _settle(Vector3(lane.x,.24,129.0))
		var initial_clear:=player.is_on_floor() and _body_overlaps().is_empty()
		var route:=await _walk_to(Vector3(lane.x,.24,203.0),1250,"market_"+str(lane.name)+"_lane")
		_check(initial_clear and bool(route.reached) and player.is_on_floor() and _body_overlaps().is_empty(),
			"Curated market %s lane permits 74m of continuous walking" % lane.name,route)

func _arena() -> void:
	world.visit_bookmark(3)
	player.enabled = true
	await _frames(45)
	var entry := await _move(Vector3.FORWARD,690,"arena_entrance_to_floor")
	_check(player.position.z< -90 and absf(player.position.x+225)<.10 and player.is_on_floor() and float(entry.height_range_m[1])<.25,"Arena entrance passage reaches the open fighting floor",entry)
	var transverse := await _move(Vector3.RIGHT,225,"arena_floor_crossing")
	_check(float(transverse.progress_along_input_m)>14.4 and player.is_on_floor(),"Arena fighting floor supports unobstructed lateral walking",transverse)
	await _stop()

func _academy_and_tower() -> void:
	world.visit_bookmark(4)
	player.enabled = true
	await _frames(45)
	var yard := await _move(Vector3.FORWARD,510,"academy_gate_and_schoolyard")
	_check(player.position.z< -156 and absf(player.position.x+92)<.12 and player.is_on_floor(),"Academy gate gives physical access to the schoolyard",yard)
	var doorway := await _move(Vector3.FORWARD,240,"academy_entrance_passage")
	_check(player.position.z< -169 and player.is_on_floor(),"Academy entrance permits walking beneath its advertised 3.2m opening",doorway)
	await _stop()
	world.visit_bookmark(2)
	player.enabled = true
	await _frames(45)
	var plaza := await _move(Vector3.FORWARD,360,"tower_plaza_to_steps")
	_check(player.position.z< -197 and player.position.z> -201 and player.is_on_floor(),"Tower bookmark has grounded access across the entrance plaza",plaza)
	await _stop()

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args():
		printerr("World physics QA requires explicit --qa.")
		quit(2)
		return
	var source_hashes_at_start := {}
	for resource_path: String in ["res://scripts/main.gd","res://scripts/player.gd","res://assets/village_v3.json","res://assets/village_v3.glb"]:
		source_hashes_at_start[resource_path]=FileAccess.get_sha256(resource_path)
	world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	player=world.player
	_check(is_instance_valid(player) and world.ready_ms>0,"Actual main scene finishes initialization",{"ready_ms":world.ready_ms,"mesh_instances":world.world_meshes,"world_triangles":world.world_faces,"native_trees":world.trees.size()})
	_check(player.qa_set_input(Vector2.ZERO),"Controller accepts its explicit QA input interface")
	var plateau_probes: Array=[]
	for zz in [-325.0,-330.0,-335.0,-340.0,-345.0,-350.0]:
		var probe := _ground(Vector3(0,200,zz),250)
		probe["x"]=0;probe["z"]=zz
		plateau_probes.append(probe)
	evidence.overlook_safe_ground_probes=plateau_probes

	await _find_safe_overlook()
	await _bookmarks()
	await _gate_route()
	await _house_wall()
	await _ichiraku()
	await _market_lanes()
	await _arena()
	await _academy_and_tower()
	var routes_finite := true
	var no_teleport_spikes := true
	for value: Variant in evidence.values():
		if value is Dictionary and value.has("finite"):
			routes_finite=routes_finite and value.finite
			no_teleport_spikes=no_teleport_spikes and float(value.peak_single_frame_motion_m)<.55
	_check(routes_finite,"All recorded world routes remain finite")
	_check(no_teleport_spikes,"No walking route contains an unexpected teleport or large physics jump")
	var failed: Array = []
	for check: Dictionary in checks:
		if not check.passed: failed.append(check.name)
	var source_hashes := {}
	for resource_path: String in ["res://scripts/main.gd","res://scripts/player.gd","res://assets/village_v3.json","res://assets/village_v3.glb"]:
		source_hashes[resource_path]=FileAccess.get_sha256(resource_path)
	var output := {"source_sha256":source_hashes_at_start,"source_sha256_at_finish":source_hashes,
		"source_changed_during_run":source_hashes_at_start!=source_hashes,"suite":"integrated_world_physics","mode":"headless Godot actual main scene, fixed 60Hz, --qa only",
		"godot":Engine.get_version_info().string,"checked_at_unix":Time.get_unix_time_from_system(),
		"checks":checks,"check_count":checks.size(),"failed_checks":failed,"failure_count":failed.size(),
		"simulated_physics_frames":simulated_frames,"simulated_seconds":simulated_frames/60.0,
		"elapsed_wall_seconds":(Time.get_ticks_usec()-started_usec)/1000000.0,"evidence":evidence,
		"limitations":"Physical route and placement verification only; no visual or GPU performance claim."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULT_PATH).get_base_dir())
	var file := FileAccess.open(RESULT_PATH,FileAccess.WRITE)
	if file==null:
		printerr("Cannot write world physics results: ",FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify(output,"\t"))
	file.close()
	print("WORLD_PHYSICS_RESULT ",JSON.stringify({"checks":checks.size(),"failures":failed.size(),"failed":failed,"result":ProjectSettings.globalize_path(RESULT_PATH)}))
	quit(0 if failed.is_empty() else 1)
