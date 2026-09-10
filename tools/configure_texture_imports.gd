extends SceneTree

## Run after the first Godot import, then import again. Runtime-created materials
## do not reliably trigger the editor's automatic 3D texture detection.
var changed := 0
var checked := 0
var failures: Array[String] = []

func _initialize() -> void:
	_visit("res://assets/textures")
	_visit("res://assets/vegetation")
	_configure("res://assets/sky.hdr.import")
	print("TEXTURE_IMPORT_PROFILE ", JSON.stringify({"checked":checked,"changed":changed,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _visit(directory: String) -> void:
	for folder in DirAccess.get_directories_at(directory):
		_visit(directory.path_join(folder))
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".import"):
			_configure(directory.path_join(filename))

func _configure(path: String) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		failures.append("Cannot read " + path)
		return
	# Leave model importers and layered lightmap textures alone.
	if config.get_value("remap", "importer", "") != "texture":return
	checked += 1
	var required := {"compress/mode":2, "mipmaps/generate":true}
	if "_nor_gl_" in path or "_normal." in path:
		required["compress/normal_map"] = 1
	var dirty := false
	for key in required:
		if config.get_value("params", key, null) != required[key]:
			config.set_value("params", key, required[key])
			dirty = true
	if dirty:
		if config.save(path) == OK:changed += 1
		else:failures.append("Cannot update " + path)
