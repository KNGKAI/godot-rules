class_name RERuleEvent
extends RefCounted

var name: StringName
var payload: Dictionary


func _init(p_name: StringName = &"", p_payload: Dictionary = {}) -> void:
	name = p_name
	payload = p_payload

