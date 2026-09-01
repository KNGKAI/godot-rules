extends GutTest

const EXAMPLE_SCENE := "res://examples/basic/main.tscn"
const EXAMPLE_BOOK := "res://examples/basic/rules/business_unlock_rules.tres"


func test_mission_signal_emits_one_business_request_with_a_stable_rule_trace() -> void:
	var scene: PackedScene = load(EXAMPLE_SCENE)
	assert_not_null(scene)
	if scene == null:
		return
	var example: Node = scene.instantiate()
	example.set("auto_run", false)
	add_child_autofree(example)
	await get_tree().process_frame
	var business_ids: Array[StringName] = []
	example.business_unlock_requested.connect(
		func(business_id: StringName) -> void: business_ids.append(business_id)
	)
	example.mission_completed.emit(&"first_steps")
	example.mission_completed.emit(&"first_steps")
	assert_eq(business_ids, [&"boutique"])
	assert_eq(example.get("fired_rule_ids"), [&"unlock_boutique"])
	var engine: RERuleEngine = example.get("rule_engine")
	assert_true(engine.get_blackboard().get_value(&"business_unlocked:boutique", false))


func test_example_rules_use_data_actions_instead_of_scene_path_mutation() -> void:
	var book: RERuleBook = load(EXAMPLE_BOOK)
	assert_not_null(book)
	if book == null:
		return
	assert_eq(book.rules.size(), 1)
	assert_eq(book.rules[0].actions.size(), 2)
	assert_is(book.rules[0].actions[0], RESetBlackboardAction)
	assert_is(book.rules[0].actions[1], REEmitEventAction)
