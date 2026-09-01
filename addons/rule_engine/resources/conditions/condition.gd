@tool
class_name RECondition
extends Resource


func evaluate(_context: Variant) -> REConditionResult:
	return REConditionResult.new(false, false)

