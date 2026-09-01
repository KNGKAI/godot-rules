extends SceneTree

const ROOTS := [
	"res://addons/rule_engine/runtime",
	"res://addons/rule_engine/resources",
]
const FORBIDDEN_TOKENS := ["Editor", "/editor/"]


func _init() -> void:
	var scripts: PackedStringArray = []
	for root: String in ROOTS:
		_collect_scripts(root, scripts)
	var failures: PackedStringArray = []
	for path: String in scripts:
		var script := ResourceLoader.load(path, "Script")
		if script == null:
			failures.append("could not parse %s" % path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("could not read %s" % path)
			continue
		var source := file.get_as_text()
		for token: String in FORBIDDEN_TOKENS:
			if source.contains(token):
				failures.append("%s contains forbidden editor dependency token '%s'" % [path, token])
	if failures.is_empty():
		print("RUNTIME_BOUNDARY_CHECK: PASS (%d scripts)" % scripts.size())
		quit()
		return
	for failure: String in failures:
		printerr("RUNTIME_BOUNDARY_CHECK: %s" % failure)
	quit(1)


func _collect_scripts(path: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child_path := path.path_join(entry)
		if directory.current_is_dir():
			_collect_scripts(child_path, output)
		elif entry.ends_with(".gd"):
			output.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
