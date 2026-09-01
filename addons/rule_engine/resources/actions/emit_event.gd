@tool
class_name REEmitEventAction
extends REAction

@export var event: StringName
@export var payload: Dictionary = {}


func execute(context: REActionContext) -> Error:
	if event.is_empty():
		return ERR_INVALID_PARAMETER
	context.emit_event(event, payload)
	return OK

