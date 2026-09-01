# Godot Rule Engine

Godot Rule Engine is a Godot 4.7 addon for deterministic, data-authored
Event-Condition-Action gameplay rules:

```text
event + payload + facts + blackboard -> conditions -> actions
```

It suits progression, unlock, economy, and quest decisions that should remain
independent of scene paths. Rules are ordinary Godot Resources, reactive
events use a non-recursive FIFO queue, and candidates run in priority-descending
then ID-ascending order.

## Install

1. Copy `addons/rule_engine/` into the same path in your Godot 4.7.1+ project.
2. Enable **Rule Engine** under **Project > Project Settings > Plugins**.
3. Use the optional `Rules` autoload installed by the plugin, or retain your own
   `RERuleEngine` instance.

```gdscript
var engine := RERuleEngine.new()

func _ready() -> void:
	engine.set_fact_provider(REDictionaryFactProvider.new({&"reputation": 12}))
	engine.load_book(load("res://rules/progression.tres"))
	engine.emit_event(&"mission_completed", {&"mission_id": &"first_steps"})
```

An engine is `RefCounted`, so keep it in a member variable for as long as its
books, signals, overrides, and blackboard are needed.

## Example

The included example translates a Godot `mission_completed` signal into a rule
event, checks payload and game facts, applies a one-time blackboard guard, and
emits `business_unlock_requested` back to game code.

```powershell
godot --headless --path . --quit-after 3
```

Expected output includes:

```text
BASIC_EXAMPLE: requested=[&"boutique"] fired=[&"unlock_boutique"]
```

See [the example walkthrough](examples/basic/README.md),
[runtime API](docs/runtime-api.md), and [custom types](docs/custom-types.md).

## Validate rules in CI

Pass one or more rule books after Godot's `--` argument separator. Errors exit
with code 1; warnings-only input exits with code 0.

```powershell
godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd -- --book=res://rules/progression.tres
```

Optional `--event-catalog=res://...` and `--fact-catalog=res://...` arguments
report unknown names as warnings.

## V1 boundaries

V1 intentionally has no graph editor, runtime debugger, automatic persistence,
arbitrary Node-path/property actions, multiplayer replication, or C# extension
discovery. Games own save/load integration for blackboard state.

## Development

GUT 9.7.1 is vendored for the repository test suite:

```powershell
godot --headless --path . --script addons/gut/gut_cmdln.gd -- '-gdir=res://tests' -ginclude_subdirs -gexit
godot --headless --path . --script tools/check_runtime.gd
godot --headless --path . --export-pack "Rule Engine Test Pack" .tools/rule-engine-runtime-boundary.pck
# Run this from outside the source tree, using an absolute path to the pack:
godot --headless --main-pack C:\path\to\godot-rules\.tools\rule-engine-runtime-boundary.pck --script tools/export_content_smoke.gd
```

The frozen scope and semantics remain available under [`plan/`](plan/).

## License

[MIT](LICENSE)
