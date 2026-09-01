@tool
extends RefCounted

enum Severity { ERROR, WARNING }

var severity: Severity
var code: StringName
var message: String
var rule_id: StringName
var property_path: String


func _init(
	p_severity: Severity = Severity.ERROR,
	p_code: StringName = &"",
	p_message: String = "",
	p_rule_id: StringName = &"",
	p_property_path: String = "",
) -> void:
	severity = p_severity
	code = p_code
	message = p_message
	rule_id = p_rule_id
	property_path = p_property_path


func _to_string() -> String:
	return "%s [%s] %s: %s" % [
		"ERROR" if severity == Severity.ERROR else "WARNING",
		code,
		property_path,
		message,
	]

