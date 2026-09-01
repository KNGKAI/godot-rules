extends GutTest

const ENGINE_PATH := "res://addons/rule_engine/runtime/rule_engine.gd"


class AlwaysCondition extends RECondition:
	func evaluate(_context: REMatchContext) -> REConditionResult:
		return REConditionResult.new(true, true)


class CountAction extends REAction:
	var calls: int = 0

	func execute(_context: Variant) -> Error:
		calls += 1
		return OK


func _engine() -> Variant:
	var script: Script = load(ENGINE_PATH)
	assert_not_null(script, "rule engine must load")
	return script.new() if script != null else null


func _book(rules: Array) -> RERuleBook:
	var book := RERuleBook.new()
	for rule: RERule in rules:
		book.rules.append(rule)
	return book


func _rule(id: StringName, event: StringName = &"") -> RERule:
	var rule := RERule.new()
	rule.id = id
	rule.event = event
	rule.condition = AlwaysCondition.new()
	if not event.is_empty():
		rule.actions.append(CountAction.new())
	return rule


func test_load_is_atomic_when_an_id_already_exists() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	assert_eq(engine.load_book(_book([_rule(&"existing")])), OK)
	var incoming := _book([_rule(&"new"), _rule(&"existing")])
	assert_eq(engine.load_book(incoming), ERR_ALREADY_EXISTS)
	assert_null(engine.get_rule(&"new"))
	assert_not_null(engine.get_rule(&"existing"))


func test_duplicate_reference_rejects_the_whole_book() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var rule := _rule(&"duplicate")
	var book := RERuleBook.new()
	book.rules.append(rule)
	book.rules.append(rule)
	assert_eq(engine.load_book(book), ERR_INVALID_DATA)
	assert_null(engine.get_rule(&"duplicate"))


func test_loading_same_book_is_idempotent_and_unload_removes_owned_rules() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var book := _book([_rule(&"query"), _rule(&"reactive", &"ping")])
	assert_eq(engine.load_book(book), OK)
	assert_eq(engine.load_book(book), OK)
	assert_not_null(engine.get_rule(&"query"))
	engine.unload_book(book)
	assert_null(engine.get_rule(&"query"))
	assert_null(engine.get_rule(&"reactive"))


func test_queryable_and_reactive_rules_use_separate_entry_points() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var query := _rule(&"query")
	var reactive := _rule(&"reactive", &"ping")
	var action: CountAction = reactive.actions[0]
	assert_eq(engine.load_book(_book([query, reactive])), OK)
	assert_true(engine.check(&"query"))
	assert_false(engine.check(&"reactive"))
	assert_eq(action.calls, 0)
	engine.emit_event(&"ping")
	assert_eq(action.calls, 1)


func test_load_rejects_cyclic_and_null_child_condition_trees_atomically() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var cycle := REAllCondition.new()
	cycle.conditions.append(cycle)
	var cyclic_rule := _rule(&"cyclic")
	cyclic_rule.condition = cycle
	assert_eq(engine.load_book(_book([cyclic_rule])), ERR_INVALID_DATA)
	cycle.conditions.clear()
	var malformed := REAllCondition.new()
	malformed.conditions.append(null)
	var malformed_rule := _rule(&"malformed")
	malformed_rule.condition = malformed
	assert_eq(engine.load_book(_book([malformed_rule])), ERR_INVALID_DATA)
	assert_null(engine.get_rule(&"cyclic"))
	assert_null(engine.get_rule(&"malformed"))


func test_load_accepts_contains_operator_values() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var compare := RECompareCondition.new()
	compare.source = RECompareCondition.Source.PAYLOAD
	compare.key = &"items"
	compare.operator = 7 as RECompareCondition.Operator
	compare.value = "target"
	var rule := _rule(&"contains", &"check")
	rule.condition = compare
	assert_eq(engine.load_book(_book([rule])), OK)
