extends GutTest

const RULES_PATH := "res://addons/rule_engine/runtime/rules.gd"


func test_rules_facade_forwards_max_chain_depth() -> void:
	var rules_script: Script = load(RULES_PATH)
	assert_not_null(rules_script, "rules facade must load")
	if rules_script == null:
		return
	var rules: Node = rules_script.new()
	assert_eq(rules.get(&"max_chain_depth"), 64)
	rules.set(&"max_chain_depth", 3)
	assert_eq(rules.get(&"max_chain_depth"), 3)
	rules.set(&"max_chain_depth", 0)
	assert_eq(rules.get(&"max_chain_depth"), 1)
	rules.free()
