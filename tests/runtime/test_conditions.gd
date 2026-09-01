extends GutTest

const CONTEXT_PATH := "res://addons/rule_engine/runtime/match_context.gd"
const PROVIDER_PATH := "res://addons/rule_engine/runtime/dictionary_fact_provider.gd"
const BLACKBOARD_PATH := "res://addons/rule_engine/runtime/blackboard.gd"
const ALL_PATH := "res://addons/rule_engine/resources/conditions/all.gd"
const ANY_PATH := "res://addons/rule_engine/resources/conditions/any.gd"
const NOT_PATH := "res://addons/rule_engine/resources/conditions/not.gd"
const COMPARE_PATH := "res://addons/rule_engine/resources/conditions/compare.gd"
const EXISTS_PATH := "res://addons/rule_engine/resources/conditions/exists.gd"

const CONTAINS_OPERATOR := 6
const NOT_CONTAINS_OPERATOR := 7


func _new(path: String, args: Array = []) -> Variant:
	var script: Script = load(path)
	assert_not_null(script, "%s must load" % path)
	if script == null:
		return null
	return script.new.callv(args)


func _context(
	payload: Dictionary = {},
	blackboard_values: Dictionary = {},
	facts: Dictionary = {},
) -> Variant:
	var provider: Variant = _new(PROVIDER_PATH, [facts])
	var blackboard: Variant = _new(BLACKBOARD_PATH)
	if provider == null or blackboard == null:
		return null
	for key: Variant in blackboard_values:
		blackboard.set_value(StringName(key), blackboard_values[key])
	return _new(CONTEXT_PATH, [payload, blackboard.snapshot(), provider])


func _make_compare(source: int, key: StringName, operator: int, expected: Variant) -> Variant:
	var condition: Variant = _new(COMPARE_PATH)
	if condition == null:
		return null
	condition.source = source
	condition.key = key
	condition.operator = operator
	condition.value = expected
	return condition


func test_existing_comparison_operators() -> void:
	var context: Variant = _context({&"value": 10})
	if context == null:
		return
	var cases := [
		[0, 10, true],
		[1, 11, true],
		[2, 9, true],
		[3, 10, true],
		[4, 11, true],
		[5, 10, true],
	]
	for case: Array in cases:
		var result: Variant = _make_compare(1, &"value", case[0], case[1]).evaluate(context)
		assert_true(result.valid)
		assert_eq(result.matched, case[2])


func test_numeric_and_text_equivalence_is_explicit() -> void:
	var context: Variant = _context({&"number": 10, &"name": &"Ada"})
	if context == null:
		return
	var numeric: Variant = _make_compare(1, &"number", 0, 10.0).evaluate(context)
	var text: Variant = _make_compare(1, &"name", 0, "Ada").evaluate(context)
	assert_true(numeric.valid)
	assert_true(numeric.matched)
	assert_true(text.valid)
	assert_true(text.matched)
	var adjacent_large_integers := RECompareCondition.compare_values(
		9223372036854775806,
		9223372036854775807,
		RECompareCondition.Operator.LESS,
	)
	assert_true(adjacent_large_integers.valid)
	assert_true(adjacent_large_integers.matched)


func test_missing_and_incompatible_comparisons_are_invalid() -> void:
	var context: Variant = _context({&"flag": true})
	if context == null:
		return
	var missing: Variant = _make_compare(1, &"missing", 0, 1).evaluate(context)
	var incompatible: Variant = _make_compare(1, &"flag", 2, 1).evaluate(context)
	assert_false(missing.valid)
	assert_false(missing.matched)
	assert_false(incompatible.valid)
	assert_false(incompatible.matched)


func test_not_preserves_invalidity_but_not_exists_matches_missing() -> void:
	var context: Variant = _context()
	if context == null:
		return
	var not_compare: Variant = _new(NOT_PATH)
	var not_exists: Variant = _new(NOT_PATH)
	var exists: Variant = _new(EXISTS_PATH)
	if not_compare == null or not_exists == null or exists == null:
		return
	not_compare.condition = _make_compare(1, &"missing", 0, 1)
	exists.source = 1
	exists.key = &"missing"
	not_exists.condition = exists
	var invalid_result: Variant = not_compare.evaluate(context)
	var missing_result: Variant = not_exists.evaluate(context)
	assert_false(invalid_result.valid)
	assert_false(invalid_result.matched)
	assert_true(missing_result.valid)
	assert_true(missing_result.matched)


func test_composites_define_empty_and_nested_behavior() -> void:
	var context: Variant = _context({&"score": 5})
	var all_condition: Variant = _new(ALL_PATH)
	var any_condition: Variant = _new(ANY_PATH)
	if context == null or all_condition == null or any_condition == null:
		return
	assert_true(all_condition.evaluate(context).matched)
	assert_false(any_condition.evaluate(context).matched)
	all_condition.conditions.append(_make_compare(1, &"score", 3, 5))
	all_condition.conditions.append(_make_compare(1, &"score", 4, 10))
	any_condition.conditions.append(_make_compare(1, &"score", 2, 10))
	any_condition.conditions.append(all_condition)
	assert_true(any_condition.evaluate(context).matched)


func test_compare_and_exists_read_all_three_namespaces() -> void:
	var context: Variant = _context(
		{&"payload_key": "payload"},
		{&"state_key": "state"},
		{&"fact_key": "fact"},
	)
	if context == null:
		return
	for case: Array in [
		[0, &"fact_key", "fact"],
		[1, &"payload_key", "payload"],
		[2, &"state_key", "state"],
	]:
		var compare_result: Variant = _make_compare(case[0], case[1], 0, case[2]).evaluate(context)
		var exists: Variant = _new(EXISTS_PATH)
		exists.source = case[0]
		exists.key = case[1]
		assert_true(compare_result.matched)
		assert_true(exists.evaluate(context).matched)


func test_contains_and_not_contains_cover_text_and_container_families() -> void:
	var cases: Array = [
		["String/String", "rule_engine", "engine", "missing"],
		["String/StringName", "rule_engine", &"engine", &"missing"],
		["StringName/String", &"rule_engine", "engine", "missing"],
		["StringName/StringName", &"rule_engine", &"engine", &"missing"],
		["Array", [2, 4], 4, 3],
		["PackedByteArray", PackedByteArray([2, 4]), 4, 3],
		["PackedInt32Array", PackedInt32Array([2, 4]), 4, 3],
		["PackedInt64Array", PackedInt64Array([2, 4]), 4, 3],
		["PackedFloat32Array", PackedFloat32Array([2.0, 4.0]), 4.0, 3.0],
		["PackedFloat64Array", PackedFloat64Array([2.0, 4.0]), 4.0, 3.0],
		["PackedStringArray", PackedStringArray(["two", "four"]), "four", "three"],
		[
			"PackedVector2Array",
			PackedVector2Array([Vector2(2, 4)]),
			Vector2(2, 4),
			Vector2(3, 4),
		],
		[
			"PackedVector3Array",
			PackedVector3Array([Vector3(2, 4, 6)]),
			Vector3(2, 4, 6),
			Vector3(3, 4, 6),
		],
		[
			"PackedVector4Array",
			PackedVector4Array([Vector4(2, 4, 6, 8)]),
			Vector4(2, 4, 6, 8),
			Vector4(3, 4, 6, 8),
		],
		["PackedColorArray", PackedColorArray([Color.RED]), Color.RED, Color.BLUE],
		["Dictionary", {&"found": "value"}, &"found", &"missing"],
	]
	for case: Array in cases:
		var contained: Dictionary = RECompareCondition.compare_values(
			case[1], case[2], CONTAINS_OPERATOR
		)
		assert_true(contained.valid, "%s should support containment" % case[0])
		assert_true(contained.matched, "%s should find its contained value" % case[0])
		var absent: Dictionary = RECompareCondition.compare_values(
			case[1], case[3], CONTAINS_OPERATOR
		)
		assert_true(absent.valid, "%s should support absent containment checks" % case[0])
		assert_false(absent.matched, "%s should not match an absent value" % case[0])
		var negated: Dictionary = RECompareCondition.compare_values(
			case[1], case[3], NOT_CONTAINS_OPERATOR
		)
		assert_true(negated.valid, "%s should support negated containment" % case[0])
		assert_true(negated.matched, "%s should negate an absent containment result" % case[0])
		var negated_existing: Dictionary = RECompareCondition.compare_values(
			case[1], case[2], NOT_CONTAINS_OPERATOR
		)
		assert_true(
			negated_existing.valid,
			"%s should support negated containment for an existing value" % case[0],
		)
		assert_false(
			negated_existing.matched,
			"%s should not match an existing value with NOT_CONTAINS" % case[0],
		)


func test_contains_rejects_incompatible_operands_without_negating_invalidity() -> void:
	var invalid_cases: Array = [
		[42, 2],
		["text", 2],
	]
	for case: Array in invalid_cases:
		for p_operator: int in [CONTAINS_OPERATOR, NOT_CONTAINS_OPERATOR]:
			var result: Dictionary = RECompareCondition.compare_values(case[0], case[1], p_operator)
			assert_false(result.valid)
			assert_false(result.matched)
