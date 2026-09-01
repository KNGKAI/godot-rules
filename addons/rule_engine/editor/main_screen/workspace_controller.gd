@tool
extends RefCounted

signal inspect_requested(resource: Resource)
signal selection_changed
signal state_changed
signal issues_changed(issues: Array)
signal issue_activated(rule: RERule, property_path: String)

var _discovery: Variant
var _commands: Variant
var _validator: Variant
var _selected_book: RERuleBook
var _selected_rule: RERule
var _issues: Array = []


func _init(discovery: Variant, commands: Variant, validator: Variant) -> void:
	_discovery = discovery
	_commands = commands
	_validator = validator
	if _commands != null:
		var command_changed: Signal = _commands.changed
		if not command_changed.is_connected(_on_commands_changed):
			command_changed.connect(_on_commands_changed)


func stop() -> void:
	if _commands == null:
		return
	var command_changed: Signal = _commands.changed
	if command_changed.is_connected(_on_commands_changed):
		command_changed.disconnect(_on_commands_changed)


func get_selected_book() -> RERuleBook:
	return _selected_book


func get_selected_rule() -> RERule:
	return _selected_rule


func get_issues() -> Array:
	return _issues.duplicate()


func select_book(book: RERuleBook) -> bool:
	if book == null or not _books().has(book):
		return false
	_selected_book = book
	_selected_rule = null
	selection_changed.emit()
	inspect_requested.emit(book)
	return true


func select_rule(rule: RERule) -> bool:
	var book := _find_book(rule)
	if book == null:
		return false
	_selected_book = book
	_selected_rule = rule
	selection_changed.emit()
	inspect_requested.emit(rule)
	return true


func select_condition(condition: RECondition) -> bool:
	if _selected_rule == null or condition == null:
		return false
	if not _condition_contains(_selected_rule.condition, condition, {}):
		return false
	inspect_requested.emit(condition)
	return true


func select_action(index: int) -> bool:
	if _selected_rule == null or index < 0 or index >= _selected_rule.actions.size():
		return false
	var action: REAction = _selected_rule.actions[index]
	if action == null:
		return false
	inspect_requested.emit(action)
	return true


func clear_selection() -> void:
	_selected_book = null
	_selected_rule = null
	selection_changed.emit()


func get_default_rules_directory() -> String:
	if _selected_book == null or _selected_book.resource_path.is_empty():
		return "res://rules"
	return _selected_book.resource_path.get_base_dir().path_join("rules")


func create_rule(target_path: String, rule_id: StringName) -> RERule:
	if _selected_book == null or _commands == null:
		return null
	var created: RERule = _commands.create_rule(_selected_book, target_path, rule_id)
	if created != null:
		select_rule(created)
	return created


func duplicate_selected_rule(target_path: String) -> RERule:
	if _selected_book == null or _selected_rule == null or _commands == null:
		return null
	var duplicate: RERule = _commands.duplicate_rule(
		_selected_book,
		_selected_rule,
		target_path,
		_discovered_ids(),
	)
	if duplicate != null:
		select_rule(duplicate)
	return duplicate


func unlink_selected_rule() -> bool:
	if _selected_book == null or _selected_rule == null or _commands == null:
		return false
	if not _commands.unlink_rule(_selected_book, _selected_rule):
		return false
	_selected_rule = null
	selection_changed.emit()
	return true


func set_rule_enabled(value: bool) -> bool:
	return _commands != null and _commands.set_rule_enabled(_selected_rule, value)


func set_rule_id(value: StringName) -> bool:
	return _commands != null and _commands.set_rule_id(_selected_rule, value)


func set_rule_event(value: StringName) -> bool:
	return _commands != null and _commands.set_rule_event(_selected_rule, value)


func set_rule_priority(value: int) -> bool:
	return _commands != null and _commands.set_rule_priority(_selected_rule, value)


func set_rule_tags(value: PackedStringArray) -> bool:
	return _commands != null and _commands.set_rule_tags(_selected_rule, value)


func set_condition(property_path: String, script: Script) -> bool:
	return _commands != null and _commands.set_condition(_selected_rule, property_path, script)


func replace_condition(property_path: String, script: Script) -> bool:
	return _commands != null and _commands.replace_condition(_selected_rule, property_path, script)


func remove_condition(property_path: String) -> bool:
	return _commands != null and _commands.remove_condition(_selected_rule, property_path)


func wrap_condition(property_path: String, script: Script) -> bool:
	return _commands != null and _commands.wrap_condition(_selected_rule, property_path, script)


func convert_condition(property_path: String) -> bool:
	return _commands != null and _commands.convert_all_any(_selected_rule, property_path)


func add_action(script: Script, index: int = -1) -> bool:
	return _commands != null and _commands.add_action(_selected_rule, script, index)


func remove_action(index: int) -> bool:
	return _commands != null and _commands.remove_action(_selected_rule, index)


func move_action(from_index: int, to_index: int) -> bool:
	return _commands != null and _commands.move_action(_selected_rule, from_index, to_index)


func validate() -> Array:
	_issues = _validator.validate_books(_books()) if _validator != null else []
	issues_changed.emit(_issues.duplicate())
	return _issues.duplicate()


func activate_issue(index: int) -> bool:
	if index < 0 or index >= _issues.size():
		return false
	var issue: Variant = _issues[index]
	if issue.rule == null or not select_rule(issue.rule):
		return false
	issue_activated.emit(issue.rule, issue.property_path)
	return true


func _books() -> Array[RERuleBook]:
	return _discovery.get_books() if _discovery != null else []


func _find_book(rule: RERule) -> RERuleBook:
	if rule == null:
		return null
	for book: RERuleBook in _books():
		if book != null and book.rules.has(rule):
			return book
	return null


func _discovered_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for book: RERuleBook in _books():
		if book == null:
			continue
		for rule: RERule in book.rules:
			if rule != null:
				ids.append(rule.id)
	return ids


func _on_commands_changed() -> void:
	state_changed.emit()


func _condition_contains(root: RECondition, target: RECondition, visited: Dictionary) -> bool:
	if root == null:
		return false
	if root == target:
		return true
	var key := root.get_instance_id()
	if visited.has(key):
		return false
	visited[key] = true
	if root is RENotCondition:
		return _condition_contains(root.condition, target, visited)
	if root is REAllCondition or root is REAnyCondition:
		for child: RECondition in root.conditions:
			if _condition_contains(child, target, visited):
				return true
	return false
