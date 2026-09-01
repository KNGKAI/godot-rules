class_name REActionContext
extends RefCounted

var event: RERuleEvent
var payload: Dictionary
var blackboard: REBlackboard
var _engine: Variant


func _init(
	p_event: RERuleEvent = null,
	p_blackboard: REBlackboard = null,
	p_engine: Variant = null,
) -> void:
	event = p_event
	payload = p_event.payload if p_event != null else REMatchContext.freeze_dictionary({})
	blackboard = p_blackboard
	_engine = p_engine


func emit_event(name: StringName, p_payload: Dictionary = {}) -> void:
	if _engine != null:
		_engine.emit_event(name, p_payload)

