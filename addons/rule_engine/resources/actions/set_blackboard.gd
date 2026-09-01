@tool
class_name RESetBlackboardAction
extends REAction

@export var key: StringName
@export var value: Variant


func execute(context: REActionContext) -> Error:
	if key.is_empty():
		return ERR_INVALID_PARAMETER
	context.blackboard.set_value(key, value)
	return OK

