extends SceneTree


func _init() -> void:
	var required_files := [
		"res://addons/rule_engine/plugin.cfg",
		"res://addons/rule_engine/plugin.gd",
		"res://addons/rule_engine/README.md",
		"res://addons/rule_engine/LICENSE",
	]
	for path: String in required_files:
		if not FileAccess.file_exists(path):
			printerr("CONSUMER_SMOKE: missing %s" % path)
			quit(1)
			return
	var condition := REExistsCondition.new()
	condition.source = REExistsCondition.Source.PAYLOAD
	condition.key = &"ready"
	var rule := RERule.new()
	rule.id = &"consumer_query"
	rule.condition = condition
	var book := RERuleBook.new()
	book.rules.append(rule)
	var engine := RERuleEngine.new()
	if engine.load_book(book) != OK or not engine.check(&"consumer_query", {&"ready": true}):
		printerr("CONSUMER_SMOKE: runtime API did not evaluate the clean-project query.")
		quit(1)
		return
	print("CONSUMER_SMOKE: PASS")
	quit()
