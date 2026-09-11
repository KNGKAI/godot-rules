@tool
extends SceneTree

const AUTOLOAD_SETTING := "autoload/Rules"
const AUTOLOAD_PATH := "res://addons/rule_engine/runtime/rules.gd"
const PLUGIN_CONFIG_PATH := "res://addons/rule_engine/plugin.cfg"
const EMIT_ACTION_PATH := "res://addons/rule_engine/resources/actions/emit_event.gd"
const Plugin := preload("res://addons/rule_engine/plugin.gd")


class FocusController extends RefCounted:
	var _commands: Variant
	var _book: RERuleBook
	var _rule: RERule

	func _init(commands: Variant, book: RERuleBook, rule: RERule) -> void:
		_commands = commands
		_book = book
		_rule = rule

	func get_selected_book() -> RERuleBook:
		return _book

	func get_selected_rule() -> RERule:
		return _rule

	func set_rule_id(value: StringName) -> bool:
		return _commands.set_rule_id(_rule, value)

	func set_rule_event(value: StringName) -> bool:
		return _commands.set_rule_event(_rule, value)

	func set_rule_tags(value: PackedStringArray) -> bool:
		return _commands.set_rule_tags(_rule, value)


class ProjectBookDiscovery extends RefCounted:
	var _books: Array[RERuleBook]

	func _init(books: Array[RERuleBook]) -> void:
		_books = books

	func get_books() -> Array[RERuleBook]:
		return _books.duplicate()


func _init() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	await create_timer(1.0).timeout
	var failed := false
	if not Engine.is_editor_hint():
		printerr("Plugin lifecycle check was not launched in editor mode.")
		quit(1)
		return
	var plugin_config := ConfigFile.new()
	var enabled_plugins: PackedStringArray = []
	if plugin_config.load("res://project.godot") == OK:
		enabled_plugins = plugin_config.get_value("editor_plugins", "enabled", PackedStringArray())
	if not enabled_plugins.has(PLUGIN_CONFIG_PATH):
		printerr("The project does not enable Rule Engine through its editor plugin manager.")
		failed = true
	var registered_workspace := EditorInterface.get_editor_main_screen().find_child(
		"RulesWorkspace",
		true,
		false,
	) as Control
	if (
		registered_workspace == null
		or registered_workspace.get_parent() != EditorInterface.get_editor_main_screen()
		or registered_workspace.get("_controller") == null
	):
		printerr("The project-enabled Rule Engine plugin manager did not register its Rules workspace.")
		failed = true
	else:
		EditorInterface.set_main_screen_editor("Rules")
		await process_frame
		if not registered_workspace.visible:
			printerr("The project-enabled Rule Engine plugin manager did not open its Rules workspace.")
			failed = true
		var project_book := RERuleBook.new()
		var project_rule := RERule.new()
		project_rule.id = &"project_workspace_smoke"
		project_book.rules = [project_rule]
		var project_controller: Variant = registered_workspace.get("_controller")
		var original_discovery: Variant = project_controller.get("_discovery") if project_controller != null else null
		if project_controller == null:
			printerr("The project-enabled workspace did not expose its controller.")
			failed = true
		else:
			project_controller.set("_discovery", ProjectBookDiscovery.new([project_book]))
			if not project_controller.select_rule(project_rule):
				printerr("The project-enabled workspace could not select its smoke Rule.")
				failed = true
			else:
				if not project_controller.add_action(load(EMIT_ACTION_PATH)):
					printerr("The project-enabled workspace could not perform a structural authoring command.")
					failed = true
				else:
					var project_commands: Variant = project_controller.get("_commands")
					var undo_adapter: Variant = project_commands.get("_undo_redo") if project_commands != null else null
					var project_manager: Variant = undo_adapter.get("_manager") if undo_adapter != null else null
					var project_history: UndoRedo = (
						project_manager.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
						if project_manager != null
						else null
					)
					if project_history == null:
						printerr("The project-enabled workspace did not expose its editor undo history.")
						failed = true
					else:
						project_history.undo()
						if not project_rule.actions.is_empty():
							printerr("The project-enabled workspace could not undo its structural authoring command.")
							failed = true
						project_history.redo()
						if project_rule.actions.size() != 1:
							printerr("The project-enabled workspace could not redo its structural authoring command.")
							failed = true
			project_controller.set("_discovery", original_discovery)
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
	if not plugin.has_method("get_rules_command_service"):
		printerr("Rule Engine plugin did not expose its authoring service lifecycle state.")
		failed = true
	var retained_rules: Array[RERule] = []
	var retained_services: Array = []
	var retained_histories: Array[UndoRedo] = []
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
				^"Layout/WorkspacePane/ConditionToolbar/AppendChild",
				^"Layout/WorkspacePane/ActionList",
				^"Layout/WorkspacePane/IssueTree",
				^"Layout/WorkspacePane/StatusLabel",
				^"RuleSaveDialog",
			]:
				if not workspace.has_node(required_path):
					printerr("Rules workspace was missing %s." % required_path)
					failed = true
			var save_dialog := workspace.get_node_or_null(^"RuleSaveDialog")
			if not save_dialog is EditorFileDialog:
				printerr("Rules workspace did not use the editor-native EditorFileDialog.")
				failed = true
			plugin._make_visible(true)
			if not workspace.visible:
				printerr("Rule Engine plugin did not show its workspace.")
				failed = true
			plugin._make_visible(false)
			if workspace.visible:
				printerr("Rule Engine plugin did not hide its workspace.")
				failed = true
			var authored_rule := RERule.new()
			authored_rule.id = &"before_focus"
			var book := RERuleBook.new()
			book.rules = [authored_rule]
			var existing_controller: Variant = workspace.get("_controller")
			var focus_controller := FocusController.new(
				plugin.get_rules_command_service(),
				book,
				authored_rule,
			)
			workspace.set("_controller", focus_controller)
			for field_case: Array in [
				["_id_field", "id", "after_focus", &"after_focus"],
				["_event_field", "event", "event_focus", &"event_focus"],
				["_tags_field", "tags", "alpha, beta", PackedStringArray(["alpha", "beta"])],
			]:
				var field: LineEdit = workspace.get(field_case[0]) as LineEdit
				if field == null:
					printerr("Rules workspace did not expose %s for focus-loss authoring." % field_case[0])
					failed = true
					continue
				var before: Variant = authored_rule.get(field_case[1])
				field.text = field_case[2]
				field.focus_exited.emit()
				if authored_rule.get(field_case[1]) != field_case[3]:
					printerr("Rules workspace did not commit %s on focus loss." % field_case[1])
					failed = true
					continue
				field.text_submitted.emit(field.text)
				var history := plugin.get_undo_redo().get_history_undo_redo(
					EditorUndoRedoManager.GLOBAL_HISTORY
				)
				history.undo()
				if authored_rule.get(field_case[1]) != before:
					printerr("Rules workspace created duplicate undo for %s submit after focus loss." % field_case[1])
					failed = true
				history.redo()
			workspace.set("_controller", existing_controller)
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
		var command_service: Variant = (
			plugin.call("get_rules_command_service")
			if plugin.has_method("get_rules_command_service")
			else null
		)
		var authored_rule := RERule.new()
		authored_rule.id = &"before_teardown"
		if command_service == null or not command_service.set_rule_id(
			authored_rule,
			&"after_authoring",
		):
			printerr("Rule Engine plugin could not perform a real authoring command.")
			failed = true
		else:
			if not command_service.add_action(authored_rule, load(EMIT_ACTION_PATH)):
				printerr("Rule Engine plugin could not perform a structural authoring command.")
				failed = true
			else:
				var structural_history := plugin.get_undo_redo().get_history_undo_redo(
					EditorUndoRedoManager.GLOBAL_HISTORY
				)
				structural_history.undo()
				if not authored_rule.actions.is_empty():
					printerr("Rule Engine plugin could not undo a structural authoring command.")
					failed = true
				structural_history.redo()
				if authored_rule.actions.size() != 1:
					printerr("Rule Engine plugin could not redo a structural authoring command.")
					failed = true
			retained_rules.append(authored_rule)
			retained_services.append(command_service)
			var history_manager := plugin.get_undo_redo()
			var history_id := history_manager.get_object_history_id(command_service)
			retained_histories.append(history_manager.get_history_undo_redo(history_id))
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
		if command_service != null and (
			not command_service.has_method("is_shutdown")
			or not command_service.is_shutdown()
		):
			printerr("Rule Engine plugin retained an active authoring service after exit.")
			failed = true
	plugin.free()
	await process_frame
	if not retained_histories.is_empty():
		for index: int in range(retained_histories.size() - 1, -1, -1):
			retained_histories[index].undo()
		for rule: RERule in retained_rules:
			if rule.id != &"after_authoring":
				printerr("A retained undo callback mutated authored data after plugin teardown.")
				failed = true
		for retained_history: UndoRedo in retained_histories:
			retained_history.redo()
		for rule: RERule in retained_rules:
			if rule.id != &"after_authoring":
				printerr("A retained redo callback mutated authored data after plugin teardown.")
				failed = true
	retained_services.clear()
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
