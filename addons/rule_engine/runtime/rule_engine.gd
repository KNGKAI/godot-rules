class_name RERuleEngine
extends RefCounted

signal event_received(event: RERuleEvent)
signal rule_evaluated(rule: RERule, passed: bool)
signal rule_fired(rule: RERule)
signal action_executed(rule: RERule, action: REAction)
signal dispatch_failed(reason: StringName, processed_events: int)

var max_events_per_dispatch: int = 1000:
	set(value):
		max_events_per_dispatch = maxi(1, value)

var _books: Dictionary = {}
var _rules_by_id: Dictionary = {}
var _event_index: Dictionary = {}
var _enabled_overrides: Dictionary = {}
var _queue: Array[RERuleEvent] = []
var _draining: bool = false
var _blackboard := REBlackboard.new()
var _fact_provider: REFactProvider = REFactProvider.new()


func load_book(book: RERuleBook) -> Error:
	if book == null:
		return ERR_INVALID_PARAMETER
	var book_key := book.get_instance_id()
	if _books.has(book_key):
		return OK
	var validation := _validate_incoming_book(book)
	if validation != OK:
		return validation
	var owned_ids: Array[StringName] = []
	for rule: RERule in book.rules:
		_rules_by_id[rule.id] = rule
		owned_ids.append(rule.id)
		if rule.is_reactive():
			if not _event_index.has(rule.event):
				_event_index[rule.event] = []
			_event_index[rule.event].append(rule)
	_books[book_key] = {&"book": book, &"ids": owned_ids}
	return OK


func unload_book(book: RERuleBook) -> void:
	if book == null:
		return
	var book_key := book.get_instance_id()
	if not _books.has(book_key):
		return
	var entry: Dictionary = _books[book_key]
	for id: StringName in entry.ids:
		var rule: RERule = _rules_by_id.get(id)
		if rule != null and rule.is_reactive() and _event_index.has(rule.event):
			var candidates: Array = _event_index[rule.event]
			candidates.erase(rule)
			if candidates.is_empty():
				_event_index.erase(rule.event)
		_rules_by_id.erase(id)
		_enabled_overrides.erase(id)
	_books.erase(book_key)


func emit_event(name: StringName, payload: Dictionary = {}) -> void:
	if name.is_empty():
		push_error("Rule event name cannot be empty.")
		return
	var normalized := REMatchContext.normalize_payload(payload)
	if not normalized.valid:
		push_error("Rule event payload keys must be String or StringName values.")
		return
	_queue.append(RERuleEvent.new(name, normalized.value))
	if not _draining:
		_drain_queue()


func check(rule_id: StringName, payload: Dictionary = {}) -> bool:
	var rule: RERule = _rules_by_id.get(rule_id)
	if rule == null or rule.is_reactive() or not _is_effectively_enabled(rule):
		return false
	var normalized := REMatchContext.normalize_payload(payload)
	if not normalized.valid:
		return false
	var context := REMatchContext.new(normalized.value, _blackboard.snapshot(), _fact_provider)
	var result := rule.condition.evaluate(context)
	var passed := result.valid and result.matched
	rule_evaluated.emit(rule, passed)
	return passed


func get_rule(rule_id: StringName) -> RERule:
	return _rules_by_id.get(rule_id)


func set_fact_provider(provider: REFactProvider) -> void:
	_fact_provider = provider if provider != null else REFactProvider.new()


func set_rule_enabled(rule_id: StringName, enabled: bool) -> Error:
	if not _rules_by_id.has(rule_id):
		return ERR_DOES_NOT_EXIST
	_enabled_overrides[rule_id] = enabled
	return OK


func clear_rule_enabled_override(rule_id: StringName) -> void:
	_enabled_overrides.erase(rule_id)


func get_blackboard() -> REBlackboard:
	return _blackboard


func _validate_incoming_book(book: RERuleBook) -> Error:
	var seen_ids: Dictionary = {}
	var seen_resources: Dictionary = {}
	for rule: RERule in book.rules:
		if rule == null or rule.id.is_empty() or rule.condition == null:
			return ERR_INVALID_DATA
		var resource_key := rule.get_instance_id()
		if seen_resources.has(resource_key):
			return ERR_INVALID_DATA
		seen_resources[resource_key] = true
		if seen_ids.has(rule.id) or _rules_by_id.has(rule.id):
			return ERR_ALREADY_EXISTS
		seen_ids[rule.id] = true
		if rule.is_reactive() and rule.actions.is_empty():
			return ERR_INVALID_DATA
		for action: REAction in rule.actions:
			if action == null:
				return ERR_INVALID_DATA
	return OK


func _is_effectively_enabled(rule: RERule) -> bool:
	return _enabled_overrides.get(rule.id, rule.enabled)


func _drain_queue() -> void:
	_draining = true
	var processed_count := 0
	var last_event: StringName
	var failure_reason: StringName
	while not _queue.is_empty():
		if processed_count == max_events_per_dispatch:
			failure_reason = &"event_limit"
			_queue.clear()
			break
		var event: RERuleEvent = _queue.pop_front()
		processed_count += 1
		last_event = event.name
		failure_reason = _process_event(event)
		if not failure_reason.is_empty():
			_queue.clear()
			break
	_draining = false
	if failure_reason.is_empty():
		return
	dispatch_failed.emit(failure_reason, processed_count)
	if failure_reason == &"event_limit":
		push_error(
			"Rule event limit reached after %d events; last event was '%s'." %
			[processed_count, last_event]
		)
	else:
		push_error("Rule action failed after %d processed events." % processed_count)


func _process_event(event: RERuleEvent) -> StringName:
	event_received.emit(event)
	var candidates: Array = _event_index.get(event.name, []).duplicate()
	candidates.sort_custom(_rule_precedes)
	var context := REMatchContext.new(event.payload, _blackboard.snapshot(), _fact_provider)
	var passing: Array[RERule] = []
	for rule: RERule in candidates:
		if not _is_effectively_enabled(rule):
			continue
		var result := rule.condition.evaluate(context)
		var passed := result.valid and result.matched
		rule_evaluated.emit(rule, passed)
		if passed:
			passing.append(rule)
	var action_context := REActionContext.new(event, _blackboard, self)
	for rule: RERule in passing:
		for action: REAction in rule.actions:
			var error := action.execute(action_context)
			if error != OK:
				return &"action_failed"
			action_executed.emit(rule, action)
		rule_fired.emit(rule)
	return &""


func _rule_precedes(left: RERule, right: RERule) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	return String(left.id) < String(right.id)

