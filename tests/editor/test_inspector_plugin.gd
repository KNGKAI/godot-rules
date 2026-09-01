extends GutTest

const INSPECTOR_PATH := "res://addons/rule_engine/editor/inspector/rule_inspector_plugin.gd"
const PROPERTY_PATH := "res://addons/rule_engine/editor/inspector/variant_editor_property.gd"


func test_inspector_plugin_script_has_the_editor_base_type() -> void:
	var script: Script = load(INSPECTOR_PATH)
	assert_not_null(script)
	assert_eq(script.get_instance_base_type(), "EditorInspectorPlugin")


func test_variant_editor_script_has_the_editor_property_base_type() -> void:
	var script: Script = load(PROPERTY_PATH)
	assert_not_null(script)
	assert_eq(script.get_instance_base_type(), "EditorProperty")
