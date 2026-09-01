@tool
extends REAction

@export var marker: StringName


func execute(context: REActionContext) -> Error:
	context.blackboard.set_value(marker, true)
	return OK

