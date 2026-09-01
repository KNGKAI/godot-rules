extends Node

signal mission_completed(mission_id: StringName)
signal business_unlock_requested(business_id: StringName)

const RULE_BOOK := preload("res://examples/basic/rules/business_unlock_rules.tres")
const BusinessManager := preload("res://examples/basic/business_manager.gd")

@export var auto_run: bool = true

var rule_engine := RERuleEngine.new()
var fired_rule_ids: Array[StringName] = []
var business_manager: Node


func _ready() -> void:
	business_manager = BusinessManager.new()
	add_child(business_manager)
	business_manager.business_unlock_requested.connect(business_unlock_requested.emit)
	mission_completed.connect(_on_mission_completed)
	rule_engine.event_received.connect(business_manager.accept_rule_event)
	rule_engine.rule_fired.connect(_on_rule_fired)
	rule_engine.set_fact_provider(
		REDictionaryFactProvider.new({&"player.reputation": 12})
	)
	var error := rule_engine.load_book(RULE_BOOK)
	if error != OK:
		push_error("Could not load the basic example rule book: %s" % error_string(error))
		return
	if auto_run:
		call_deferred("run_demo")


func run_demo() -> void:
	mission_completed.emit(&"first_steps")
	mission_completed.emit(&"first_steps")
	print(
		"BASIC_EXAMPLE: requested=%s fired=%s"
		% [business_manager.requested_business_ids, fired_rule_ids]
	)


func _on_mission_completed(mission_id: StringName) -> void:
	rule_engine.emit_event(&"mission_completed", {&"mission_id": mission_id})


func _on_rule_fired(rule: RERule) -> void:
	fired_rule_ids.append(rule.id)
