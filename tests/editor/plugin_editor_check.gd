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
	if not plugin._has_main_screen():
		printerr("Rule Engine plugin did not register a main screen.")
		failed = true
	if plugin._get_plugin_name() != "Rules":
		printerr("Rule Engine plugin main-screen name was not Rules.")
		failed = true
	if not plugin.has_method("get_rules_workspace"):
		printerr("Rule Engine plugin did not expose its workspace lifecycle state.")
		failed = true
	for cycle: int in 2:
		plugin._enter_tree()
		plugin._enter_tree()
		var workspace: Control = (
			plugin.call("get_rules_workspace") as Control
			if plugin.has_method("get_rules_workspace")
			else null
		)
		if (
			workspace == null
			or workspace.get_parent() != plugin.get_editor_interface().get_editor_main_screen()
		):
			printerr("Rule Engine plugin did not create exactly one attached Control workspace.")
			failed = true
		else:
			for required_path: NodePath in [
				^"Layout/BrowserPane/Search",
				^"Layout/BrowserPane/BookTree",
				^"Layout/WorkspacePane/RuleFields",
				^"Layout/WorkspacePane/ConditionTree",
				^"Layout/WorkspacePane/ActionList",
				^"Layout/WorkspacePane/IssueTree",
			]:
				if not workspace.has_node(required_path):
					printerr("Rules workspace was missing %s." % required_path)
					failed = true
			plugin._make_visible(true)
			if not workspace.visible:
				printerr("Rule Engine plugin did not show its workspace.")
				failed = true
			plugin._make_visible(false)
			if workspace.visible:
				printerr("Rule Engine plugin did not hide its workspace.")
				failed = true
		var condition_names: Array = plugin.get_discovered_conditions().map(
			func(entry: Dictionary) -> StringName: return entry.name
		)
		if not condition_names.has(&"RETestGrandchildCondition"):
			printerr("Rule Engine plugin did not discover a transitive custom condition.")
			failed = true
		var non_tool_entry: Dictionary = {}
		for entry: Dictionary in plugin.get_discovered_conditions():
			if entry.name == &"RETestNonToolCondition":
				non_tool_entry = entry
				break
		if non_tool_entry.is_empty() or non_tool_entry.warning.is_empty():
			printerr("Rule Engine plugin did not surface the non-@tool extension warning.")
			failed = true
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
		if plugin.has_method("get_rules_workspace") and plugin.call("get_rules_workspace") != null:
			printerr("Rule Engine plugin retained its workspace after exit.")
			failed = true
		if workspace != null and is_instance_valid(workspace):
			printerr("Rule Engine plugin did not free its workspace after exit.")
			failed = true
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
