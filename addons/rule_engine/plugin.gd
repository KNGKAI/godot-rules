@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Rules"
const AUTOLOAD_PATH := "res://addons/rule_engine/runtime/rules.gd"
const INSPECTOR_PLUGIN_PATH := "res://addons/rule_engine/editor/inspector/rule_inspector_plugin.gd"
const EXPORT_PLUGIN_PATH := "res://addons/rule_engine/editor/export_plugin.gd"
const TYPE_REGISTRY_PATH := "res://addons/rule_engine/editor/registry/type_registry.gd"

var _inspector_plugin: EditorInspectorPlugin
var _export_plugin: EditorExportPlugin
var _condition_types: Array[Dictionary] = []
var _action_types: Array[Dictionary] = []


func _enter_tree() -> void:
	if _inspector_plugin == null:
		_refresh_extension_registry()
		_inspector_plugin = load(INSPECTOR_PLUGIN_PATH).new()
		add_inspector_plugin(_inspector_plugin)
	if _export_plugin == null:
		_export_plugin = load(EXPORT_PLUGIN_PATH).new()
		add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	_condition_types.clear()
	_action_types.clear()


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


func get_discovered_conditions() -> Array[Dictionary]:
	return _condition_types.duplicate()


func get_discovered_actions() -> Array[Dictionary]:
	return _action_types.duplicate()


func _refresh_extension_registry() -> void:
	var registry: Variant = load(TYPE_REGISTRY_PATH).new()
	_condition_types = registry.discover(&"RECondition")
	_action_types = registry.discover(&"REAction")
	for entry: Dictionary in _condition_types + _action_types:
		if not entry.warning.is_empty():
			push_warning(entry.warning)
