extends GutTest

const SERVICE_PATH := "res://addons/rule_engine/editor/rule_command_service.gd"
const COMPARE_PATH := "res://addons/rule_engine/resources/conditions/compare.gd"
const ALL_PATH := "res://addons/rule_engine/resources/conditions/all.gd"
const ANY_PATH := "res://addons/rule_engine/resources/conditions/any.gd"
const NOT_PATH := "res://addons/rule_engine/resources/conditions/not.gd"
const CUSTOM_CONDITION_PATH := "res://tests/fixtures/serialization/custom_condition.gd"
const EMIT_ACTION_PATH := "res://addons/rule_engine/resources/actions/emit_event.gd"
const CUSTOM_ACTION_PATH := "res://tests/fixtures/serialization/custom_action.gd"
const NON_TOOL_CONDITION_PATH := "res://tests/fixtures/custom_types/non_tool_condition.gd"
const UNRELATED_PATH := "res://tests/fixtures/custom_types/unrelated_resource.gd"
const DUPLICATE_PATH := "res://.tools/rule_command_service_duplicate.tres"
const CREATED_PATH := "res://.tools/rule_command_service_created.tres"
const EXTERNAL_CONDITION_PATH := "res://.tools/rule_command_service_external_condition.tres"
const EXTERNAL_ACTION_PATH := "res://.tools/rule_command_service_external_action.tres"
const EXTERNAL_SOURCE_PATH := "res://.tools/rule_command_service_external_source.tres"
const MISSING_DIRECTORY := "res://.tools/task4_missing_rules"
const MISSING_DIRECTORY_RULE_PATH := MISSING_DIRECTORY + "/created.tres"

var _undo_redo: UndoRedo
var _service: Variant
var _persisted: Array[Resource]
var _refresh_count := 0
var _resource_changed_count := 0


class EditorStyleUndoRedo extends RefCounted:
	var _current_do: Callable
	var _current_undo: Callable
	var _undo_stack: Array[Dictionary] = []
	var _redo_stack: Array[Dictionary] = []

	func create_action(_name: String) -> void:
		_current_do = Callable()
		_current_undo = Callable()

	func add_do_method(object: Object, method_name: StringName, operation: Callable, resources: Array) -> void:
		_current_do = Callable(object, method_name).bind(operation, resources)

	func add_undo_method(object: Object, method_name: StringName, operation: Callable, resources: Array) -> void:
		_current_undo = Callable(object, method_name).bind(operation, resources)

	func commit_action() -> void:
		_current_do.call()
		_undo_stack.append({&"do": _current_do, &"undo": _current_undo})
		_redo_stack.clear()

	func undo() -> void:
		var action: Dictionary = _undo_stack.pop_back()
		action.undo.call()
		_redo_stack.append(action)

	func redo() -> void:
		var action: Dictionary = _redo_stack.pop_back()
		action.do.call()
		_undo_stack.append(action)


func before_each() -> void:
	_remove_duplicate_file()
	_undo_redo = UndoRedo.new()
	_persisted = []
	_refresh_count = 0
	_resource_changed_count = 0
	var script: Script = load(SERVICE_PATH)
	assert_not_null(script)
	if script == null:
		return
	_service = script.new(_undo_redo, _record_persist)
	_service.changed.connect(_record_refresh)


func after_each() -> void:
	if _undo_redo != null:
		_undo_redo.clear_history()
	_service = null
	_undo_redo = null
	_remove_duplicate_file()


func _remove_duplicate_file() -> void:
	for path: String in [DUPLICATE_PATH, CREATED_PATH, EXTERNAL_CONDITION_PATH, EXTERNAL_ACTION_PATH, EXTERNAL_SOURCE_PATH, MISSING_DIRECTORY_RULE_PATH]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
	var absolute_directory := ProjectSettings.globalize_path(MISSING_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func _record_persist(resource: Resource) -> void:
	_persisted.append(resource)


func _record_refresh() -> void:
	_refresh_count += 1


func _record_resource_changed() -> void:
	_resource_changed_count += 1


func test_shutdown_releases_dependencies_and_makes_retained_history_callbacks_inert() -> void:
	var manager := EditorStyleUndoRedo.new()
	var script: Script = load(SERVICE_PATH)
	var retained_service: Variant = script.new(manager, _record_persist)
	var rule := _rule(&"before_shutdown")
	assert_true(retained_service.set_rule_id(rule, &"after_shutdown"))
	assert_eq(rule.id, &"after_shutdown")
	var persisted_before_shutdown := _persisted.size()

	retained_service.shutdown()
	assert_true(retained_service.is_shutdown())
	assert_false(retained_service.set_rule_id(rule, &"rejected_after_shutdown"))
	manager.undo()
	assert_eq(rule.id, &"after_shutdown", "retained undo callbacks must become inert")
	manager.redo()
	assert_eq(rule.id, &"after_shutdown", "retained redo callbacks must become inert")
	assert_eq(_persisted.size(), persisted_before_shutdown)


func _save_external(resource: Resource) -> void:
	if not resource.resource_path.is_empty():
		ResourceSaver.save(resource, resource.resource_path)


func _rule(id: StringName = &"rule") -> RERule:
	var rule := RERule.new()
	rule.id = id
	return rule


func _book(rules: Array[RERule] = []) -> RERuleBook:
	var book := RERuleBook.new()
	book.rules = rules
	return book


func test_add_and_unlink_rule_are_undoable_and_reject_no_ops() -> void:
	if _service == null:
		return
	var rule := _rule()
	var book := _book()
	assert_true(_service.add_rule(book, rule))
	assert_eq(book.rules, [rule])
	assert_eq(_persisted, [book])
	assert_eq(_refresh_count, 1)
	assert_false(_service.add_rule(book, rule), "linking an existing rule is a no-op")
	assert_eq(_refresh_count, 1)
	_undo_redo.undo()
	assert_true(book.rules.is_empty())
	assert_eq(_persisted, [book, book])
	assert_eq(_refresh_count, 2)
	_undo_redo.redo()
	assert_eq(book.rules, [rule])
	assert_eq(_persisted, [book, book, book])
	assert_eq(_refresh_count, 3)
	assert_true(_service.unlink_rule(book, rule))
	assert_true(book.rules.is_empty())
	_undo_redo.undo()
	assert_eq(book.rules, [rule])
	_undo_redo.redo()
	assert_true(book.rules.is_empty())
	_undo_redo.undo()
	assert_eq(book.rules, [rule])
	assert_true(_service.unlink_rule(book, rule))
	assert_false(_service.unlink_rule(book, rule), "unlinking an absent rule is a no-op")


func test_rule_field_commands_restore_exact_old_and_new_values() -> void:
	if _service == null:
		return
	var rule := _rule(&"old")
	rule.event = &"before"
	rule.priority = 3
	rule.enabled = true
	rule.tags = PackedStringArray(["one"])
	var cases: Array[Dictionary] = [
		{&"method": &"set_rule_id", &"property": &"id", &"new": &"new"},
		{&"method": &"set_rule_event", &"property": &"event", &"new": &"after"},
		{&"method": &"set_rule_priority", &"property": &"priority", &"new": 7},
		{&"method": &"set_rule_enabled", &"property": &"enabled", &"new": false},
		{&"method": &"set_rule_tags", &"property": &"tags", &"new": PackedStringArray(["two", "three"])},
	]
	for item: Dictionary in cases:
		var old_value: Variant = rule.get(item.property)
		assert_true(_service.call(item.method, rule, item.new))
		assert_eq(rule.get(item.property), item.new)
		_undo_redo.undo()
		assert_eq(rule.get(item.property), old_value)
		_undo_redo.redo()
		assert_eq(rule.get(item.property), item.new)
		assert_false(_service.call(item.method, rule, item.new), "unchanged fields are rejected")
	assert_eq(_persisted.size(), cases.size() * 3)
	assert_eq(_refresh_count, cases.size() * 3)


func test_do_undo_redo_mark_the_resource_changed() -> void:
	if _service == null:
		return
	var rule := _rule(&"before")
	rule.changed.connect(_record_resource_changed)
	assert_true(_service.set_rule_id(rule, &"after"))
	assert_eq(_resource_changed_count, 1)
	_undo_redo.undo()
	assert_eq(_resource_changed_count, 2)
	_undo_redo.redo()
	assert_eq(_resource_changed_count, 3)


func test_editor_style_undo_redo_api_executes_real_mutations() -> void:
	var script: Script = load(SERVICE_PATH)
	var manager := EditorStyleUndoRedo.new()
	var service: Variant = script.new(manager, _record_persist)
	var rule := _rule(&"before")
	assert_true(service.set_rule_id(rule, &"after"))
	assert_eq(rule.id, &"after")
	manager.undo()
	assert_eq(rule.id, &"before")
	manager.redo()
	assert_eq(rule.id, &"after")


func test_set_replace_and_remove_conditions_at_root_and_nested_paths() -> void:
	if _service == null:
		return
	var rule := _rule()
	assert_true(_service.set_condition(rule, "condition", load(CUSTOM_CONDITION_PATH)))
	var custom: RECondition = rule.condition
	assert_not_null(custom)
	assert_eq(custom.get_script(), load(CUSTOM_CONDITION_PATH))
	_undo_redo.undo()
	assert_null(rule.condition)
	_undo_redo.redo()
	assert_eq(rule.condition, custom)

	var root := REAllCondition.new()
	root.conditions = [REExistsCondition.new(), RENotCondition.new()]
	(root.conditions[1] as RENotCondition).condition = REExistsCondition.new()
	rule.condition = root
	var old_nested: RECondition = (root.conditions[1] as RENotCondition).condition
	assert_true(_service.replace_condition(
		rule,
		"condition.conditions[1].condition",
		load(COMPARE_PATH),
	))
	var replacement: RECondition = (root.conditions[1] as RENotCondition).condition
	assert_true(replacement is RECompareCondition)
	_undo_redo.undo()
	assert_eq((root.conditions[1] as RENotCondition).condition, old_nested)
	_undo_redo.redo()
	assert_eq((root.conditions[1] as RENotCondition).condition, replacement)
	assert_true(_service.remove_condition(rule, "condition.conditions[1].condition"))
	assert_null((root.conditions[1] as RENotCondition).condition)
	_undo_redo.undo()
	assert_eq((root.conditions[1] as RENotCondition).condition, replacement)
	_undo_redo.redo()
	assert_null((root.conditions[1] as RENotCondition).condition)


func test_append_condition_adds_first_and_later_composite_children_with_undo_redo() -> void:
	if _service == null:
		return
	var root := REAllCondition.new()
	var rule := _rule()
	rule.condition = root
	assert_true(_service.append_condition(rule, "condition", load(COMPARE_PATH)))
	assert_eq(root.conditions.size(), 1)
	assert_true(root.conditions[0] is RECompareCondition)
	var first: RECondition = root.conditions[0]
	_undo_redo.undo()
	assert_true(root.conditions.is_empty())
	_undo_redo.redo()
	assert_eq(root.conditions, [first])
	assert_true(_service.append_condition(rule, "condition", load(CUSTOM_CONDITION_PATH)))
	assert_eq(root.conditions.size(), 2)
	assert_eq(root.conditions[0], first)
	assert_eq(root.conditions[1].get_script(), load(CUSTOM_CONDITION_PATH))
	_undo_redo.undo()
	assert_eq(root.conditions, [first])
	_undo_redo.redo()
	assert_eq(root.conditions.size(), 2)


func test_set_condition_child_fills_empty_not_and_null_composite_slots_with_undo_redo() -> void:
	if _service == null:
		return
	var empty_not := RENotCondition.new()
	var root := REAnyCondition.new()
	root.conditions = [empty_not, null]
	var rule := _rule()
	rule.condition = root
	assert_true(_service.set_condition_child(rule, "condition.conditions[0]", -1, load(COMPARE_PATH)))
	assert_true(empty_not.condition is RECompareCondition)
	var not_child: RECondition = empty_not.condition
	_undo_redo.undo()
	assert_null(empty_not.condition)
	_undo_redo.redo()
	assert_eq(empty_not.condition, not_child)
	assert_true(_service.set_condition_child(rule, "condition", 1, load(CUSTOM_CONDITION_PATH)))
	assert_eq(root.conditions[1].get_script(), load(CUSTOM_CONDITION_PATH))
	var composite_child: RECondition = root.conditions[1]
	_undo_redo.undo()
	assert_null(root.conditions[1])
	_undo_redo.redo()
	assert_eq(root.conditions[1], composite_child)
	assert_false(_service.set_condition_child(rule, "condition", 0, load(COMPARE_PATH)))
	assert_false(_service.set_condition_child(rule, "condition.conditions[0]", -1, load(COMPARE_PATH)))


func test_wrap_condition_and_convert_all_any_preserve_children_through_undo_redo() -> void:
	if _service == null:
		return
	var child := REExistsCondition.new()
	var nested := REAllCondition.new()
	nested.conditions = [child]
	var root := REAllCondition.new()
	root.conditions = [nested]
	var rule := _rule()
	rule.condition = root
	assert_true(_service.wrap_condition(rule, "condition.conditions[0].conditions[0]", load(NOT_PATH)))
	var wrapper: RENotCondition = nested.conditions[0]
	assert_not_null(wrapper)
	assert_eq(wrapper.condition, child)
	_undo_redo.undo()
	assert_eq(nested.conditions[0], child)
	_undo_redo.redo()
	assert_eq(nested.conditions[0], wrapper)

	assert_true(_service.convert_all_any(rule, "condition"))
	var converted: REAnyCondition = rule.condition
	assert_not_null(converted)
	assert_eq(converted.conditions, [nested])
	_undo_redo.undo()
	assert_eq(rule.condition, root)
	_undo_redo.redo()
	assert_eq(rule.condition, converted)
	assert_true(_service.convert_all_any(rule, "condition"))
	assert_true(rule.condition is REAllCondition)
	_undo_redo.undo()
	assert_eq(rule.condition, converted)
	_undo_redo.redo()
	assert_true(rule.condition is REAllCondition)


func test_condition_commands_reject_stale_invalid_paths_and_bad_scripts_without_history() -> void:
	if _service == null:
		return
	var rule := _rule()
	var root := REAllCondition.new()
	root.conditions = [REExistsCondition.new()]
	rule.condition = root
	assert_false(_service.remove_condition(rule, "condition.conditions[2]"))
	assert_false(_service.remove_condition(rule, "condition.condition"))
	assert_false(_service.remove_condition(rule, "conditions[0]"))
	assert_false(_service.replace_condition(rule, "condition.conditions[0]", load(NON_TOOL_CONDITION_PATH)))
	assert_false(_service.replace_condition(rule, "condition.conditions[0]", load(UNRELATED_PATH)))
	assert_false(_service.wrap_condition(rule, "condition.conditions[0]", load(COMPARE_PATH)), "only composite or not conditions can wrap")
	assert_false(_service.convert_all_any(rule, "condition.conditions[0]"))
	assert_false(_undo_redo.has_undo())
	assert_eq(root.conditions.size(), 1)


func test_condition_paths_reject_empty_segments_without_creating_history() -> void:
	if _service == null:
		return
	var root := REAllCondition.new()
	root.conditions = [REExistsCondition.new()]
	var rule := _rule()
	rule.condition = root
	assert_false(_service.remove_condition(rule, "condition."))
	assert_false(_service.remove_condition(rule, "condition..conditions[0]"))
	assert_false(_undo_redo.has_undo())
	assert_eq(rule.condition, root)
	assert_eq(root.conditions.size(), 1)


func test_formerly_valid_condition_path_is_rejected_after_tree_replacement() -> void:
	if _service == null:
		return
	var root := REAllCondition.new()
	root.conditions = [REExistsCondition.new()]
	var rule := _rule()
	rule.condition = root
	rule.condition = REExistsCondition.new()
	assert_false(_service.remove_condition(rule, "condition.conditions[0]"))
	assert_false(_undo_redo.has_undo())


func test_add_and_remove_core_and_custom_actions_are_undoable() -> void:
	if _service == null:
		return
	var rule := _rule()
	assert_true(_service.add_action(rule, load(EMIT_ACTION_PATH)))
	var core: REAction = rule.actions[0]
	assert_true(core is REEmitEventAction)
	assert_true(_service.add_action(rule, load(CUSTOM_ACTION_PATH), 0))
	var custom: REAction = rule.actions[0]
	assert_eq(custom.get_script(), load(CUSTOM_ACTION_PATH))
	assert_eq(rule.actions, [custom, core])
	_undo_redo.undo()
	assert_eq(rule.actions, [core])
	_undo_redo.redo()
	assert_eq(rule.actions, [custom, core])
	assert_true(_service.remove_action(rule, 1))
	assert_eq(rule.actions, [custom])
	_undo_redo.undo()
	assert_eq(rule.actions, [custom, core])
	_undo_redo.redo()
	assert_eq(rule.actions, [custom])


func test_action_reorder_is_deterministic_and_rejects_invalid_or_no_op_moves() -> void:
	if _service == null:
		return
	var first := REEmitEventAction.new()
	first.event = &"first"
	var second := REEmitEventAction.new()
	second.event = &"second"
	var third := REEmitEventAction.new()
	third.event = &"third"
	var rule := _rule()
	rule.actions = [first, second, third]
	assert_false(_service.move_action(rule, -1, 1))
	assert_false(_service.move_action(rule, 0, 3))
	assert_false(_service.move_action(rule, 1, 1))
	assert_false(_undo_redo.has_undo())
	assert_true(_service.move_action(rule, 0, 2))
	assert_eq(rule.actions, [second, third, first])
	_undo_redo.undo()
	assert_eq(rule.actions, [first, second, third])
	_undo_redo.redo()
	assert_eq(rule.actions, [second, third, first])
	assert_false(_service.add_action(rule, load(NON_TOOL_CONDITION_PATH)))
	assert_false(_service.add_action(rule, load(UNRELATED_PATH)))
	assert_false(_service.remove_action(rule, 3))


func test_duplicate_rule_deep_copies_generates_unique_id_saves_and_never_deletes() -> void:
	if _service == null:
		return
	var nested := RENotCondition.new()
	var compare := RECompareCondition.new()
	compare.key = &"source_key"
	nested.condition = compare
	var root := REAllCondition.new()
	root.conditions = [nested]
	var action := REEmitEventAction.new()
	action.event = &"source_event"
	action.payload = {&"nested": {&"value": 1}}
	var source := _rule(&"boss")
	source.event = &"trigger"
	source.priority = 9
	source.enabled = false
	source.tags = PackedStringArray(["elite", "night"])
	source.condition = root
	source.actions = [action]
	source.set_meta(&"author", "test")
	var book := _book([source])
	var duplicate: RERule = _service.duplicate_rule(
		book,
		source,
		DUPLICATE_PATH,
		PackedStringArray(["boss_copy", "boss_copy_2", "other"]),
	)
	assert_not_null(duplicate)
	if duplicate == null:
		return
	assert_eq(duplicate.id, &"boss_copy_3")
	assert_eq(duplicate.event, source.event)
	assert_eq(duplicate.priority, source.priority)
	assert_eq(duplicate.enabled, source.enabled)
	assert_eq(duplicate.tags, source.tags)
	assert_eq(duplicate.get_meta(&"author"), "test")
	assert_ne(duplicate.condition, source.condition)
	assert_ne((duplicate.condition as REAllCondition).conditions[0], nested)
	assert_ne(((duplicate.condition as REAllCondition).conditions[0] as RENotCondition).condition, compare)
	assert_ne(duplicate.actions[0], action)
	((duplicate.condition as REAllCondition).conditions[0] as RENotCondition).condition.set(&"key", &"duplicate_key")
	(duplicate.actions[0] as REEmitEventAction).payload[&"nested"][&"value"] = 2
	assert_eq(compare.key, &"source_key")
	assert_eq(action.payload[&"nested"][&"value"], 1)
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(DUPLICATE_PATH)))
	assert_eq(book.rules, [source, duplicate])
	assert_eq(_persisted, [duplicate, book])
	_undo_redo.undo()
	assert_eq(book.rules, [source])
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(DUPLICATE_PATH)), "undo only unlinks")
	assert_eq(_persisted.slice(2), [duplicate, book])
	_undo_redo.redo()
	assert_eq(book.rules, [source, duplicate], "redo reuses the saved resource")
	assert_eq(_persisted.slice(4), [duplicate, book])
	assert_eq(duplicate.resource_path, DUPLICATE_PATH)


func test_duplicate_rule_rejects_invalid_requests_without_linking_or_history() -> void:
	if _service == null:
		return
	var source := _rule(&"source")
	var book := _book([source])
	assert_null(_service.duplicate_rule(book, source, "user://duplicate.res", PackedStringArray()))
	assert_null(_service.duplicate_rule(book, _rule(&"unlinked"), DUPLICATE_PATH, PackedStringArray()))
	assert_false(_undo_redo.has_undo())
	assert_eq(book.rules, [source])


func test_create_rule_saves_before_link_and_undo_only_unlinks_the_file() -> void:
	if _service == null:
		return
	var book := _book()
	var created: RERule = _service.create_rule(book, CREATED_PATH, &"new_rule")
	assert_not_null(created)
	if created == null:
		return
	assert_eq(created.id, &"new_rule")
	assert_eq(created.resource_path, CREATED_PATH)
	assert_eq(book.rules, [created])
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(CREATED_PATH)))
	assert_eq(_persisted, [created, book])
	_undo_redo.undo()
	assert_true(book.rules.is_empty())
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(CREATED_PATH)))
	_undo_redo.redo()
	assert_eq(book.rules, [created])
	assert_null(_service.create_rule(book, "user://bad.res", &"bad"))


func test_create_rule_creates_its_missing_parent_directory_before_saving() -> void:
	if _service == null:
		return
	var absolute_directory := ProjectSettings.globalize_path(MISSING_DIRECTORY)
	assert_false(DirAccess.dir_exists_absolute(absolute_directory))
	var book := _book()
	var created: RERule = _service.create_rule(
		book,
		MISSING_DIRECTORY_RULE_PATH,
		&"created_in_new_directory",
	)
	assert_not_null(created)
	assert_true(DirAccess.dir_exists_absolute(absolute_directory))
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(MISSING_DIRECTORY_RULE_PATH)))
	assert_eq(book.rules, [created])


func test_saved_rule_path_drives_persistence_after_do_undo_redo() -> void:
	var script: Script = load(SERVICE_PATH)
	var manager := UndoRedo.new()
	var service: Variant = script.new(manager, _save_external)
	var created: RERule = service.create_rule(_book(), CREATED_PATH, &"before")
	assert_not_null(created)
	if created == null:
		return
	assert_eq(created.resource_path, CREATED_PATH)
	assert_true(service.set_rule_id(created, &"after"))
	var loaded_after := ResourceLoader.load(CREATED_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as RERule
	assert_eq(loaded_after.id, &"after")
	manager.undo()
	var loaded_undo := ResourceLoader.load(CREATED_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as RERule
	assert_eq(loaded_undo.id, &"before")
	manager.redo()
	var loaded_redo := ResourceLoader.load(CREATED_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as RERule
	assert_eq(loaded_redo.id, &"after")
	manager.clear_history()


func test_duplicate_deep_copies_externally_pathed_condition_and_action_resources() -> void:
	if _service == null:
		return
	var external_condition := RECompareCondition.new()
	external_condition.key = &"source"
	assert_eq(ResourceSaver.save(external_condition, EXTERNAL_CONDITION_PATH, ResourceSaver.FLAG_CHANGE_PATH), OK)
	var external_action := REEmitEventAction.new()
	external_action.event = &"source"
	assert_eq(ResourceSaver.save(external_action, EXTERNAL_ACTION_PATH, ResourceSaver.FLAG_CHANGE_PATH), OK)
	var loaded_condition_asset := ResourceLoader.load(
		EXTERNAL_CONDITION_PATH,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as RECompareCondition
	var loaded_action_asset := ResourceLoader.load(
		EXTERNAL_ACTION_PATH,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as REEmitEventAction
	var root := REAllCondition.new()
	root.conditions = [loaded_condition_asset]
	var source := _rule(&"external")
	source.condition = root
	source.actions = [loaded_action_asset]
	assert_eq(ResourceSaver.save(source, EXTERNAL_SOURCE_PATH), OK)
	var loaded_source := ResourceLoader.load(EXTERNAL_SOURCE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as RERule
	assert_not_null(loaded_source)
	if loaded_source == null:
		return
	var duplicate: RERule = _service.duplicate_rule(
		_book([loaded_source]),
		loaded_source,
		DUPLICATE_PATH,
		PackedStringArray(),
	)
	assert_not_null(duplicate)
	if duplicate == null:
		return
	var copied_condition: RECompareCondition = (duplicate.condition as REAllCondition).conditions[0]
	var copied_action: REEmitEventAction = duplicate.actions[0]
	var loaded_external_condition: RECompareCondition = (loaded_source.condition as REAllCondition).conditions[0]
	var loaded_external_action: REEmitEventAction = loaded_source.actions[0]
	assert_eq(loaded_external_condition.resource_path, EXTERNAL_CONDITION_PATH)
	assert_eq(loaded_external_action.resource_path, EXTERNAL_ACTION_PATH)
	assert_ne(copied_condition, loaded_external_condition)
	assert_ne(copied_action, loaded_external_action)
	assert_true(copied_condition.resource_path.is_empty())
	assert_true(copied_action.resource_path.is_empty())
	copied_condition.key = &"copy"
	copied_action.event = &"copy"
	assert_eq(loaded_external_condition.key, &"source")
	assert_eq(loaded_external_action.event, &"source")
