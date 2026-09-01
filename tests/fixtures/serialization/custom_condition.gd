@tool
extends RECondition

@export var key: StringName


func evaluate(context: REMatchContext) -> REConditionResult:
	var lookup := context.lookup(REMatchContext.Source.PAYLOAD, key)
	return REConditionResult.new(lookup.present, true)

