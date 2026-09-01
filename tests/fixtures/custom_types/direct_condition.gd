@tool
class_name RETestDirectCondition
extends RECondition


func evaluate(_context: REMatchContext) -> REConditionResult:
	return REConditionResult.new(true, true)

