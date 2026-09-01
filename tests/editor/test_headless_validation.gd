extends GutTest

const VALIDATOR_SCRIPT := "res://addons/rule_engine/tools/validate_rules.gd"


func _run_validator(book_path: String) -> Dictionary:
	var output: Array = []
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		VALIDATOR_SCRIPT.trim_prefix("res://"),
		"--",
		"--book=%s" % book_path,
	])
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true, false)
	return {&"exit_code": exit_code, &"output": "\n".join(output)}


func test_valid_book_exits_successfully() -> void:
	var result := _run_validator("res://tests/fixtures/validation_cli/valid_book.tres")
	assert_eq(result.exit_code, 0, result.output)


func test_warning_only_book_exits_successfully() -> void:
	var result := _run_validator("res://tests/fixtures/validation_cli/warning_book.tres")
	assert_eq(result.exit_code, 0, result.output)
	assert_string_contains(result.output, "WARNING [empty_composite]")


func test_invalid_book_exits_with_failure() -> void:
	var result := _run_validator("res://tests/fixtures/validation_cli/invalid_book.tres")
	assert_eq(result.exit_code, 1, result.output)
	assert_string_contains(result.output, "ERROR [missing_condition]")
