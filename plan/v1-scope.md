# Godot Rule Engine V1 Scope

## Goal

Ship a reusable Godot 4.7 addon for deterministic, data-authored gameplay
rules using the model `event + facts + conditions -> actions`. A game can
install `addons/rule_engine/`, create and validate rules with native Godot
workflows, and run them without modifying Godot or coupling rules to scene
paths.

## Supported platform

- Godot 4.7.1+ within the Godot 4.7 release line.
- GDScript; C# custom condition/action discovery is not supported in V1.
- Text `.tres` authoring; runtime loading always uses `ResourceLoader` and
  therefore remains correct when exports convert resources to `.res`.
- GUT 9.7.1 on its `godot_4_7` branch for automated GDScript tests.
- Git stores `.tres`, `.uid`, and required `.import` files.

## V1 capabilities

### Authored resources

- `RERuleBook` references external `RERule` files.
- `RERule` contains an ID, authored enabled default, priority, tags, optional
  event name, one condition tree, and an ordered action list.
- Built-in conditions: all, any, not, compare, and exists.
- Compare/exists can read an event payload, game fact, or rule blackboard.
- Built-in actions: emit event and set blackboard value.
- Project-defined GDScript conditions and actions are supported.

### Runtime

- A `RefCounted` `RERuleEngine` can be instantiated more than once.
- An optional `Node` autoload named `Rules` wraps one engine instance.
- Loaded books are indexed by event and explicit rule ID.
- Reactive event dispatch and manual/queryable rule checks are separate.
- Candidate ordering is deterministic: priority descending, then ID ascending.
- Each event uses a match phase followed by an action phase.
- Nested events append to one non-recursive FIFO queue.
- `max_events_per_dispatch` stops cycles and emits a diagnostic signal.
- Authored resources are never mutated by runtime state.
- Runtime enabled overrides and blackboard values are per engine instance.

### Authoring and validation

- Every V1 resource is usable through the native Inspector without the custom
  Rules workspace.
- A custom `EditorProperty` handles the comparison `Variant` value reliably.
- The plugin discovers transitive GDScript subclasses of `RECondition` and
  `REAction`, and warns when a candidate lacks `@tool`.
- Editor and headless validation share one validator.
- Validation covers malformed trees, duplicate IDs/references, invalid
  comparisons, Resource cycles, and optional event/fact catalog mismatches.
- Editor mutations supplied by the plugin use `EditorUndoRedoManager`.
- Runtime/resource scripts neither reference nor preload editor classes.

### Distribution

- `plugin.cfg` contains `name`, `description`, `author`, `version`, and a script
  path relative to the addon directory.
- `README.md` and the full `LICENSE` exist both at repository root and inside
  `addons/rule_engine/`.
- An `EditorExportPlugin` excludes `addons/rule_engine/editor/` from exported
  games without removing it from consumer projects.
- Asset Store metadata includes the required AI-use disclosure.

## Explicitly deferred

The following are not V1 acceptance requirements:

- Dedicated Rules main-screen workspace or private replacement Inspector.
- Dry-run UI, traced condition trees, runtime debugger, breakpoints, profiling.
- Graph editor, behavior trees, state machines, GOAP, RETE, or forward chaining.
- Delayed actions, cooldowns, exclusive groups, halt/stop propagation.
- Automatic once/refraction fields; authors use blackboard guards in V1.
- Save-game integration or blackboard persistence.
- Multiplayer replication, authoritative networking, or deterministic rollback.
- Arbitrary Node paths, arbitrary property mutation, or game-domain actions.
- Per-entity/source rule instances; games encode identity in facts or payloads.
- C# extension discovery.

## Architecture

Dependency direction is strict:

```text
editor -> runtime -> resources
editor -----------> resources
```

`resources/` and `runtime/` never reference `Editor*` identifiers, even behind
`Engine.is_editor_hint()`, because export templates must parse these scripts.
`plugin.gd` is the only `EditorPlugin`; editor helpers avoid global
`class_name` declarations.

The engine translates an event into candidates through an event index. It
evaluates every candidate against one match view, records passers, and only
then executes their actions. Action event emission calls back into the same
engine queue. Game systems consume emitted events or provide project-specific
actions; the addon never reaches into scene-tree paths.

## Public resource interfaces

```gdscript
@tool
class_name RERuleBook
extends Resource
@export var rules: Array[RERule] = []

@tool
class_name RERule
extends Resource
@export var id: StringName
@export var enabled: bool = true
@export var priority: int = 0
@export var tags: PackedStringArray = []
@export var event: StringName
@export var condition: RECondition
@export var actions: Array[REAction] = []

@tool
class_name RECondition
extends Resource
func evaluate(context: REMatchContext) -> REConditionResult

@tool
class_name REAction
extends Resource
func execute(context: REActionContext) -> Error
```

`REConditionResult` contains `matched: bool` and `valid: bool`. Built-ins return
an invalid result for a missing comparison or incompatible operands, allowing
`RENotCondition` to preserve invalidity instead of turning bad data into a
match. `REAction.execute()` returns `OK` or a Godot `Error` code so dispatch
failure behavior is observable and testable.

An empty `event` makes a rule queryable. Queryable rules are absent from the
event index and run only through `check()`.

Compare and exists use an explicit source:

```gdscript
enum Source { FACT, PAYLOAD, BLACKBOARD }
enum Operator { EQUAL, NOT_EQUAL, GREATER, GREATER_EQUAL, LESS, LESS_EQUAL }
```

`contains` is deferred because its cross-Variant behavior is not coherent
enough for a stable V1 contract.

## Public runtime interface

```gdscript
class_name RERuleEngine
extends RefCounted

signal event_received(event: RERuleEvent)
signal rule_evaluated(rule: RERule, passed: bool)
signal rule_fired(rule: RERule)
signal action_executed(rule: RERule, action: REAction)
signal dispatch_failed(reason: StringName, processed_events: int)

func load_book(book: RERuleBook) -> Error
func unload_book(book: RERuleBook) -> void
func emit_event(name: StringName, payload: Dictionary = {}) -> void
func check(rule_id: StringName, payload: Dictionary = {}) -> bool
func get_rule(rule_id: StringName) -> RERule
func set_fact_provider(provider: REFactProvider) -> void
func set_rule_enabled(rule_id: StringName, enabled: bool) -> Error
func clear_rule_enabled_override(rule_id: StringName) -> void
func get_blackboard() -> REBlackboard
```

`check()` is match-only: it never runs actions, queues events, or emits
`rule_fired`. `load_book()` is atomic and returns `ERR_ALREADY_EXISTS` for a
duplicate rule ID from another loaded book. Loading the same `RERuleBook`
instance twice is idempotent and returns `OK`.

## Repository shape

```text
addons/rule_engine/
  README.md
  LICENSE
  plugin.cfg
  plugin.gd
  runtime/
    rule_engine.gd
    rule_event.gd
    match_context.gd
    action_context.gd
    fact_provider.gd
    dictionary_fact_provider.gd
    blackboard.gd
  resources/
    rule.gd
    rule_book.gd
    name_catalog.gd
    conditions/{condition,condition_result,all,any,not,compare,exists}.gd
    actions/{action,emit_event,set_blackboard}.gd
  editor/
    export_plugin.gd
    inspector/rule_inspector_plugin.gd
    inspector/variant_editor_property.gd
    registry/type_registry.gd
    validation/{validator,validation_issue}.gd
  tools/validate_rules.gd
tests/
  runtime/
  serialization/
  editor/
  fixtures/
examples/basic/
```

## V1 acceptance criteria

V1 is complete only when all of the following are demonstrated:

1. Two engines can load the same book without sharing overrides or blackboard.
2. A payload-and-fact rule emits a second event exactly once and in stable order.
3. Same-event conditions see the pre-action match view.
4. A nested event queues rather than reentering dispatch.
5. An `A -> B -> A` cycle stops at the configured event limit.
6. A complete book can be authored using the native Inspector.
7. Custom transitive GDScript subclasses are discovered; non-`@tool` types warn.
8. Saving and reloading external rules preserves nested conditions and actions.
9. Headless validation exits 1 for errors and 0 for warnings-only input.
10. A headless export/parsing check proves runtime scripts contain no editor dependency.
11. The basic example runs on Godot 4.7.1 and the packaged addon contains its
    own README and LICENSE.
