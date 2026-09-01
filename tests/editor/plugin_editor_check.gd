@tool
extends SceneTree

const AUTOLOAD_SETTING := "autoload/Rules"
const AUTOLOAD_PATH := "res://addons/rule_engine/runtime/rules.gd"
const Plugin := preload("res://addons/rule_engine/plugin.gd")


func _init() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	await create_timer(1.0).timeout
	var failed := false
	if not Engine.is_editor_hint():
		printerr("Plugin lifecycle check was not launched in editor mode.")
		quit(1)
		return
	var plugin: EditorPlugin = Plugin.new()
	for cycle: int in 2:
		plugin._enter_tree()
		plugin._enter_tree()
		plugin._enable_plugin()
		plugin._enable_plugin()
		await process_frame
		if not _autoload_points_to_runtime():
			printerr(
				"Rule Engine plugin installed an unexpected Rules autoload in cycle %d: %s"
				% [cycle, ProjectSettings.get_setting(AUTOLOAD_SETTING, "<missing>")]
			)
			failed = true
		plugin._disable_plugin()
		plugin._disable_plugin()
		plugin._exit_tree()
		plugin._exit_tree()
		await process_frame
		if ProjectSettings.has_setting(AUTOLOAD_SETTING):
			printerr("Rule Engine plugin left a stale Rules autoload after cycle %d." % cycle)
			failed = true
	plugin.free()
	if ProjectSettings.has_setting(AUTOLOAD_SETTING):
		ProjectSettings.set_setting(AUTOLOAD_SETTING, null)
		ProjectSettings.save()
	if failed:
		quit(1)
		return
	print("EDITOR_PLUGIN_LIFECYCLE_CHECK: PASS")
	quit()


func _autoload_points_to_runtime() -> bool:
	if not ProjectSettings.has_setting(AUTOLOAD_SETTING):
		return false
	var path := String(ProjectSettings.get_setting(AUTOLOAD_SETTING)).trim_prefix("*")
	if path == AUTOLOAD_PATH:
		return true
	if path.begins_with("uid://"):
		return ResourceUID.get_id_path(ResourceUID.text_to_id(path)) == AUTOLOAD_PATH
	return false
