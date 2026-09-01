extends GutTest

const CUSTOM_CONDITION_PATH := "res://tests/fixtures/serialization/custom_condition.gd"
const CUSTOM_ACTION_PATH := "res://tests/fixtures/serialization/custom_action.gd"
const OUTPUT_DIR := "user://rule_engine_round_trip"
const RULE_PATH := OUTPUT_DIR + "/rule.tres"
const BOOK_PATH := OUTPUT_DIR + "/book.tres"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BOOK_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RULE_PATH))


func test_external_rule_round_trip_preserves_nested_behavior_and_order() -> void:
	var custom_condition_script: Script = load(CUSTOM_CONDITION_PATH)
	var custom_action_script: Script = load(CUSTOM_ACTION_PATH)
	assert_not_null(custom_condition_script)
	assert_not_null(custom_action_script)
	if custom_condition_script == null or custom_action_script == null:
		return
	var compare := RECompareCondition.new()
	compare.source = RECompareCondition.Source.PAYLOAD
	compare.key = &"score"
	compare.operator = RECompareCondition.Operator.GREATER_EQUAL
	compare.value = 10
	var custom_condition: RECondition = custom_condition_script.new()
	custom_condition.key = &"bonus"
	var root := REAllCondition.new()
	root.conditions.append(compare)
	root.conditions.append(custom_condition)
	var first_action := RESetBlackboardAction.new()
	first_action.key = &"first"
	first_action.value = 1
	var custom_action: REAction = custom_action_script.new()
	custom_action.marker = &"second"
	var rule := RERule.new()
	rule.id = &"round_trip"
	rule.event = &"score_changed"
	rule.condition = root
	rule.actions.append(first_action)
	rule.actions.append(custom_action)
	assert_eq(ResourceSaver.save(rule, RULE_PATH, ResourceSaver.FLAG_CHANGE_PATH), OK)
	rule.take_over_path(RULE_PATH)
	var book := RERuleBook.new()
	book.rules.append(rule)
	assert_eq(ResourceSaver.save(book, BOOK_PATH), OK)
	compare.value = 99
	var loaded: RERuleBook = ResourceLoader.load(
		BOOK_PATH,
		"",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP,
	)
	assert_not_null(loaded)
	assert_eq(loaded.rules.size(), 1)
	var loaded_rule := loaded.rules[0]
	assert_eq(loaded_rule.id, &"round_trip")
	assert_eq(loaded_rule.resource_path, RULE_PATH)
	var loaded_root: REAllCondition = loaded_rule.condition
	assert_eq(loaded_root.conditions.size(), 2)
	assert_eq(loaded_root.conditions[0].value, 10)
	assert_eq(loaded_root.conditions[1].get_script(), custom_condition_script)
	assert_true(loaded_rule.actions[0] is RESetBlackboardAction)
	assert_eq(loaded_rule.actions[1].get_script(), custom_action_script)
	var provider := REDictionaryFactProvider.new()
	var context := REMatchContext.new({&"score": 10, &"bonus": true}, {}, provider)
	assert_true(loaded_rule.condition.evaluate(context).matched)
	var engine := RERuleEngine.new()
	assert_eq(engine.load_book(loaded), OK)
	engine.emit_event(&"score_changed", {&"score": 10, &"bonus": true})
	assert_eq(engine.get_blackboard().get_value(&"first"), 1)
	assert_eq(engine.get_blackboard().get_value(&"second"), true)
