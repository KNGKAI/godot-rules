extends GutTest

const VALIDATOR_PATH := "res://addons/rule_engine/editor/validation/validator.gd"
const VALIDATION_ISSUE_PATH := "res://addons/rule_engine/editor/validation/validation_issue.gd"


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


func _issues_with_code(issues: Array, code: StringName) -> Array:
	return issues.filter(func(issue: Variant) -> bool: return issue.code == code)


func _reactive_rule(id: StringName, event: StringName, emitted_event: StringName) -> RERule:
	var rule := _rule(id, event)
	var action := REEmitEventAction.new()
	action.event = emitted_event
	rule.actions[0] = action
	return rule


func test_validation_issue_retains_rule_and_derives_rule_id() -> void:
	var script: Script = load(VALIDATION_ISSUE_PATH)
	assert_not_null(script)
	if script == null:
		return
	var rule := _rule(&"rule_reference")
	var issue: Variant = script.new(script.Severity.ERROR, &"test", "message", rule, ".field")
	assert_eq(issue.rule, rule)
	assert_eq(issue.rule_id, &"rule_reference")


func test_validation_issue_allows_book_level_issues_and_formats_all_severities() -> void:
	var script: Script = load(VALIDATION_ISSUE_PATH)
	assert_not_null(script)
	if script == null:
		return
	var book_issue: Variant = script.new(script.Severity.INFO, &"note", "message", null, "books[0]")
	assert_null(book_issue.rule)
	assert_eq(book_issue.rule_id, &"")
	assert_string_contains(str(book_issue), "INFO [note]")
	for severity: int in [script.Severity.ERROR, script.Severity.WARNING, script.Severity.INFO]:
		var issue: Variant = script.new(severity, &"formatted", "message", null, ".field")
		var expected: String = ["ERROR", "WARNING", "INFO"][severity]
		assert_string_contains(str(issue), "%s [formatted]" % expected)


func test_issues_sort_by_severity_then_rule_path_and_code() -> void:
	var validator: Variant = _validator()
	var script: Script = load(VALIDATION_ISSUE_PATH)
	if validator == null or script == null:
		return
	var issues: Array = [
		script.new(script.Severity.INFO, &"z", "", null, ".z"),
		script.new(script.Severity.WARNING, &"z", "", _rule(&"b"), ".z"),
		script.new(script.Severity.ERROR, &"z", "", _rule(&"b"), ".z"),
		script.new(script.Severity.ERROR, &"a", "", _rule(&"a"), ".z"),
		script.new(script.Severity.ERROR, &"b", "", _rule(&"a"), ".a"),
	]
	issues.sort_custom(validator._issue_precedes)
	assert_eq(issues.map(func(issue: Variant) -> StringName: return issue.code), [&"b", &"a", &"z", &"z", &"z"])
	assert_eq(issues.map(func(issue: Variant) -> int: return issue.severity), [0, 0, 0, 1, 2])


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


func test_contains_operator_values_are_accepted_by_editor_validation() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var compare := RECompareCondition.new()
	compare.source = RECompareCondition.Source.PAYLOAD
	compare.key = &"items"
	compare.operator = 7 as RECompareCondition.Operator
	compare.value = "target"
	var rule := _rule(&"contains")
	rule.condition = compare
	var issues: Array = validator.validate_books([_book([rule])])
	assert_does_not_have(_codes(issues), &"invalid_operator")


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


func test_empty_builtin_action_fields_are_errors_at_their_properties() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var emit_rule := _rule(&"empty_emit", &"start")
	emit_rule.actions[0] = REEmitEventAction.new()
	var blackboard_rule := _rule(&"empty_key", &"next")
	blackboard_rule.actions[0] = RESetBlackboardAction.new()
	var issues: Array = validator.validate_books([_book([emit_rule, blackboard_rule])])
	var emit_issues := _issues_with_code(issues, &"empty_action_event")
	var key_issues := _issues_with_code(issues, &"empty_action_key")
	assert_eq(emit_issues.size(), 1)
	if emit_issues.size() != 1:
		return
	assert_eq(emit_issues[0].property_path, "books[0].rules[0].actions[0].event")
	assert_eq(key_issues.size(), 1)
	if key_issues.size() != 1:
		return
	assert_eq(key_issues[0].property_path, "books[0].rules[1].actions[0].key")
	assert_eq(emit_issues[0].severity, 0)
	assert_eq(key_issues[0].severity, 0)


func test_self_emitting_rule_reports_one_cycle_warning_on_its_action() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var loop := _reactive_rule(&"loop", &"again", &"again")
	var issues: Array = validator.validate_books([_book([loop])])
	var warnings := _issues_with_code(issues, &"potential_event_cycle")
	assert_eq(warnings.size(), 1)
	if warnings.size() != 1:
		return
	assert_eq(warnings[0].severity, 1)
	assert_eq(warnings[0].rule, loop)
	assert_eq(warnings[0].rule_id, &"loop")
	assert_eq(warnings[0].property_path, "books[0].rules[0].actions[0].event")


func test_two_event_cycle_reports_each_emitting_action_once() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var issues: Array = validator.validate_books([_book([
		_reactive_rule(&"first", &"a", &"b"),
		_reactive_rule(&"second", &"b", &"a"),
	])])
	var warnings := _issues_with_code(issues, &"potential_event_cycle")
	assert_eq(warnings.size(), 2)
	assert_eq(warnings.map(func(issue: Variant) -> StringName: return issue.rule_id), [&"first", &"second"])


func test_larger_event_cycle_reports_each_participating_action_once() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var issues: Array = validator.validate_books([_book([
		_reactive_rule(&"first", &"a", &"b"),
		_reactive_rule(&"second", &"b", &"c"),
		_reactive_rule(&"third", &"c", &"a"),
	])])
	var warnings := _issues_with_code(issues, &"potential_event_cycle")
	assert_eq(warnings.size(), 3)
	assert_eq(warnings.map(func(issue: Variant) -> StringName: return issue.rule_id), [&"first", &"second", &"third"])


func test_acyclic_and_custom_action_edges_do_not_report_cycle_warnings() -> void:
	var validator: Variant = _validator()
	if validator == null:
		return
	var custom := _rule(&"custom", &"c")
	var custom_action := NoOpAction.new()
	custom.actions[0] = custom_action
	var issues: Array = validator.validate_books([_book([
		_reactive_rule(&"first", &"a", &"b"),
		_reactive_rule(&"second", &"b", &"c"),
		custom,
	])])
	assert_eq(_issues_with_code(issues, &"potential_event_cycle").size(), 0)
