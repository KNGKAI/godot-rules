@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Rules"
const AUTOLOAD_PATH := "res://addons/rule_engine/runtime/rules.gd"
const InspectorPlugin := preload("editor/inspector/rule_inspector_plugin.gd")
const ExportPlugin := preload("editor/export_plugin.gd")

var _inspector_plugin: EditorInspectorPlugin
var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	if _inspector_plugin == null:
		_inspector_plugin = InspectorPlugin.new()
		add_inspector_plugin(_inspector_plugin)
	if _export_plugin == null:
		_export_plugin = ExportPlugin.new()
		add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/%s" % AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	var setting := "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(setting):
		return
	if _autoload_points_to_runtime(String(ProjectSettings.get_setting(setting))):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _autoload_points_to_runtime(configured_value: String) -> bool:
	var configured_path := configured_value.trim_prefix("*")
	if configured_path == AUTOLOAD_PATH:
		return true
	if configured_path.begins_with("uid://"):
		var resource_id := ResourceUID.text_to_id(configured_path)
		return ResourceUID.get_id_path(resource_id) == AUTOLOAD_PATH
	return false
