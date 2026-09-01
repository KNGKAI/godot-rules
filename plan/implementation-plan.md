# Godot Rule Engine V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an installable Godot 4.7 Event–Condition–Action addon matching the frozen V1 contract.

**Architecture:** Authored `Resource` definitions feed an event-indexed, `RefCounted` runtime with per-instance state. Editor-only inspection, discovery, validation, and export support depend inward on the runtime and resources; runtime files never reference editor APIs.

**Tech Stack:** Godot 4.7.1+, typed GDScript, `.tres` Resources, EditorPlugin APIs, GUT 9.7.1.

**Spec:** `plan/v1-scope.md` and `plan/runtime-semantics.md`

## Global constraints

- Prefix every public global class with `RE`.
- Conditions are side-effect-free and actions never mutate authored Resources.
- Use a FIFO queue and match-all-before-actions dispatch.
- Normalize public names and keys to `StringName`.
- Runtime and resource scripts contain no `Editor*` identifier or editor preload.
- Use `EditorUndoRedoManager`, not raw `UndoRedo`, for plugin mutations.
- Do not add anything listed under “Explicitly deferred” in the V1 scope.

---

### Task 1: Project, test harness, and immutable resource model

**Files:**

- Create: `project.godot`
- Create: `addons/rule_engine/plugin.cfg`
- Create: `addons/rule_engine/resources/rule.gd`
- Create: `addons/rule_engine/resources/rule_book.gd`
- Create: `addons/rule_engine/resources/name_catalog.gd`
- Create: `addons/rule_engine/resources/conditions/condition.gd`
- Create: `addons/rule_engine/resources/conditions/condition_result.gd`
- Create: `addons/rule_engine/resources/actions/action.gd`
- Create: `tests/runtime/test_resources.gd`
- Create: `tests/fixtures/valid_book.tres`

**Interfaces:**

- Produces `RERule`, `RERuleBook`, `RENameCatalog`, `REConditionResult`,
  `RECondition`, and `REAction` with the exact properties and methods in
  `plan/v1-scope.md`.
- All resource scripts start with `@tool`; every `_init()` parameter has a default.

- [ ] **Step 1: Add Godot project configuration and pin GUT 9.7.1**

Configure `res://tests` as the GUT test directory and document the local addon
installation in the repository README. Do not commit generated `.godot/` data.

- [ ] **Step 2: Write failing resource tests**

Cover default construction, external rule references, explicit IDs, queryable
versus reactive classification, and absence of runtime fields such as
`has_fired` on `RERule`.

- [ ] **Step 3: Run the focused tests and verify failure**

Run:

```powershell
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/runtime -gtest=test_resources.gd -gexit
```

Expected: failure because the resource classes do not exist.

- [ ] **Step 4: Implement the minimal resource classes**

Use typed exported properties from the V1 scope. `RENameCatalog` contains
`@export var names: Array[StringName] = []` and is used only when supplied to
validation.

- [ ] **Step 5: Run focused tests and parse checks**

Expected: resource tests pass and this succeeds:

```powershell
godot --headless --path . --check-only -s addons/rule_engine/resources/rule.gd
```

- [ ] **Step 6: Commit**

```powershell
git add project.godot addons/rule_engine tests/runtime/test_resources.gd tests/fixtures/valid_book.tres README.md
git commit -m "feat: add rule resource model"
```

### Task 2: Match values, providers, contexts, and built-in conditions

**Files:**

- Create: `addons/rule_engine/runtime/fact_provider.gd`
- Create: `addons/rule_engine/runtime/dictionary_fact_provider.gd`
- Create: `addons/rule_engine/runtime/blackboard.gd`
- Create: `addons/rule_engine/runtime/match_context.gd`
- Create: `addons/rule_engine/resources/conditions/{all,any,not,compare,exists}.gd`
- Create: `tests/runtime/test_conditions.gd`
- Create: `tests/runtime/test_match_snapshot.gd`

**Interfaces:**

- `REFactProvider.has_fact(key: StringName) -> bool`
- `REFactProvider.get_fact(key: StringName) -> Variant`
- `REBlackboard.has_value/get_value/set_value`
- `REMatchContext.lookup(source: int, key: StringName) -> Dictionary` returns
  `{&"present": bool, &"value": Variant}`; this internal shape is centralized
  in `match_context.gd` and never crosses the engine's public boundary.
- `RECondition.evaluate(context: REMatchContext) -> REConditionResult` returns
  `valid = false` for missing comparisons or incompatible operand types.

- [ ] **Step 1: Write failing lookup and condition tests**

Test all six comparison operators, int/float equality, String/StringName
equality, invalid ordered pairs, missing compare, `NOT` of missing compare,
`NOT Exists`, empty all/any behavior, nested composites, and all three sources.
Define empty `All` as true and empty `Any` as false.

- [ ] **Step 2: Write failing match-view isolation tests**

Prove payload normalization/deep-copy, read-only nested collections,
blackboard snapshotting, and provider memoization of both missing and present
values.

- [ ] **Step 3: Run tests and verify they fail for missing classes**

Run the two focused test scripts with the Task 1 GUT command.

- [ ] **Step 4: Implement providers, snapshots, and conditions**

Centralize normalization and comparison in `match_context.gd`; condition
classes must not duplicate coercion rules. The engine fires only for a result
whose `valid` and `matched` fields are both true.

- [ ] **Step 5: Run all runtime tests**

Expected: Task 1 and Task 2 tests pass with no orphan-node or script errors.

- [ ] **Step 6: Commit**

```powershell
git add addons/rule_engine/runtime addons/rule_engine/resources/conditions tests/runtime
git commit -m "feat: add deterministic condition evaluation"
```

### Task 3: Event queue, indexes, runtime state, and actions

**Files:**

- Create: `addons/rule_engine/runtime/rule_event.gd`
- Create: `addons/rule_engine/runtime/action_context.gd`
- Create: `addons/rule_engine/runtime/rule_engine.gd`
- Create: `addons/rule_engine/resources/actions/emit_event.gd`
- Create: `addons/rule_engine/resources/actions/set_blackboard.gd`
- Create: `tests/runtime/test_registration.gd`
- Create: `tests/runtime/test_dispatch.gd`
- Create: `tests/runtime/test_runaway.gd`

**Interfaces:**

- Produces the exact `RERuleEngine` methods and signals in `plan/v1-scope.md`.
- `REActionContext.emit_event(name, payload) -> void` appends through its owner
  engine; it exposes the live `REBlackboard` but no fact mutation API.
- `REAction.execute(context: REActionContext) -> Error` returns `OK` on success;
  the engine applies the action-failure behavior in the semantic spec for any
  other code.
- The event index is `Dictionary[StringName, Array]`; do not add an element
  type to the nested array because GDScript does not support nested typed
  collections.

- [ ] **Step 1: Write failing atomic-registration tests**

Cover duplicate IDs, duplicate references, repeated load of the same book,
unload, reactive/queryable indexing, and lookup after rejected loads.

- [ ] **Step 2: Write failing dispatch tests**

Cover priority/ID ordering, action array order, disabled defaults and overrides,
match-all-before-actions, nested game callback emission, FIFO chains, check as
match-only, String payload keys, and two engines sharing one Resource book.

- [ ] **Step 3: Write failing runaway and recovery tests**

Construct `A -> B -> A`, assert `processed_events == max_events_per_dispatch`
and queue clearing, then emit an unrelated event and prove the engine recovered.

- [ ] **Step 4: Run focused tests and verify failure**

Expected: missing engine/action classes cause failures.

- [ ] **Step 5: Implement registration and dispatch minimally**

Use one drain guard with guaranteed cleanup. Evaluate to a passing-rule array
before creating action contexts. Never write `RERule.enabled` at runtime.

- [ ] **Step 6: Run the full runtime suite**

Expected: all runtime tests pass, including same-event blackboard isolation.

- [ ] **Step 7: Commit**

```powershell
git add addons/rule_engine/runtime addons/rule_engine/resources/actions tests/runtime
git commit -m "feat: add queued rule engine runtime"
```

### Task 4: Serialization and native Inspector usability

**Files:**

- Create: `addons/rule_engine/editor/inspector/rule_inspector_plugin.gd`
- Create: `addons/rule_engine/editor/inspector/variant_editor_property.gd`
- Create: `tests/serialization/test_rule_round_trip.gd`
- Create: `tests/editor/test_inspector_plugin.gd`
- Create: `tests/fixtures/round_trip_book.tres`

**Interfaces:**

- `variant_editor_property.gd` edits compare values without relying on the
  fragile untyped `@export var value: Variant` default editor.
- Inspector helpers have no `class_name`; the plugin creates them with
  `preload(...).new()`.

- [ ] **Step 1: Write failing save/reload tests**

Use `ResourceSaver.save`, clear/reload through `ResourceLoader`, and assert
external rule references, nested condition subresources, ordered actions,
Variant values, and custom condition/action scripts. Assert behavior, not raw
`.tres` text or subresource IDs.

- [ ] **Step 2: Write a minimal editor-plugin lifecycle test**

Assert that the Inspector plugin can be added and removed without leaked
controls and that returning `true` from `_parse_property` replaces only the
comparison value property.

- [ ] **Step 3: Run tests and verify the custom Variant case fails**

- [ ] **Step 4: Implement the Inspector property and lifecycle**

All edits use `EditorUndoRedoManager.add_do_method(target, method_name, ...)`
and matching undo methods; do not pass lambdas or Resource references to
`add_do_reference`/`add_undo_reference`.

- [ ] **Step 5: Run serialization and editor tests**

Expected: round trips preserve behavior and plugin cleanup passes.

- [ ] **Step 6: Commit**

```powershell
git add addons/rule_engine/editor/inspector tests/serialization tests/editor tests/fixtures
git commit -m "feat: support native inspector rule authoring"
```

### Task 5: Type discovery and shared validation

**Files:**

- Create: `addons/rule_engine/editor/registry/type_registry.gd`
- Create: `addons/rule_engine/editor/validation/validation_issue.gd`
- Create: `addons/rule_engine/editor/validation/validator.gd`
- Create: `tests/editor/test_type_registry.gd`
- Create: `tests/editor/test_validator.gd`
- Create: `tests/fixtures/custom_types/`

**Interfaces:**

- `RuleTypeRegistry.discover(base_name: StringName) -> Array[Dictionary]`
  follows every immediate `base` link until it reaches `RECondition` or
  `REAction`; it accepts GDScript only and reports non-`@tool` candidates.
- `RuleValidator.validate_books(books, event_catalog = null,
  fact_catalog = null) -> Array[ValidationIssue]` returns stable ordering by
  severity, rule ID, and property path.

- [ ] **Step 1: Write failing transitive-discovery tests**

Fixtures include a direct child, grandchild, unrelated class, C#-language fake
registry entry, missing-base entry, and non-`@tool` script.

- [ ] **Step 2: Write failing validator tests**

Cover every item in `plan/v1-scope.md`: empty/duplicate IDs, duplicate external
references, missing conditions/actions, null children, empty composites,
invalid source/operator/value combinations, Resource cycles, empty reactive
events where required, and optional catalog warnings.

- [ ] **Step 3: Implement discovery and validation without UI dependencies**

Cycle checks use an active-path set keyed by Resource instance ID; never add
parent/back-pointer fields to Resources.

- [ ] **Step 4: Run editor tests**

Expected: discovery and validator suites pass deterministically.

- [ ] **Step 5: Commit**

```powershell
git add addons/rule_engine/editor/registry addons/rule_engine/editor/validation tests/editor tests/fixtures/custom_types
git commit -m "feat: discover and validate rule extensions"
```

### Task 6: Headless validation, plugin, autoload, and export boundary

**Files:**

- Create: `addons/rule_engine/tools/validate_rules.gd`
- Create: `addons/rule_engine/runtime/rules.gd`
- Create: `addons/rule_engine/editor/export_plugin.gd`
- Create: `addons/rule_engine/plugin.gd`
- Create: `tests/editor/test_headless_validation.gd`
- Create: `tests/editor/test_plugin_lifecycle.gd`
- Create: `tools/check_runtime.gd`

**Interfaces:**

- `validate_rules.gd extends SceneTree`; `_init()` loads configured books,
  prints issues, and calls `quit(1)` for errors or `quit(0)` otherwise.
- `rules.gd extends Node` and delegates the public runtime API to one retained
  `RERuleEngine`; its name `Rules` differs from all `class_name` values.
- `plugin.gd` registers/removes Inspector and export plugins in `_enter_tree()`;
  it adds/removes the optional autoload in `_enable_plugin()`/
  `_disable_plugin()`.

- [ ] **Step 1: Write failing CLI exit-code tests**

Invoke Godot as a child process against valid, warning-only, and invalid fixture
projects; assert exit codes 0, 0, and 1 respectively.

- [ ] **Step 2: Write failing lifecycle and boundary tests**

Enable/disable twice, assert no duplicate Inspector plugin or stale autoload,
and scan `runtime/` plus `resources/` for `Editor`, `/editor/`, and editor
preloads.

- [ ] **Step 3: Implement the CLI, Node wrapper, plugin, and export filter**

The export plugin calls `skip()` for `addons/rule_engine/editor/` only. It must
not remove runtime, resources, README, or LICENSE from the consumer project.

- [ ] **Step 4: Run import, tests, and runtime parse check**

```powershell
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
godot --headless --path . --script tools/check_runtime.gd
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```powershell
git add addons/rule_engine/plugin.gd addons/rule_engine/runtime/rules.gd addons/rule_engine/editor/export_plugin.gd addons/rule_engine/tools tools tests/editor
git commit -m "feat: integrate rule engine with Godot editor"
```

### Task 7: Example, documentation, and distributable package

**Files:**

- Create: `examples/basic/`
- Create: `addons/rule_engine/README.md`
- Create: `addons/rule_engine/LICENSE`
- Create: `README.md`
- Create: `LICENSE`
- Create: `CHANGELOG.md`
- Create: `.gitattributes`
- Create: `docs/custom-types.md`
- Create: `docs/runtime-api.md`

**Interfaces:**

- The example translates a Godot signal into `mission_completed`, matches
  payload `mission_id` and fact `player.reputation`, then emits
  `business_unlock_requested` for game code to consume.
- Documentation states custom Resource scripts require `@tool`, constructors
  need default arguments, engine instances must be retained, and blackboard
  persistence is the game's responsibility.

- [ ] **Step 1: Add an end-to-end failing example test**

Load the example headlessly and assert the emitted business ID, one-time
blackboard guard, deterministic trace of rule IDs, and no scene-path access.

- [ ] **Step 2: Implement the smallest example that passes**

Keep game-specific `BusinessManager` behavior in the example, not the addon.

- [ ] **Step 3: Write consumer and extension documentation**

Include installation, optional autoload, direct engine ownership, rule file
layout, validation command, comparison semantics, once pattern, custom types,
known `@tool` restart issue, and V1 non-goals.

- [ ] **Step 4: Add package metadata**

Duplicate the full license and essential README inside the addon. Configure
`export-ignore` for tests, repository-only examples, screenshots, and research;
include the Asset Store AI-use disclosure in submission documentation.

- [ ] **Step 5: Run the complete release gate**

```powershell
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
godot --headless --path examples/basic --quit-after 10
godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd
godot --headless --path . --script tools/check_runtime.gd
```

Expected: all exit 0; no parse errors, leaked objects, validation errors, or
unexpected editor dependency.

- [ ] **Step 6: Inspect the package contents**

Verify the distributable contains only intended addon files and includes
`plugin.cfg`, runtime/resources/editor/tools, README, LICENSE, `.uid`, and
required `.import` files.

- [ ] **Step 7: Commit**

```powershell
git add examples addons/rule_engine/README.md addons/rule_engine/LICENSE README.md LICENSE CHANGELOG.md .gitattributes docs
git commit -m "docs: prepare rule engine v1 package"
```

## Final review gate

- [ ] Map every V1 capability and acceptance criterion to a passing test.
- [ ] Search for unresolved markers and vague instructions; resolve every
  occurrence before handoff.
- [ ] Verify class, property, method, signal, and enum names match the spec.
- [ ] Confirm deferred features did not enter the public API.
- [ ] Test on a clean Godot 4.7.1 project with only `addons/rule_engine/` copied.
