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


class EmitEventsAction extends REAction:
	var events: Array = []

	func _init(p_events: Array = []) -> void:
		events = p_events

	func execute(context: Variant) -> Error:
		for event: StringName in events:
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


func test_max_chain_depth_defaults_to_64_and_clamps_to_one() -> void:
	var script: Script = load(ENGINE_PATH)
	assert_not_null(script, "rule engine must load")
	if script == null:
		return
	var engine: Variant = script.new()
	assert_eq(engine.get(&"max_chain_depth"), 64)
	engine.set(&"max_chain_depth", 0)
	assert_eq(engine.get(&"max_chain_depth"), 1)


func test_chain_depth_allows_the_boundary_and_rejects_a_listener_and_action_child() -> void:
	var script: Script = load(ENGINE_PATH)
	assert_not_null(script, "rule engine must load")
	if script == null:
		return
	var boundary_engine: Variant = script.new()
	boundary_engine.max_chain_depth = 2
	var boundary_count := CountAction.new()
	var boundary_book := RERuleBook.new()
	boundary_book.rules.append(_rule(&"boundary_a", &"A", EmitAction.new(&"B")))
	boundary_book.rules.append(_rule(&"boundary_b", &"B", EmitAction.new(&"C")))
	boundary_book.rules.append(_rule(&"boundary_c", &"C", boundary_count))
	assert_eq(boundary_engine.load_book(boundary_book), OK)
	boundary_engine.emit_event(&"A")
	assert_eq(boundary_count.calls, 1)

	var engine: Variant = script.new()
	engine.max_chain_depth = 1
	var rejected := CountAction.new()
	var cleared := CountAction.new()
	var recovery := CountAction.new()
	var book := RERuleBook.new()
	book.rules.append(_rule(&"a", &"A", CountAction.new()))
	book.rules.append(_rule(&"b", &"B", EmitEventsAction.new([&"rejected", &"cleared"])))
	book.rules.append(_rule(&"rejected", &"rejected", rejected))
	book.rules.append(_rule(&"cleared", &"cleared", cleared))
	book.rules.append(_rule(&"recovery", &"recovery", recovery))
	var received: Array = []
	var failures: Array = []
	engine.event_received.connect(func(event: RERuleEvent) -> void:
		received.append(event.name)
		if event.name == &"A":
			engine.emit_event(&"B")
	)
	engine.dispatch_failed.connect(func(reason: StringName, processed: int) -> void:
		failures.append([reason, processed])
	)
	assert_eq(engine.load_book(book), OK)
	engine.emit_event(&"A")
	assert_push_error("chain depth")
	assert_eq(received, [&"A", &"B"])
	assert_eq(failures, [[&"chain_depth", 2]])
	assert_eq(rejected.calls, 0)
	assert_eq(cleared.calls, 0)
	engine.emit_event(&"recovery")
	assert_eq(recovery.calls, 1)
