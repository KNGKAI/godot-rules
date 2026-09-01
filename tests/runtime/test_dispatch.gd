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
	var packed_action := RESetBlackboardAction.new()
	packed_action.key = &"packed"
	packed_action.value = PackedStringArray(["original"])
	var resource_action := RESetBlackboardAction.new()
	resource_action.key = &"catalog"
	resource_action.value = RENameCatalog.new()
	resource_action.value.names.append(&"original")
	var shared_rule := RERule.new()
	shared_rule.id = &"authored_nested_rule"
	var authored_book := RERuleBook.new()
	authored_book.rules.assign([shared_rule, shared_rule])
	var shared_resource_action := RESetBlackboardAction.new()
	shared_resource_action.key = &"book"
	shared_resource_action.value = authored_book
	var mutable_book := _book([
		_always_rule(
			&"mutable_variants",
			&"mutable",
			[packed_action, resource_action, shared_resource_action],
		)
	])
	assert_eq(first.load_book(mutable_book), OK)
	assert_eq(second.load_book(mutable_book), OK)
	first.emit_event(&"mutable")
	second.emit_event(&"mutable")
	var first_packed: PackedStringArray = first.get_blackboard().get_value(&"packed")
	var second_packed: PackedStringArray = second.get_blackboard().get_value(&"packed")
	first_packed[0] = "first-only"
	assert_eq(second_packed[0], "original")
	assert_eq(packed_action.value[0], "original")
	var first_catalog: RENameCatalog = first.get_blackboard().get_value(&"catalog")
	var second_catalog: RENameCatalog = second.get_blackboard().get_value(&"catalog")
	first_catalog.names[0] = &"first-only"
	assert_eq(second_catalog.names[0], &"original")
	assert_eq(resource_action.value.names[0], &"original")
	var first_book: RERuleBook = first.get_blackboard().get_value(&"book")
	assert_not_same(first_book, authored_book)
	assert_same(first_book.rules[0], first_book.rules[1])
	assert_not_same(first_book.rules[0], shared_rule)
	first_book.rules[0].id = &"runtime_nested_rule"
	assert_eq(first_book.rules[1].id, &"runtime_nested_rule")
	assert_eq(shared_rule.id, &"authored_nested_rule")


func test_actions_cannot_replace_the_shared_event_or_payload_view() -> void:
	var engine: Variant = _engine()
	if engine == null:
		return
	var packed_payload := PackedStringArray(["original"])
	var resource_payload := RENameCatalog.new()
	resource_payload.names.append(&"original")
	var shared_names: Array[StringName] = [&"original"]
	var shared_resource := RENameCatalog.new()
	shared_resource.names = shared_names
	var key_resource := RENameCatalog.new()
	key_resource.names.append(&"original")
	var keyed_payload := {key_resource: true}
	var tampered_names: Array[StringName] = [&"tampered"]
	var observed: Dictionary = {}
	var tamper := RecordingAction.new([], "", &"", func(context: Variant) -> void:
		context.set(&"event", RERuleEvent.new(&"tampered"))
		context.set(&"payload", {&"value": "tampered"})
		context.event.set(&"name", &"tampered")
		context.event.set(&"payload", {&"value": "tampered"})
		context.event._name = &"tampered"
		context.event._payload = {&"value": "tampered"}
		context.payload[&"packed"][0] = "tampered"
		context.event.payload[&"resource"].names = tampered_names
		observed.direct_read_only = context.payload[&"shared_names"].is_read_only()
		observed.resource_read_only = context.payload[&"shared_resource"].names.is_read_only()
		observed.shared_identity = is_same(
			context.payload[&"shared_names"],
			context.payload[&"shared_resource"].names,
		)
		for key: RENameCatalog in context.payload[&"keyed"]:
			key.names = tampered_names
		context._event_name = &"tampered"
		context._payload = {&"value": "tampered"}
	)
	var observe := RecordingAction.new([], "", &"", func(context: Variant) -> void:
		observed.event = context.event.name
		observed.payload = context.payload[&"value"]
		observed.packed = context.payload[&"packed"][0]
		observed.resource = context.payload[&"resource"].names[0]
		for key: RENameCatalog in context.payload[&"keyed"]:
			observed.key_resource = key.names[0]
	)
	assert_eq(
		engine.load_book(_book([_always_rule(&"immutable_context", &"go", [tamper, observe])])),
		OK,
	)
	engine.emit_event(
		&"go",
		{
			&"value": "original",
			&"packed": packed_payload,
			&"resource": resource_payload,
			&"shared_resource": shared_resource,
			&"shared_names": shared_names,
			&"keyed": keyed_payload,
		},
	)
	assert_eq(
		observed,
		{
			&"event": &"go",
			&"payload": "original",
			&"packed": "original",
			&"resource": &"original",
			&"direct_read_only": true,
			&"resource_read_only": true,
			&"shared_identity": true,
			&"key_resource": &"original",
		},
	)
	assert_eq(packed_payload[0], "original")
	assert_eq(resource_payload.names[0], &"original")
	assert_eq(shared_names[0], &"original")
	assert_eq(key_resource.names[0], &"original")


func test_cyclic_blackboard_containers_are_copied_and_frozen_safely() -> void:
	var array_cycle: Array = []
	array_cycle.append(array_cycle)
	var dictionary_cycle: Dictionary = {}
	dictionary_cycle[&"self"] = dictionary_cycle
	var blackboard := REBlackboard.new()
	blackboard.set_value(&"array", array_cycle)
	blackboard.set_value(&"dictionary", dictionary_cycle)
	var copied_array: Array = blackboard.get_value(&"array")
	var copied_dictionary: Dictionary = blackboard.get_value(&"dictionary")
	assert_false(is_same(copied_array, array_cycle))
	assert_true(is_same(copied_array, copied_array[0]))
	assert_false(is_same(copied_dictionary, dictionary_cycle))
	assert_true(is_same(copied_dictionary, copied_dictionary[&"self"]))
	var snapshot := blackboard.snapshot()
	var frozen_array: Array = snapshot[&"array"]
	var frozen_dictionary: Dictionary = snapshot[&"dictionary"]
	assert_true(is_same(frozen_array, frozen_array[0]))
	assert_true(is_same(frozen_dictionary, frozen_dictionary[&"self"]))
	assert_true(frozen_array.is_read_only())
	assert_true(frozen_dictionary.is_read_only())


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
