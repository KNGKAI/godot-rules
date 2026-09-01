extends GutTest

const PLUGIN_PATH := "res://addons/rule_engine/plugin.gd"
const EXPORT_PLUGIN_PATH := "res://addons/rule_engine/editor/export_plugin.gd"
const RULES_PATH := "res://addons/rule_engine/runtime/rules.gd"


func test_plugin_scripts_have_the_expected_editor_base_types() -> void:
	var plugin: Script = load(PLUGIN_PATH)
	var export_plugin: Script = load(EXPORT_PLUGIN_PATH)
	assert_not_null(plugin)
	assert_not_null(export_plugin)
	if plugin != null:
		assert_eq(plugin.get_instance_base_type(), "EditorPlugin")
	if export_plugin != null:
		assert_eq(export_plugin.get_instance_base_type(), "EditorExportPlugin")


func test_plugin_manifest_points_at_the_integration_script() -> void:
	var config := ConfigFile.new()
	assert_eq(config.load("res://addons/rule_engine/plugin.cfg"), OK)
	assert_eq(config.get_value("plugin", "script"), "plugin.gd")
	assert_eq(config.get_value("plugin", "version"), "0.1.0")


func test_rules_facade_delegates_to_one_retained_engine() -> void:
	var rules_script: Script = load(RULES_PATH)
	assert_not_null(rules_script)
	if rules_script == null:
		return
	var rules: Node = rules_script.new()
	var condition := REExistsCondition.new()
	condition.source = REExistsCondition.Source.PAYLOAD
	condition.key = &"mission_id"
	var rule := RERule.new()
	rule.id = &"mission_query"
	rule.condition = condition
	var book := RERuleBook.new()
	book.rules.append(rule)
	assert_eq(rules.call("load_book", book), OK)
	assert_true(rules.call("check", &"mission_query", {&"mission_id": &"first_steps"}))
	assert_same(rules.call("get_rule", &"mission_query"), rule)
	assert_same(rules.call("get_blackboard"), rules.call("get_blackboard"))
	rules.free()
