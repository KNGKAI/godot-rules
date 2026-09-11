extends GutTest

const DISCOVERY_PATH := "res://addons/rule_engine/editor/main_screen/rule_book_discovery.gd"


class FakeDirectory extends RefCounted:
	var files: Array[Dictionary]
	var subdirectories: Array

	func _init(p_files: Array[Dictionary] = [], p_subdirectories: Array = []) -> void:
		files = p_files
		subdirectories = p_subdirectories

	func get_file_count() -> int:
		return files.size()

	func get_file_path(index: int) -> String:
		return files[index].path

	func get_file_type(index: int) -> String:
		return files[index].type

	func get_subdir_count() -> int:
		return subdirectories.size()

	func get_subdir(index: int) -> Variant:
		return subdirectories[index]


class FakeFileSystem extends RefCounted:
	signal filesystem_changed

	var root: Variant

	func _init(p_root: Variant) -> void:
		root = p_root

	func get_filesystem() -> Variant:
		return root


func _book(rule_id: StringName) -> RERuleBook:
	var rule := RERule.new()
	rule.id = rule_id
	var book := RERuleBook.new()
	book.rules = [rule]
	return book


func _load_fixture(path: String, resources: Dictionary) -> Resource:
	return resources.get(path) as Resource


func test_discovery_recurses_groups_and_sorts_only_indexed_rule_books() -> void:
	var script: Script = load(DISCOVERY_PATH)
	assert_not_null(script)
	if script == null:
		return
	var resources := {
		"res://zeta/books/z_book.res": _book(&"z"),
		"res://alpha/a_book.tres": _book(&"a"),
		"res://alpha/nested/b_book.res": _book(&"b"),
		"res://alpha/not_a_book.tres": RENameCatalog.new(),
	}
	var filesystem := FakeFileSystem.new(FakeDirectory.new([
		{&"path": "res://readme.txt", &"type": "TextFile"},
	], [
		FakeDirectory.new([
			{&"path": "res://zeta/books/z_book.res", &"type": "RERuleBook"},
		]),
		FakeDirectory.new([
			{&"path": "res://alpha/not_a_book.tres", &"type": "RERuleBook"},
			{&"path": "res://alpha/a_book.tres", &"type": "Resource/RERuleBook"},
		], [
			FakeDirectory.new([
				{&"path": "res://alpha/nested/b_book.res", &"type": "RERuleBook"},
				{&"path": "res://alpha/nested/ignored.tscn", &"type": "RERuleBook"},
			]),
		]),
	]))
	var discovery: Variant = script.new(filesystem, _load_fixture.bind(resources))
	discovery.refresh()
	var groups: Array = discovery.get_groups()
	assert_eq(groups.map(func(group: Dictionary) -> String: return group.directory), [
		"res://alpha",
		"res://alpha/nested",
		"res://zeta/books",
	])
	assert_eq(groups[0].books.map(func(entry: Dictionary) -> String: return entry.path), [
		"res://alpha/a_book.tres",
	])
	assert_eq(groups[1].books[0].book, resources["res://alpha/nested/b_book.res"])


func test_start_refreshes_on_filesystem_changes_without_duplicate_connections() -> void:
	var script: Script = load(DISCOVERY_PATH)
	assert_not_null(script)
	if script == null:
		return
	var first_path := "res://rules/first.tres"
	var second_path := "res://rules/second.tres"
	var resources := {first_path: _book(&"first"), second_path: _book(&"second")}
	var filesystem := FakeFileSystem.new(FakeDirectory.new([
		{&"path": first_path, &"type": "RERuleBook"},
	]))
	var discovery: Variant = script.new(filesystem, _load_fixture.bind(resources))
	watch_signals(discovery)
	discovery.start()
	discovery.start()
	assert_eq(filesystem.filesystem_changed.get_connections().size(), 1)
	assert_eq(discovery.get_books(), [resources[first_path]])
	filesystem.root = FakeDirectory.new([
		{&"path": second_path, &"type": "RERuleBook"},
	])
	filesystem.filesystem_changed.emit()
	assert_eq(discovery.get_books(), [resources[second_path]])
	assert_signal_emit_count(discovery, "changed", 3)
	discovery.stop()
	assert_eq(filesystem.filesystem_changed.get_connections().size(), 0)
