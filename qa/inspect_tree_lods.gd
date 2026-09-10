extends SceneTree

const OUTPUT_PATH := "res://.build/tree-lods.json"
const LODS := ["near","mid","far","distant","horizon"]

func _initialize() -> void:
	call_deferred("_run")

func _primitive_name(value: Mesh.PrimitiveType) -> String:
	return ["points","lines","line_strip","triangles","triangle_strip"][int(value)]

func _primitive_count(kind: Mesh.PrimitiveType, element_count: int) -> int:
	match kind:
		Mesh.PRIMITIVE_POINTS:return element_count
		Mesh.PRIMITIVE_LINES:return element_count/2
		Mesh.PRIMITIVE_LINE_STRIP:return maxi(0,element_count-1)
		Mesh.PRIMITIVE_TRIANGLES:return element_count/3
		Mesh.PRIMITIVE_TRIANGLE_STRIP:return maxi(0,element_count-2)
	return 0

func _material_detail(material: Material) -> Dictionary:
	if material==null:
		return {"valid":false,"class":"","name":"","alpha":false,"alpha_reason":"missing"}
	var alpha:=false
	var reason:="opaque"
	var alpha_texture:=false
	var albedo_texture_path:=""
	var runtime_transparency_enabled:=false
	var runtime_canopy_alpha:=false
	if material is BaseMaterial3D:
		var base:=material as BaseMaterial3D
		if base.albedo_texture!=null:
			albedo_texture_path=base.albedo_texture.resource_path
			var image:=base.albedo_texture.get_image()
			alpha_texture=image!=null and image.detect_alpha()!=Image.ALPHA_NONE
		if base.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:
			alpha=true;runtime_transparency_enabled=true;reason="transparency_%d"%base.transparency
		elif base.albedo_color.a<.999:
			alpha=true;reason="albedo_alpha"
		elif alpha_texture:
			alpha=true;reason="albedo_texture_has_alpha_but_transparency_is_disabled"
	elif material is ShaderMaterial:
		var shader: Shader=(material as ShaderMaterial).shader
		if shader!=null and shader.code.contains("ALPHA"):
			alpha=true;reason="shader_alpha"
	# The GLBs intentionally carry lightweight placeholder materials. The actual
	# world replaces a surface named "leaves" with canopy.gdshader, which writes
	# ALPHA. Report that effective runtime alpha contract alongside raw GLB state.
	if material.resource_name.to_lower().contains("leaves"):
		var canopy:=load("res://scripts/canopy.gdshader") as Shader
		runtime_canopy_alpha=canopy!=null and canopy.code.contains("ALPHA")
		if runtime_canopy_alpha:alpha=true;reason="runtime_canopy_shader_alpha"
	return {"valid":true,"class":material.get_class(),"name":material.resource_name,
		"resource_path":material.resource_path,"alpha":alpha,"alpha_reason":reason,
		"alpha_texture":alpha_texture,"albedo_texture_path":albedo_texture_path,
		"runtime_transparency_enabled":runtime_transparency_enabled,"runtime_canopy_alpha":runtime_canopy_alpha}

func _inspect_node(node: Node, scene_root: Node, detail: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance:=node as MeshInstance3D
		var mesh: Mesh=instance.mesh
		var mesh_detail:={"node_path":str(scene_root.get_path_to(instance)),"node_name":str(instance.name),
			"mesh_name":mesh.resource_name if mesh!=null else "","surfaces":[]}
		detail.mesh_instances+=1
		if mesh==null:
			detail.missing_meshes.append(mesh_detail.node_path)
		else:
			var aabb:=mesh.get_aabb()
			mesh_detail["aabb_position"]=[aabb.position.x,aabb.position.y,aabb.position.z]
			mesh_detail["aabb_size"]=[aabb.size.x,aabb.size.y,aabb.size.z]
			for surface_index in range(mesh.get_surface_count()):
				var arrays: Array=mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				var elements:=indices.size() if not indices.is_empty() else vertices.size()
				var primitive_type: Mesh.PrimitiveType=mesh.surface_get_primitive_type(surface_index)
				var material:=mesh.surface_get_material(surface_index)
				var material_detail:=_material_detail(material)
				var primitives:=_primitive_count(primitive_type,elements)
				var surface:={"surface":surface_index,"primitive_type":_primitive_name(primitive_type),
					"vertices":vertices.size(),"indices":indices.size(),"primitives":primitives,
					"material":material_detail}
				mesh_detail.surfaces.append(surface)
				detail.surfaces+=1;detail.vertices+=vertices.size();detail.indices+=indices.size();detail.primitives+=primitives
				if primitive_type==Mesh.PRIMITIVE_TRIANGLES:detail.triangles+=primitives
				if material_detail.alpha:detail.alpha_surfaces+=1
		detail.meshes.append(mesh_detail)
	for child: Node in node.get_children():_inspect_node(child,scene_root,detail)

func _run() -> void:
	var output:={"godot":Engine.get_version_info().string,"lods":[],"totals":{"mesh_instances":0,"surfaces":0,
		"vertices":0,"indices":0,"primitives":0,"triangles":0,"alpha_surfaces":0},"ratios_to_near":[]}
	for lod: String in LODS:
		var path:="res://assets/vegetation/tree_v3_%s.glb"%lod
		var packed:=load(path) as PackedScene
		if packed==null or not packed.can_instantiate():
			printerr("Cannot instantiate tree LOD: ",path);quit(2);return
		var scene:=packed.instantiate()
		var detail:={"lod":lod,"path":path,"file_bytes":FileAccess.get_file_as_bytes(path).size(),
			"mesh_instances":0,"surfaces":0,"vertices":0,"indices":0,"primitives":0,"triangles":0,
			"alpha_surfaces":0,"missing_meshes":[],"meshes":[]}
		_inspect_node(scene,scene,detail)
		scene.free()
		output.lods.append(detail)
		for key: String in output.totals.keys():output.totals[key]+=detail[key]
	var near: Dictionary=output.lods[0]
	for detail: Dictionary in output.lods:
		output.ratios_to_near.append({"lod":detail.lod,
			"triangle_ratio":float(detail.triangles)/maxi(int(near.triangles),1),
			"vertex_ratio":float(detail.vertices)/maxi(int(near.vertices),1),
			"file_size_ratio":float(detail.file_bytes)/maxi(int(near.file_bytes),1)})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH).get_base_dir())
	var file:=FileAccess.open(OUTPUT_PATH,FileAccess.WRITE)
	if file==null:
		printerr("Cannot write tree LOD results: ",FileAccess.get_open_error());quit(2);return
	file.store_string(JSON.stringify(output,"\t"));file.close()
	print("TREE_LOD_RESULT ",JSON.stringify({"result":ProjectSettings.globalize_path(OUTPUT_PATH),
		"totals":output.totals,"ratios_to_near":output.ratios_to_near}))
	quit()
