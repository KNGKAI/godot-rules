extends GutTest

const ENGINE_PATH := "res://addons/rule_engine/runtime/rule_engine.gd"


class AlwaysCondition extends RECondition:
	func evaluate(_context: REMatchContext) -> REConditionResult:
		return REConditionResult.new(true, true)


class EmitAction extends REAction:
	var event: StringName

	func _init(p_event: StringName = &"") -> void:
		event = p_event

	func execute(context: Variant) -> Error:
		context.emit_event(event)
		return OK


class CountAction extends REAction:
	var calls: int = 0

	func execute(_context: Variant) -> Error:
		calls += 1
		return OK


func _rule(id: StringName, event: StringName, action: REAction) -> RERule:
	var rule := RERule.new()
	rule.id = id
	rule.event = event
	rule.condition = AlwaysCondition.new()
	rule.actions.append(action)
	return rule


func test_event_limit_reports_exact_processed_count_clears_and_recovers() -> void:
	var script: Script = load(ENGINE_PATH)
	assert_not_null(script, "rule engine must load")
	if script == null:
		return
	var engine: Variant = script.new()
	engine.max_events_per_dispatch = 3
	var recovery := CountAction.new()
	var book := RERuleBook.new()
	book.rules.append(_rule(&"a", &"A", EmitAction.new(&"B")))
	book.rules.append(_rule(&"b", &"B", EmitAction.new(&"A")))
	book.rules.append(_rule(&"recovery", &"recovery", recovery))
	var failures: Array = []
	engine.dispatch_failed.connect(func(reason: StringName, processed: int) -> void:
		failures.append([reason, processed])
	)
	assert_eq(engine.load_book(book), OK)
	engine.emit_event(&"A")
	assert_push_error("event limit")
	assert_eq(failures, [[&"event_limit", 3]])
	engine.emit_event(&"recovery")
	assert_eq(recovery.calls, 1)

