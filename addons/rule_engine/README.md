# Godot Rule Engine addon

A deterministic Event-Condition-Action rules addon for Godot 4.7.1+.

## Installation

Copy this entire `rule_engine` directory to `res://addons/rule_engine/`, then
enable **Rule Engine** in **Project > Project Settings > Plugins**. Enabling the
plugin adds an optional `Rules` autoload; disabling it removes that autoload
only when it still points to this addon's runtime facade.

You may instead own the runtime directly:

```gdscript
var rule_engine := RERuleEngine.new()

func _ready() -> void:
	rule_engine.load_book(load("res://rules/game_rules.tres"))
	rule_engine.emit_event(&"game_started")
```

Retain the `RERuleEngine` in a member variable. Its blackboard and enabled
overrides are per-engine, in-memory state; your game is responsible for any
save-game persistence.

## Authoring

Create external `RERule` resources and reference them from an `RERuleBook`.
An empty rule event makes it queryable through `check()`; a non-empty event
makes it reactive through `emit_event()`. Reactive rules require at least one
action.

Built-in conditions are `REAllCondition`, `REAnyCondition`, `RENotCondition`,
`RECompareCondition`, and `REExistsCondition`. Built-in actions emit another
rule event or set a blackboard value. Use NOT + blackboard EXISTS followed by a
set action for one-time behavior.

Validate authored books in automation:

```powershell
godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd -- --book=res://rules/game_rules.tres
```

Custom GDScript conditions and actions require `@tool`, a global `class_name`,
and constructors callable with default arguments so the Inspector can create
them. After adding or changing a tool script, reopen the project if Godot's
global class cache has not refreshed it.

See the repository documentation for the full runtime contract and extension
examples. Licensed under the [MIT License](LICENSE).
