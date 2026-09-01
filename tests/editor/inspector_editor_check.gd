@tool
extends SceneTree

const InspectorPlugin := preload(
	"res://addons/rule_engine/editor/inspector/rule_inspector_plugin.gd"
)
const VariantProperty := preload(
	"res://addons/rule_engine/editor/inspector/variant_editor_property.gd"
)


func _init() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	await create_timer(1.0).timeout
	var failed := false
	if not Engine.is_editor_hint():
		push_error("Inspector check was not launched in editor mode.")
		failed = true
	var plugin: EditorInspectorPlugin = InspectorPlugin.new()
	if not plugin._can_handle(RECompareCondition.new()):
		push_error("Inspector plugin did not handle RECompareCondition.")
		failed = true
	if plugin._can_handle(RERule.new()):
		push_error("Inspector plugin handled an unrelated RERule.")
		failed = true
	var property: EditorProperty = VariantProperty.new()
	property.call("setup")
	var captured: Dictionary = {&"value": null, &"count": 0}
	property.property_changed.connect(
		func(_name: StringName, value: Variant, _field: StringName, _changing: bool) -> void:
			captured.value = value
			captured.count += 1
	)
	var input: LineEdit
	for child: Node in property.get_children():
		if child is LineEdit:
			input = child
			break
	if input == null:
		push_error("Variant EditorProperty did not create its LineEdit.")
		failed = true
	else:
		input.text_submitted.emit("42")
		if captured.count != 1 or captured.value != 42:
			push_error("Variant EditorProperty did not emit parsed integer 42.")
			failed = true
	property.free()
	if not failed:
		print("EDITOR_INSPECTOR_CHECK: PASS")
		quit()
	else:
		quit(1)
