extends GutTest

const VALIDATOR_PATH := "res://addons/rule_engine/editor/validation/validator.gd"


class AlwaysCondition extends RECondition:
	func evaluate(_context: REMatchContext) -> REConditionResult:
		return REConditionResult.new(true, true)


class NoOpAction extends REAction:
	func execute(_context: Variant) -> Error:
		return OK


func _validator() -> Variant:
	var script: Script = load(VALIDATOR_PATH)
	assert_not_null(script)
	return script.new() if script != null else null


func _rule(id: StringName, event: StringName = &"") -> RERule:
	var rule := RERule.new()
	rule.id = id
	rule.event = event
	rule.condition = AlwaysCondition.new()
	if not event.is_empty():
		rule.actions.append(NoOpAction.new())
	return rule


func _book(rules: Array) -> RERuleBook:
	var book := RERuleBook.new()
	for rule: RERule in rules:
		book.rules.append(rule)
	return book


func _codes(issues: Array) -> Array:
	return issues.map(func(issue: Variant) -> StringName: return issue.code)


func test_duplicate_ids_and_references_are_reported_without_short_circuiting() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var shared := _rule(&"shared")
	var first := _book([shared, shared])
	var second := _book([_rule(&"shared"), _rule(&"unique")])
	var issues: Array = validator.validate_books([first, second])
	assert_has(_codes(issues), &"duplicate_reference")
	assert_has(_codes(issues), &"duplicate_id")


func test_malformed_and_cyclic_condition_trees_are_errors() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var missing := RERule.new()
	missing.event = &"go"
	var composite := REAllCondition.new()
	composite.conditions.append(null)
	var malformed := _rule(&"malformed", &"go")
	malformed.condition = composite
	malformed.actions.clear()
	var cycle := RENotCondition.new()
	cycle.condition = cycle
	var cyclic := _rule(&"cyclic")
	cyclic.condition = cycle
	var issues: Array = validator.validate_books([_book([missing, malformed, cyclic])])
	cycle.condition = null
	var codes := _codes(issues)
	assert_has(codes, &"empty_id")
	assert_has(codes, &"missing_condition")
	assert_has(codes, &"missing_actions")
	assert_has(codes, &"null_condition_child")
	assert_has(codes, &"condition_cycle")


func test_invalid_compare_values_and_optional_catalog_misses_are_reported() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var compare := RECompareCondition.new()
	compare.source = 99 as RECompareCondition.Source
	compare.operator = 99 as RECompareCondition.Operator
	compare.key = &"unknown_fact"
	compare.value = null
	var rule := _rule(&"catalogued", &"unknown_event")
	rule.condition = compare
	var event_catalog := RENameCatalog.new()
	event_catalog.names.append(&"known_event")
	var fact_catalog := RENameCatalog.new()
	fact_catalog.names.append(&"known_fact")
	var issues: Array = validator.validate_books([_book([rule])], event_catalog, fact_catalog)
	var codes := _codes(issues)
	assert_has(codes, &"invalid_source")
	assert_has(codes, &"invalid_operator")
	assert_has(codes, &"unknown_event")


func test_empty_composites_and_unknown_fact_are_stable_warnings_after_errors() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var empty_all := REAllCondition.new()
	var warning_rule := _rule(&"warning")
	warning_rule.condition = empty_all
	var exists := REExistsCondition.new()
	exists.source = REExistsCondition.Source.FACT
	exists.key = &"missing_catalog_entry"
	var fact_rule := _rule(&"fact")
	fact_rule.condition = exists
	var error_rule := _rule(&"")
	var fact_catalog := RENameCatalog.new()
	fact_catalog.names.append(&"known")
	var issues: Array = validator.validate_books(
		[_book([warning_rule, fact_rule, error_rule])],
		null,
		fact_catalog,
	)
	assert_has(_codes(issues), &"empty_composite")
	assert_has(_codes(issues), &"unknown_fact")
	var saw_warning := false
	for issue: Variant in issues:
		if issue.severity == 1:
			saw_warning = true
		else:
			assert_false(saw_warning, "errors must sort before warnings")
