extends GutTest

const REGISTRY_PATH := "res://addons/rule_engine/editor/registry/type_registry.gd"
const DIRECT_PATH := "res://tests/fixtures/custom_types/direct_condition.gd"
const GRANDCHILD_PATH := "res://tests/fixtures/custom_types/grandchild_condition.gd"
const NON_TOOL_PATH := "res://tests/fixtures/custom_types/non_tool_condition.gd"
const UNRELATED_PATH := "res://tests/fixtures/custom_types/unrelated_resource.gd"


func test_discovery_walks_transitive_bases_and_reports_non_tool_scripts() -> void:
	var registry_script: Script = load(REGISTRY_PATH)
	assert_not_null(registry_script)
	if registry_script == null:
		return
	var entries: Array = [
		{&"class": &"RETestDirectCondition", &"base": &"RECondition", &"language": &"GDScript", &"path": DIRECT_PATH},
		{&"class": &"RETestGrandchildCondition", &"base": &"RETestDirectCondition", &"language": &"GDScript", &"path": GRANDCHILD_PATH},
		{&"class": &"RETestNonToolCondition", &"base": &"RECondition", &"language": &"GDScript", &"path": NON_TOOL_PATH},
		{&"class": &"RETestUnrelated", &"base": &"Resource", &"language": &"GDScript", &"path": UNRELATED_PATH},
		{&"class": &"RETestCSharp", &"base": &"RECondition", &"language": &"C#", &"path": "res://fake.cs"},
		{&"class": &"RETestMissingBase", &"base": &"UnknownBase", &"language": &"GDScript", &"path": DIRECT_PATH},
	]
	var registry: Variant = registry_script.new(entries)
	var discovered: Array = registry.discover(&"RECondition")
	assert_eq(discovered.size(), 3)
	assert_eq(
		discovered.map(func(item: Dictionary) -> StringName: return item.name),
		[&"RETestDirectCondition", &"RETestGrandchildCondition", &"RETestNonToolCondition"],
	)
	assert_true(discovered[0].tool)
	assert_true(discovered[1].tool)
	assert_false(discovered[2].tool)
	assert_string_contains(discovered[2].warning, "@tool")

