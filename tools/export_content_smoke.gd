extends SceneTree

const ADDON_PATH := "res://addons/rule_engine"


func _init() -> void:
	var addon_directory := DirAccess.open(ADDON_PATH)
	if addon_directory == null or not addon_directory.dir_exists("runtime"):
		printerr("EXPORT_CONTENT_SMOKE: runtime script is missing from the exported pack.")
		quit(1)
		return
	if addon_directory.dir_exists("editor"):
		printerr("EXPORT_CONTENT_SMOKE: forbidden editor directory is present.")
		quit(1)
		return
	print("EXPORT_CONTENT_SMOKE: PASS")
	quit()
