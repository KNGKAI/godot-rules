@tool
extends EditorExportPlugin

const EDITOR_PREFIX := "res://addons/rule_engine/editor/"


func _get_name() -> String:
	return "RuleEngineRuntimeBoundary"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with(EDITOR_PREFIX):
		skip()
