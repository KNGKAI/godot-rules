extends GutTest

const FILTER_PATH := "res://addons/rule_engine/editor/main_screen/rule_filter.gd"
const MENU_PATH := "res://addons/rule_engine/editor/main_screen/type_menu_model.gd"
const CONTROLLER_PATH := "res://addons/rule_engine/editor/main_screen/workspace_controller.gd"
const VALIDATOR_PATH := "res://addons/rule_engine/editor/validation/validator.gd"
const COMMAND_SERVICE_PATH := "res://addons/rule_engine/editor/rule_command_service.gd"
const EMIT_ACTION_PATH := "res://addons/rule_engine/resources/actions/emit_event.gd"
const CUSTOM_ACTION_PATH := "res://tests/fixtures/serialization/custom_action.gd"
const NON_TOOL_CONDITION_PATH := "res://tests/fixtures/custom_types/non_tool_condition.gd"


func _rule(id: StringName, event: StringName, tags: PackedStringArray) -> RERule:
	var rule := RERule.new()
	rule.id = id
	rule.event = event
	rule.tags = tags
	return rule


func _book_entry(path: String, rules: Array[RERule]) -> Dictionary:
	var book := RERuleBook.new()
	book.rules = rules
	return {&"path": path, &"book": book}


func _filtered_ids(groups: Array) -> Array:
	var ids: Array = []
	for group: Dictionary in groups:
		for entry: Dictionary in group.books:
			for rule: RERule in entry.rules:
				ids.append(rule.id)
	return ids


func test_filter_matches_id_event_or_any_tag_case_insensitively() -> void:
	var script: Script = load(FILTER_PATH)
	assert_not_null(script)
	if script == null:
		return
	var groups: Array[Dictionary] = [
		{&"directory": "res://first", &"books": [
			_book_entry("res://first/one.tres", [
				_rule(&"Unlock_Door", &"player_arrived", PackedStringArray(["world"])),
				_rule(&"grant_reward", &"quest_done", PackedStringArray(["Rare", "loot"])),
			]),
		]},
		{&"directory": "res://second", &"books": [
			_book_entry("res://second/two.res", [
				_rule(&"ambient", &"night_started", PackedStringArray(["audio"])),
			]),
		]},
	]
	var model: Variant = script.new()
	assert_eq(_filtered_ids(model.filter(groups, "unlock")), [&"Unlock_Door"])
	assert_eq(_filtered_ids(model.filter(groups, "QUEST_DONE")), [&"grant_reward"])
	assert_eq(_filtered_ids(model.filter(groups, "rArE")), [&"grant_reward"])
	assert_eq(_filtered_ids(model.filter(groups, "")), [
		&"Unlock_Door", &"grant_reward", &"ambient",
	])
	assert_true(model.filter(groups, "missing").is_empty())


func test_menu_combines_core_and_registry_types_and_disables_non_tool_scripts() -> void:
	var script: Script = load(MENU_PATH)
	assert_not_null(script)
	if script == null:
		return
	var condition_types: Array[Dictionary] = [{
		&"name": &"RETestNonToolCondition",
		&"path": NON_TOOL_CONDITION_PATH,
		&"script": load(NON_TOOL_CONDITION_PATH),
		&"tool": false,
		&"warning": "RETestNonToolCondition must declare @tool.",
	}]
	var action_types: Array[Dictionary] = [{
		&"name": &"RETestCustomAction",
		&"path": CUSTOM_ACTION_PATH,
		&"script": load(CUSTOM_ACTION_PATH),
		&"tool": true,
		&"warning": "",
	}]
	var model: Variant = script.new(condition_types, action_types)
	var conditions: Array = model.get_condition_entries()
	var actions: Array = model.get_action_entries()
	assert_has(conditions.map(func(entry: Dictionary) -> StringName: return entry.name), &"RECompareCondition")
	assert_has(actions.map(func(entry: Dictionary) -> StringName: return entry.name), &"REEmitEventAction")
	assert_has(actions.map(func(entry: Dictionary) -> StringName: return entry.name), &"RETestCustomAction")
	var non_tool: Dictionary = conditions.filter(
		func(entry: Dictionary) -> bool: return entry.name == &"RETestNonToolCondition"
	)[0]
	assert_false(non_tool.enabled)
	assert_string_contains(non_tool.tooltip, "@tool")
	assert_eq(
		conditions.map(func(entry: Dictionary) -> String: return String(entry.name)),
		[
			"REAllCondition",
			"REAnyCondition",
			"RECompareCondition",
			"REExistsCondition",
			"RENotCondition",
			"RETestNonToolCondition",
		],
	)


class FakeDiscovery extends RefCounted:
	var books: Array[RERuleBook]

	func _init(p_books: Array[RERuleBook]) -> void:
		books = p_books

	func get_books() -> Array[RERuleBook]:
		return books.duplicate()


func test_controller_emits_only_valid_book_rule_condition_and_action_selections() -> void:
	var script: Script = load(CONTROLLER_PATH)
	assert_not_null(script)
	if script == null:
		return
	var condition := REExistsCondition.new()
	var action := REEmitEventAction.new()
	var rule := _rule(&"selectable", &"event", PackedStringArray())
	rule.condition = condition
	rule.actions = [action]
	var book := RERuleBook.new()
	book.rules = [rule]
	var controller: Variant = script.new(FakeDiscovery.new([book]), null, null)
	var inspected: Array[Resource] = []
	controller.inspect_requested.connect(func(resource: Resource) -> void: inspected.append(resource))
	assert_true(controller.select_book(book))
	assert_true(controller.select_rule(rule))
	assert_true(controller.select_condition(condition))
	assert_true(controller.select_action(0))
	assert_eq(inspected, [book, rule, condition, action])
	assert_false(controller.select_rule(_rule(&"foreign", &"", PackedStringArray())))
	assert_false(controller.select_condition(REExistsCondition.new()))
	assert_false(controller.select_action(4))
	assert_eq(inspected, [book, rule, condition, action])


func test_controller_returns_shared_validation_issues_and_navigates_to_issue_rule() -> void:
	var controller_script: Script = load(CONTROLLER_PATH)
	var validator_script: Script = load(VALIDATOR_PATH)
	assert_not_null(controller_script)
	assert_not_null(validator_script)
	if controller_script == null or validator_script == null:
		return
	var broken := RERule.new()
	broken.id = &"broken"
	var book := RERuleBook.new()
	book.rules = [broken]
	var controller: Variant = controller_script.new(
		FakeDiscovery.new([book]),
		null,
		validator_script.new(),
	)
	var navigation: Array[Dictionary] = []
	controller.issue_activated.connect(
		func(rule: RERule, property_path: String) -> void:
			navigation.append({&"rule": rule, &"property_path": property_path})
	)
	var issues: Array = controller.validate()
	assert_gt(issues.size(), 0)
	var missing_condition_index := -1
	for index: int in issues.size():
		if issues[index].code == &"missing_condition":
			missing_condition_index = index
			break
	assert_ne(missing_condition_index, -1)
	if missing_condition_index == -1:
		return
	var issue: Variant = issues[missing_condition_index]
	assert_eq(issue.rule, broken)
	assert_eq(issue.rule_id, &"broken")
	assert_eq(issue.property_path, "books[0].rules[0].condition")
	assert_true(controller.activate_issue(missing_condition_index))
	assert_eq(controller.get_selected_book(), book)
	assert_eq(controller.get_selected_rule(), broken)
	assert_eq(navigation, [{
		&"rule": broken,
		&"property_path": "books[0].rules[0].condition",
	}])
	assert_false(controller.activate_issue(issues.size()))


func _ignore_persistence(_resource: Resource) -> void:
	pass


func test_controller_structural_operations_use_undoable_commands_and_empty_state_is_safe() -> void:
	var controller_script: Script = load(CONTROLLER_PATH)
	var command_script: Script = load(COMMAND_SERVICE_PATH)
	assert_not_null(controller_script)
	assert_not_null(command_script)
	if controller_script == null or command_script == null:
		return
	var undo_redo := UndoRedo.new()
	var commands: Variant = command_script.new(undo_redo, _ignore_persistence)
	var rule := _rule(&"editable", &"event", PackedStringArray())
	var book := RERuleBook.new()
	book.rules = [rule]
	book.take_over_path("res://data/gameplay/book.tres")
	var controller: Variant = controller_script.new(FakeDiscovery.new([book]), commands, null)
	assert_false(controller.unlink_selected_rule())
	assert_false(controller.add_action(load(EMIT_ACTION_PATH)))
	assert_true(controller.select_rule(rule))
	assert_eq(controller.get_default_rules_directory(), "res://data/gameplay/rules")
	assert_true(controller.add_action(load(EMIT_ACTION_PATH)))
	assert_eq(rule.actions.size(), 1)
	undo_redo.undo()
	assert_true(rule.actions.is_empty())
	undo_redo.redo()
	assert_eq(rule.actions.size(), 1)
	assert_true(controller.unlink_selected_rule())
	assert_true(book.rules.is_empty())
	assert_null(controller.get_selected_rule())
	undo_redo.undo()
	assert_eq(book.rules, [rule])
	undo_redo.clear_history()
	controller.stop()
	undo_redo.free()
