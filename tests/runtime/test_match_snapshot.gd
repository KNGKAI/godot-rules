extends GutTest

const CONTEXT_PATH := "res://addons/rule_engine/runtime/match_context.gd"
const PROVIDER_PATH := "res://addons/rule_engine/runtime/dictionary_fact_provider.gd"
const BLACKBOARD_PATH := "res://addons/rule_engine/runtime/blackboard.gd"


func _script(path: String) -> Script:
	var value: Script = load(path)
	assert_not_null(value, "%s must load" % path)
	return value


func test_payload_keys_are_normalized_and_nested_values_are_frozen_snapshots() -> void:
	var context_script := _script(CONTEXT_PATH)
	var provider_script := _script(PROVIDER_PATH)
	if context_script == null or provider_script == null:
		return
	var source := {"items": [{"name": "original"}]}
	var normalized: Dictionary = context_script.normalize_payload(source)
	assert_true(normalized.valid)
	var context: Variant = context_script.new(normalized.value, {}, provider_script.new())
	source["items"][0]["name"] = "changed"
	var lookup: Dictionary = context.lookup(1, &"items")
	assert_true(lookup.present)
	assert_eq(lookup.value[0][&"name"], "original")
	assert_true(context.payload.is_read_only())
	assert_true(lookup.value.is_read_only())
	assert_true(lookup.value[0].is_read_only())
	assert_true(context.payload.has(&"items"))


func test_payload_rejects_non_string_keys() -> void:
	var context_script := _script(CONTEXT_PATH)
	if context_script == null:
		return
	var normalized: Dictionary = context_script.normalize_payload({1: "invalid"})
	assert_false(normalized.valid)
	assert_eq(normalized.value, {})


func test_blackboard_is_snapshotted_for_one_match_phase() -> void:
	var context_script := _script(CONTEXT_PATH)
	var provider_script := _script(PROVIDER_PATH)
	var blackboard_script := _script(BLACKBOARD_PATH)
	if context_script == null or provider_script == null or blackboard_script == null:
		return
	var blackboard: Variant = blackboard_script.new()
	blackboard.set_value(&"score", 10)
	var context: Variant = context_script.new({}, blackboard.snapshot(), provider_script.new())
	blackboard.set_value(&"score", 20)
	assert_eq(context.lookup(2, &"score").value, 10)


func test_fact_provider_memoizes_present_and_missing_values() -> void:
	var context_script := _script(CONTEXT_PATH)
	var provider_script := _script(PROVIDER_PATH)
	if context_script == null or provider_script == null:
		return
	var provider: Variant = provider_script.new({&"score": 10})
	var context: Variant = context_script.new({}, {}, provider)
	assert_eq(context.lookup(0, &"score").value, 10)
	provider.facts[&"score"] = 99
	assert_eq(context.lookup(0, &"score").value, 10)
	assert_false(context.lookup(0, &"missing").present)
	provider.facts[&"missing"] = true
	assert_false(context.lookup(0, &"missing").present)

