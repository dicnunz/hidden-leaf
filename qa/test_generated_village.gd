extends SceneTree

const VillageWorld = preload("res://scripts/village_world.gd")
const Player = preload("res://scripts/player.gd")
const OUTPUT_PATH := "res://.build/generated-village.json"

var village: Node3D
var player: CharacterBody3D
var checks: Array[Dictionary]=[]
var failures: Array[String]=[]
var simulated_frames:=0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String, evidence: Variant=null) -> void:
	checks.append({"name":label,"passed":condition,"evidence":evidence})
	if condition:print("GENERATED_VILLAGE PASS ",label)
	else:failures.append(label);printerr("GENERATED_VILLAGE FAIL ",label," ",evidence)

func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame
		simulated_frames+=1

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x,.0001),snappedf(value.y,.0001),snappedf(value.z,.0001)]

func _horizontal_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func _settle(position: Vector3) -> Dictionary:
	player.teleport_to(position)
	player.enabled=true
	player.qa_set_input(Vector2.ZERO)
	var start:=player.global_position
	await _frames(90)
	return {"requested":_vec(position),"start":_vec(start),"settled":_vec(player.global_position),
		"horizontal_drift_m":_horizontal_distance(start,player.global_position),
		"vertical_change_m":player.global_position.y-start.y,"on_floor":player.is_on_floor()}

func _walk_to(target: Vector3, frame_limit: int) -> Dictionary:
	var start:=player.global_position
	var previous:=start
	var trace: Array=[_vec(start)]
	var blocked_frames:=0
	var blocked_events:=0
	var blocked_streak:=0
	var blocked_event_open:=false
	var off_floor_frames:=0
	var side_contact_frames:=0
	var frames:=0
	var distance_walked:=0.0
	for frame in range(frame_limit):
		var offset:=target-player.global_position;offset.y=0
		var residual:=offset.length()
		if residual<.18 and Vector2(player.velocity.x,player.velocity.z).length()<.12:break
		var direction:=offset.normalized() if residual>.001 else Vector3.ZERO
		var local_direction: Vector3=player.global_basis.inverse()*direction
		player.qa_set_input(Vector2(local_direction.x,local_direction.z)*minf(1.0,residual*1.7))
		await _frames(1);frames+=1
		var moved:=_horizontal_distance(previous,player.global_position)
		distance_walked+=moved;previous=player.global_position
		var blocked_now:=residual>.75 and moved<.001 and Vector2(player.velocity.x,player.velocity.z).length()<.10
		if blocked_now:
			blocked_frames+=1;blocked_streak+=1
			if blocked_streak>=60 and not blocked_event_open:blocked_events+=1;blocked_event_open=true
		else:
			blocked_streak=0;blocked_event_open=false
		if not player.is_on_floor():off_floor_frames+=1
		var side_contact:=false
		for collision_index in range(player.get_slide_collision_count()):
			var collision:=player.get_slide_collision(collision_index)
			if absf(collision.get_normal().y)<.65:side_contact=true
		if side_contact:side_contact_frames+=1
		if frames%60==0:trace.append(_vec(player.global_position))
	player.qa_set_input(Vector2.ZERO)
	await _frames(20)
	var final_residual:=_horizontal_distance(player.global_position,target)
	trace.append(_vec(player.global_position))
	return {"start":_vec(start),"target":_vec(target),"end":_vec(player.global_position),"frames":frames,
		"distance_walked_m":distance_walked,"residual_m":final_residual,"reached":final_residual<.45,
		"blocked_frames":blocked_frames,"blocked_events_1s":blocked_events,"off_floor_frames":off_floor_frames,"side_contact_frames":side_contact_frames,
		"on_floor_at_end":player.is_on_floor(),"height_change_m":player.global_position.y-start.y,"trace":trace}

func _validate_roles() -> Dictionary:
	var by_name: Dictionary={}
	var mesh_nodes: Array[Node]=village.geometry.find_children("*","MeshInstance3D",true,false)
	for node: Node in mesh_nodes:
		var name_text:=str(node.name)
		if not by_name.has(name_text):by_name[name_text]=[]
		by_name[name_text].append(node)
	var missing: Array=[];var duplicate: Array=[];var invalid_aabbs: Array=[];var invalid_materials: Array=[]
	for role_name: String in village.meta.mesh_roles:
		var matches: Array=by_name.get(role_name,[])
		if matches.is_empty():missing.append(role_name);continue
		if matches.size()!=1:duplicate.append({"role":role_name,"matches":matches.size()});continue
		var mesh_node:=matches[0] as MeshInstance3D
		var aabb:=mesh_node.mesh.get_aabb()
		if not aabb.position.is_finite() or not aabb.size.is_finite() or aabb.size.x<0 or aabb.size.y<0 or aabb.size.z<0:
			invalid_aabbs.append({"role":role_name,"position":_vec(aabb.position),"size":_vec(aabb.size)})
		for surface in range(mesh_node.mesh.get_surface_count()):
			var source:=mesh_node.mesh.surface_get_material(surface)
			var override:=mesh_node.get_surface_override_material(surface)
			var source_key:=source.resource_name.split(".")[0] if source!=null else ""
			var valid: bool=source!=null and not source_key.is_empty() and village.meta.materials.has(source_key) and override!=null
			if override is ShaderMaterial:valid=valid and (override as ShaderMaterial).shader!=null
			if not valid:invalid_materials.append({"role":role_name,"surface":surface,"source":source_key,
				"override_class":override.get_class() if override!=null else ""})
	var unassigned: Array=[]
	for name_text: String in by_name:
		if not village.meta.mesh_roles.has(name_text):unassigned.append(name_text)
	return {"role_count":village.meta.mesh_roles.size(),"mesh_instance_count":mesh_nodes.size(),
		"missing_roles":missing,"duplicate_roles":duplicate,"unassigned_mesh_names":unassigned,
		"invalid_aabbs":invalid_aabbs,"invalid_material_links":invalid_materials}

func _validate_collisions() -> Dictionary:
	var invalid_metadata: Array=[]
	for index in range(village.meta.colliders.size()):
		var item: Dictionary=village.meta.colliders[index]
		var position:=VillageWorld.vector(item.position)
		var valid:=position.is_finite()
		if item.shape=="cylinder":valid=valid and is_finite(float(item.radius)) and is_finite(float(item.height)) and float(item.radius)>.001 and float(item.height)>.001
		else:
			var size:=VillageWorld.vector(item.size)
			valid=valid and size.is_finite() and size.x>.001 and size.y>.001 and size.z>.001
		if not valid:invalid_metadata.append(index)
	var invalid_runtime: Array=[]
	var runtime_shapes:=village.find_children("*","CollisionShape3D",true,false)
	for shape_node: Node in runtime_shapes:
		var shape: Shape3D=(shape_node as CollisionShape3D).shape
		var valid:=shape!=null
		if shape is BoxShape3D:
			var size: Vector3=(shape as BoxShape3D).size
			valid=size.is_finite() and size.x>.001 and size.y>.001 and size.z>.001
		elif shape is CylinderShape3D:
			valid=is_finite((shape as CylinderShape3D).radius) and is_finite((shape as CylinderShape3D).height) and (shape as CylinderShape3D).radius>.001 and (shape as CylinderShape3D).height>.001
		elif shape is ConcavePolygonShape3D:
			var faces: PackedVector3Array=(shape as ConcavePolygonShape3D).get_faces()
			valid=not faces.is_empty()
			for vertex: Vector3 in faces:valid=valid and vertex.is_finite()
		if not valid:invalid_runtime.append(str(village.get_path_to(shape_node)))
	return {"metadata_colliders":village.meta.colliders.size(),"runtime_collision_shapes":runtime_shapes.size(),
		"invalid_metadata_colliders":invalid_metadata,"invalid_runtime_shapes":invalid_runtime}

func _run() -> void:
	if not "--qa" in OS.get_cmdline_user_args():
		printerr("Generated village QA requires explicit --qa.");quit(2);return
	var source_hashes:={"world":FileAccess.get_sha256("res://scripts/village_world.gd"),
		"player":FileAccess.get_sha256("res://scripts/player.gd"),"metadata":FileAccess.get_sha256("res://assets/villages/sand.json"),
		"geometry":FileAccess.get_sha256("res://assets/villages/sand.glb")}
	village=VillageWorld.new();root.add_child(village);village.construct("sand")
	await _frames(3)
	var roles:=_validate_roles()
	_check(roles.missing_roles.is_empty() and roles.duplicate_roles.is_empty(),"Every mesh role resolves to exactly one actual MeshInstance3D",roles)
	_check(roles.invalid_aabbs.is_empty(),"Generated mesh AABBs are finite",roles.invalid_aabbs)
	_check(roles.invalid_material_links.is_empty(),"Every generated surface has a valid metadata-backed runtime material",roles.invalid_material_links)
	_check(roles.unassigned_mesh_names.is_empty(),"Every imported Sand mesh has a declared role",roles.unassigned_mesh_names)
	var collisions:=_validate_collisions()
	_check(collisions.invalid_metadata_colliders.is_empty() and collisions.invalid_runtime_shapes.is_empty(),"Metadata and runtime collision shapes have nondegenerate finite dimensions",collisions)
	player=Player.new();village.add_child(player);await _frames(2)
	var spawn_position:=VillageWorld.vector(village.meta.bookmarks[0].position)+Vector3.UP*.13
	var spawn:=await _settle(spawn_position)
	_check(spawn.on_floor and float(spawn.horizontal_drift_m)<.03 and absf(float(spawn.vertical_change_m))<.35,"Sand avenue spawn settles stably on physical ground",spawn)
	var avenue:=await _walk_to(Vector3(0,.25,10),1200)
	_check(avenue.reached and avenue.on_floor_at_end and int(avenue.blocked_events_1s)==0,"Controller walks 62m along the central Sand avenue",avenue)
	var side_spawn:=await _settle(Vector3(-24.5,.25,66))
	var side_lane:=await _walk_to(Vector3(-24.5,.25,5),1200)
	_check(side_spawn.on_floor and side_lane.reached and side_lane.on_floor_at_end and int(side_lane.blocked_events_1s)==0,"Controller traverses the longitudinal side lane between tower columns",side_lane)
	var stair_spawn:=await _settle(Vector3(59,.25,52))
	var terrace:=await _walk_to(Vector3(59,1.25,46),360)
	_check(stair_spawn.on_floor and terrace.reached and terrace.on_floor_at_end and float(terrace.height_change_m)>.85 and int(terrace.blocked_events_1s)==0,"Controller climbs the authored eight-step service terrace route",terrace)
	var end_hashes:={"world":FileAccess.get_sha256("res://scripts/village_world.gd"),
		"player":FileAccess.get_sha256("res://scripts/player.gd"),"metadata":FileAccess.get_sha256("res://assets/villages/sand.json"),
		"geometry":FileAccess.get_sha256("res://assets/villages/sand.glb")}
	_check(source_hashes==end_hashes,"Village QA leaves source inputs unchanged",{"start":source_hashes,"end":end_hashes})
	var output:={"godot":Engine.get_version_info().string,"village":"sand","mode":"headless fixed 60Hz actual generated world and controller",
		"checks":checks,"failure_count":failures.size(),"failures":failures,"source_sha256":source_hashes,
		"source_changed_during_run":source_hashes!=end_hashes,"simulated_frames":simulated_frames,
		"simulated_seconds":simulated_frames/60.0,"roles":roles,"collisions":collisions,
		"spawn":spawn,"routes":{"avenue":avenue,"side_lane":side_lane,"terrace_stairs":terrace}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH).get_base_dir())
	var file:=FileAccess.open(OUTPUT_PATH,FileAccess.WRITE)
	if file==null:printerr("Cannot write generated village QA: ",FileAccess.get_open_error());quit(2);return
	file.store_string(JSON.stringify(output,"\t"));file.close()
	print("GENERATED_VILLAGE_RESULT ",JSON.stringify({"result":ProjectSettings.globalize_path(OUTPUT_PATH),
		"checks":checks.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
