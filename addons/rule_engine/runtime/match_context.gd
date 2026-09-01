class_name REMatchContext
extends RefCounted

enum Source { FACT, PAYLOAD, BLACKBOARD }

var payload: Dictionary
var blackboard: Dictionary
var _provider: REFactProvider
var _fact_cache: Dictionary = {}


func _init(
	p_payload: Dictionary = {},
	p_blackboard: Dictionary = {},
	p_provider: REFactProvider = null,
) -> void:
	var normalized := normalize_payload(p_payload)
	payload = normalized.value if normalized.valid else freeze_dictionary({})
	blackboard = freeze_dictionary(p_blackboard)
	_provider = p_provider if p_provider != null else REFactProvider.new()


static func normalize_payload(source: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for raw_key: Variant in source:
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return {&"valid": false, &"value": {}}
		normalized[StringName(raw_key)] = freeze_value(source[raw_key])
	normalized.make_read_only()
	return {&"valid": true, &"value": normalized}


static func freeze_dictionary(source: Dictionary) -> Dictionary:
	var frozen: Dictionary = {}
	for key: Variant in source:
		frozen[key] = freeze_value(source[key])
	frozen.make_read_only()
	return frozen


static func freeze_value(value: Variant) -> Variant:
	if value is Dictionary:
		return freeze_dictionary(value)
	if value is Array:
		var frozen_array: Array = []
		for item: Variant in value:
			frozen_array.append(freeze_value(item))
		frozen_array.make_read_only()
		return frozen_array
	return value


static func duplicate_mutable_value(value: Variant) -> Variant:
	if value is Dictionary:
		var duplicated_dictionary: Dictionary = {}
		for key: Variant in value:
			duplicated_dictionary[key] = duplicate_mutable_value(value[key])
		return duplicated_dictionary
	if value is Array:
		var duplicated_array: Array = []
		for item: Variant in value:
			duplicated_array.append(duplicate_mutable_value(item))
		return duplicated_array
	return value


func lookup(source: int, key: StringName) -> Dictionary:
	match source:
		Source.FACT:
			return _lookup_fact(key)
		Source.PAYLOAD:
			return _lookup_dictionary(payload, key)
		Source.BLACKBOARD:
			return _lookup_dictionary(blackboard, key)
		_:
			return {&"present": false, &"value": null}


func _lookup_fact(key: StringName) -> Dictionary:
	if _fact_cache.has(key):
		return _fact_cache[key]
	var present := _provider.has_fact(key)
	var result := {
		&"present": present,
		&"value": freeze_value(_provider.get_fact(key)) if present else null,
	}
	_fact_cache[key] = result
	return result


func _lookup_dictionary(values: Dictionary, key: StringName) -> Dictionary:
	var present := values.has(key)
	return {
		&"present": present,
		&"value": values.get(key) if present else null,
	}
