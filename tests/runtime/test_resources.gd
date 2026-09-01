extends GutTest

const RULE_PATH := "res://addons/rule_engine/resources/rule.gd"
const BOOK_PATH := "res://addons/rule_engine/resources/rule_book.gd"
const CATALOG_PATH := "res://addons/rule_engine/resources/name_catalog.gd"
const CONDITION_RESULT_PATH := "res://addons/rule_engine/resources/conditions/condition_result.gd"
const CONDITION_PATH := "res://addons/rule_engine/resources/conditions/condition.gd"
const ACTION_PATH := "res://addons/rule_engine/resources/actions/action.gd"
const FIXTURE_PATH := "res://tests/fixtures/valid_book.tres"


func test_public_resource_scripts_can_be_loaded() -> void:
	for path: String in [
		RULE_PATH,
		BOOK_PATH,
		CATALOG_PATH,
		CONDITION_RESULT_PATH,
		CONDITION_PATH,
		ACTION_PATH,
	]:
		assert_not_null(load(path), "%s must load" % path)


func test_rule_defaults_are_safe_for_native_inspector_construction() -> void:
	var script: Script = load(RULE_PATH)
	assert_not_null(script)
	if script == null:
		return
	var rule: Resource = script.new()
	assert_eq(rule.id, &"")
	assert_true(rule.enabled)
	assert_eq(rule.priority, 0)
	assert_eq(rule.tags, PackedStringArray())
	assert_eq(rule.event, &"")
	assert_null(rule.condition)
	assert_eq(rule.actions.size(), 0)
	assert_false("has_fired" in rule)


func test_empty_event_is_queryable_and_non_empty_event_is_reactive() -> void:
	var script: Script = load(RULE_PATH)
	assert_not_null(script)
	if script == null:
		return
	var rule: Resource = script.new()
	assert_true(rule.is_queryable())
	assert_false(rule.is_reactive())
	rule.event = &"mission_completed"
	assert_false(rule.is_queryable())
	assert_true(rule.is_reactive())


func test_condition_result_preserves_match_and_validity_independently() -> void:
	var script: Script = load(CONDITION_RESULT_PATH)
	assert_not_null(script)
	if script == null:
		return
	var result: RefCounted = script.new(true, false)
	assert_true(result.matched)
	assert_false(result.valid)


func test_external_rule_fixture_loads_with_explicit_id() -> void:
	var book: Resource = load(FIXTURE_PATH)
	assert_not_null(book)
	if book == null:
		return
	assert_eq(book.rules.size(), 1)
	assert_eq(book.rules[0].id, &"fixture.query")
	assert_true(book.rules[0].is_queryable())

