@tool
extends SceneTree

const Plugin := preload("res://addons/rule_engine/plugin.gd")
const Service := preload("res://addons/rule_engine/editor/rule_command_service.gd")


func _init() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	await create_timer(1.0).timeout
	if not Engine.is_editor_hint():
		printerr("Rule command service check was not launched in editor mode.")
		quit(1)
		return
	var plugin: EditorPlugin = Plugin.new()
	plugin._enter_tree()
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var service: Variant = Service.new(manager, _persist)
	var rule := RERule.new()
	rule.id = &"before"
	var failed := false
	if not service.set_rule_id(rule, &"after") or rule.id != &"after":
		printerr("Editor manager did not execute the command service do operation.")
		failed = true
	var history := manager.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	history.undo()
	if rule.id != &"before":
		printerr("Editor manager did not execute the command service undo operation.")
		failed = true
	history.redo()
	if rule.id != &"after":
		printerr("Editor manager did not execute the command service redo operation.")
		failed = true
	plugin._exit_tree()
	plugin.free()
	if failed:
		quit(1)
		return
	print("EDITOR_RULE_COMMAND_SERVICE_CHECK: PASS")
	quit()


func _persist(_resource: Resource) -> void:
	pass
