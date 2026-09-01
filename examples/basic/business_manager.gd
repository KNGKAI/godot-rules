extends Node

signal business_unlock_requested(business_id: StringName)

var requested_business_ids: Array[StringName] = []


func accept_rule_event(event: RERuleEvent) -> void:
	if event.name != &"business_unlock_requested":
		return
	var business_id := StringName(event.payload.get(&"business_id", &""))
	if business_id.is_empty():
		return
	requested_business_ids.append(business_id)
	business_unlock_requested.emit(business_id)
