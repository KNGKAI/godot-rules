extends GutTest

const ENGINE_PATH := "res://addons/rule_engine/runtime/rule_engine.gd"


class AlwaysCondition extends RECondition:
	func evaluate(_context: REMatchContext) -> REConditionResult:
		return REConditionResult.new(true, true)


class RecordingAction extends REAction:
	var trace: Array
	var label: String
	var emitted_event: StringName
	var callback: Callable
	var result_code: Error

	func _init(
		p_trace: Array = [],
		p_label: String = "",
		p_emitted_event: StringName = &"",
		p_callback: Callable = Callable(),
		p_result_code: Error = OK,
	) -> void:
		trace = p_trace
		label = p_label
		emitted_event = p_emitted_event
		callback = p_callback
		result_code = p_result_code

	func execute(context: Variant) -> Error:
		trace.append(label)
		if callback.is_valid():
			callback.call(context)
		if not emitted_event.is_empty():
			context.emit_event(emitted_event)
		return result_code


func _engine() -> Variant:
	var script: Script = load(ENGINE_PATH)
	assert_not_null(script, "rule engine must load")
	return script.new() if script != null else null


func _book(rules: Array) -> RERuleBook:
	var book := RERuleBook.new()
	for rule: RERule in rules:
		book.rules.append(rule)
	return book


func _rule(
	id: StringName,
	event: StringName,
	condition: RECondition,
	actions: Array,
	priority: int = 0,
) -> RERule:
	var rule := RERule.new()
	rule.id = id
	rule.event = event
	rule.condition = condition
	rule.priority = priority
	for action: REAction in actions:
		rule.actions.append(action)
	return rule


func _always_rule(
	id: StringName,
	event: StringName,
	actions: Array,
	priority: int = 0,
) -> RERule:
	return _rule(id, event, AlwaysCondition.new(), actions, priority)


func test_candidates_and_actions_execute_in_deterministic_order() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var trace: Array = []
	var book := _book([
		_always_rule(&"b", &"go", [RecordingAction.new(trace, "b1"), RecordingAction.new(trace, "b2")]),
		_always_rule(&"a", &"go", [RecordingAction.new(trace, "a")]),
		_always_rule(&"c", &"go", [RecordingAction.new(trace, "c")], 10),
	])
	assert_eq(engine.load_book(book), OK)
	engine.emit_event(&"go")
	assert_eq(trace, ["c", "a", "b1", "b2"])


func test_enabled_defaults_and_runtime_overrides_do_not_mutate_resources() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var trace: Array = []
	var rule := _always_rule(&"disabled", &"go", [RecordingAction.new(trace, "fired")])
	rule.enabled = false
	assert_eq(engine.load_book(_book([rule])), OK)
	engine.emit_event(&"go")
	assert_eq(trace, [])
	assert_eq(engine.set_rule_enabled(&"disabled", true), OK)
	engine.emit_event(&"go")
	assert_eq(trace, ["fired"])
	assert_false(rule.enabled)
	engine.clear_rule_enabled_override(&"disabled")
	engine.emit_event(&"go")
	assert_eq(trace, ["fired"])


func test_same_event_conditions_use_the_pre_action_blackboard_snapshot() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var trace: Array = []
	engine.get_blackboard().set_value(&"score", 0)
	var write := RecordingAction.new(trace, "a", &"", func(context: Variant) -> void:
		context.blackboard.set_value(&"score", 1)
	)
	var compare := RECompareCondition.new()
	compare.source = RECompareCondition.Source.BLACKBOARD
	compare.key = &"score"
	compare.operator = RECompareCondition.Operator.EQUAL
	compare.value = 0
	var book := _book([
		_always_rule(&"a", &"go", [write]),
		_rule(&"b", &"go", compare, [RecordingAction.new(trace, "b")]),
	])
	assert_eq(engine.load_book(book), OK)
	engine.emit_event(&"go")
	assert_eq(trace, ["a", "b"])
	assert_eq(engine.get_blackboard().get_value(&"score"), 1)


func test_nested_action_and_listener_events_are_fifo_not_recursive() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var trace: Array = []
	var listener_state: Dictionary = {&"emitted": false}
	var weak_engine: WeakRef = weakref(engine)
	var listener: Callable = func(_rule_value: RERule, _action: REAction) -> void:
		if not listener_state.emitted:
			listener_state.emitted = true
			weak_engine.get_ref().emit_event(&"listener")
	engine.action_executed.connect(listener)
	var book := _book([
		_always_rule(&"a", &"start", [
			RecordingAction.new(trace, "a1", &"nested"),
			RecordingAction.new(trace, "a2"),
		]),
		_always_rule(&"b", &"nested", [RecordingAction.new(trace, "nested")]),
		_always_rule(&"c", &"listener", [RecordingAction.new(trace, "listener")]),
	])
	assert_eq(engine.load_book(book), OK)
	engine.emit_event(&"start")
	assert_eq(trace, ["a1", "a2", "nested", "listener"])
	engine.action_executed.disconnect(listener)


func test_check_is_match_only_and_string_payload_keys_are_normalized() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var trace: Array = []
	var fired: Dictionary = {&"count": 0}
	engine.rule_fired.connect(func(_rule_value: RERule) -> void: fired.count += 1)
	var compare := RECompareCondition.new()
	compare.source = RECompareCondition.Source.PAYLOAD
	compare.key = &"mission"
	compare.value = "alpha"
	var query := _rule(&"query", &"", compare, [RecordingAction.new(trace, "query-action")])
	var reactive := _rule(&"reactive", &"go", compare, [RecordingAction.new(trace, "reactive")])
	assert_eq(engine.load_book(_book([query, reactive])), OK)
	assert_true(engine.check(&"query", {"mission": "alpha"}))
	assert_eq(trace, [])
	assert_eq(fired.count, 0)
	engine.emit_event(&"go", {"mission": "alpha"})
	assert_eq(trace, ["reactive"])
	assert_eq(fired.count, 1)


func test_shared_book_keeps_overrides_and_blackboards_per_engine() -> void:
	var first: Variant = _engine()
	var second: Variant = _engine()
	if first == null or second == null:
		return
	var trace: Array = []
	var rule := _always_rule(&"shared", &"go", [RecordingAction.new(trace, "fired")])
	var book := _book([rule])
	assert_eq(first.load_book(book), OK)
	assert_eq(second.load_book(book), OK)
	first.set_rule_enabled(&"shared", false)
	first.get_blackboard().set_value(&"only_first", true)
	first.emit_event(&"go")
	second.emit_event(&"go")
	assert_eq(trace, ["fired"])
	assert_false(second.get_blackboard().has_value(&"only_first"))
	assert_true(rule.enabled)


func test_nested_blackboard_values_do_not_alias_authored_resources_or_other_engines() -> void:
	var first: Variant = _engine()
	var second: Variant = _engine()
	if first == null or second == null:
		return
	var authored_value := {&"items": [{&"name": "original"}]}
	var set_value := RESetBlackboardAction.new()
	set_value.key = &"inventory"
	set_value.value = authored_value
	var book := _book([_always_rule(&"shared_collection", &"go", [set_value])])
	assert_eq(first.load_book(book), OK)
	assert_eq(second.load_book(book), OK)
	first.emit_event(&"go")
	second.emit_event(&"go")
	var first_value: Dictionary = first.get_blackboard().get_value(&"inventory")
	var second_value: Dictionary = second.get_blackboard().get_value(&"inventory")
	first_value[&"items"][0][&"name"] = "first-only"
	assert_eq(second_value[&"items"][0][&"name"], "original")
	assert_eq(authored_value[&"items"][0][&"name"], "original")


func test_actions_cannot_replace_the_shared_event_or_payload_view() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var observed: Dictionary = {}
	var tamper := RecordingAction.new([], "", &"", func(context: Variant) -> void:
		context.set(&"event", RERuleEvent.new(&"tampered"))
		context.set(&"payload", {&"value": "tampered"})
	)
	var observe := RecordingAction.new([], "", &"", func(context: Variant) -> void:
		observed.event = context.event.name
		observed.payload = context.payload[&"value"]
	)
	assert_eq(
		engine.load_book(_book([_always_rule(&"immutable_context", &"go", [tamper, observe])])),
		OK,
	)
	engine.emit_event(&"go", {&"value": "original"})
	assert_eq(observed, {&"event": &"go", &"payload": "original"})


func test_action_failure_clears_queue_and_later_dispatch_recovers() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var trace: Array = []
	var failures: Array = []
	engine.dispatch_failed.connect(func(reason: StringName, processed: int) -> void:
		failures.append([reason, processed])
	)
	var book := _book([
		_always_rule(&"a", &"start", [
			RecordingAction.new(trace, "failed", &"queued", Callable(), FAILED),
			RecordingAction.new(trace, "never"),
		]),
		_always_rule(&"b", &"queued", [RecordingAction.new(trace, "also-never")]),
		_always_rule(&"c", &"recover", [RecordingAction.new(trace, "recovered")]),
	])
	assert_eq(engine.load_book(book), OK)
	engine.emit_event(&"start")
	assert_push_error("action")
	assert_eq(trace, ["failed"])
	assert_eq(failures, [[&"action_failed", 1]])
	engine.emit_event(&"recover")
	assert_eq(trace, ["failed", "recovered"])
