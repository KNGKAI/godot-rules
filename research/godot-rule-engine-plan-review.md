# Review: Godot Rule Engine Addon — Architectural Plan

**Subject:** [Godot Rule Engine Addon — Architectural Plan.md](../Godot%20Rule%20Engine%20Addon%20%E2%80%94%20Architectural%20Plan.md)
**Date:** 2026-08-31
**Target engine:** Godot 4.7.x (4.7-stable 2026-06-18; 4.7.1 2026-07-14; 4.7.2 2026-08-18)

This is a sourced review, not a rewrite. Claims about Godot APIs are traced to official 4.7 docs. Claims about prior art are traced to those projects' own documentation. Open semantic questions in the plan stay open; they are flagged, not silently decided.

---

## Verdict

The plan is a **sound Godot-native Event–Condition–Action (ECA) design**. The core constraints (no engine fork, no scene-path facts, immutable Resource config, pure conditions, queued two-phase dispatch, editor as an optional authoring layer) are the right ones for a reusable 4.7 addon.

It is **not ready to implement as written**. Milestone 0 is correctly listed first, and it is still incomplete: the example rules cannot be expressed with the proposed `CompareCondition` schema, several public-API names disagree with each other, and a handful of Godot 4.7 realities (global `class_name` collisions, `@tool` emptiness, headless script type, Resource cache, missing GDScript test runner) would become production bugs if coded from the current draft.

**Recommendation:** keep the architecture; freeze `docs/runtime-semantics.md` (Milestone 0) and apply the spec patches in [Recommended amendments](#recommended-amendments) before any runtime code.

Confidence: **high** on Godot API feasibility; **high** on architectural direction; **medium** on V1 completeness (fire-once, payload access, event/fact catalogs).

---

## 1. What the plan gets right

### 1.1 The product is a gameplay ECA engine, not a general AI/scripting layer

The in/out-of-scope split is the strongest part of the document. Existing Godot tools already occupy the excluded boxes:

| Excluded by the plan | Existing Godot-adjacent product |
|---|---|
| Behavior tree / HSM | [LimboAI](https://godotengine.org/asset-library/asset/KYd7wV/limboai-behavior-trees-state-machines-godot-46) (BT + HSM, blackboard, debugger) |
| Visual scripting / graphs | [Orchestrator](https://github.com/CraterCrash/godot-orchestrator) (Godot 4.7 → Orchestrator 2.5.x) |
| Per-frame event sheets tied to nodes | [FlowKit](https://godotassetlibrary.com/asset/KS49Hf/flowkit:-godot-visual-scripting) (Construct/Clickteam-style; `target_node: NodePath`) |
| Node-coupled production rules | [rule-based-godot](https://github.com/rvbatt/rule-based-godot) (Godot 4.1+; `RuleBasedSystem` is a `Timer` that walks node paths) |
| GOAP | [goap-godot-4](https://github.com/pixelrogueart/goap-godot-4) |

A scene-tree-independent, Resource-authored, event-indexed ECA engine is a **real gap**. FlowKit and rule-based-godot both *look* like ECA and then couple conditions/actions to `NodePath`s — the opposite of §3.2.

rule-based-godot is the closest cousin. It already has AND/OR/NOT Resource trees, Inspector authoring, a dedicated editor panel, and custom type templates. It also:

- iterates **every physics frame or on a timer** by default (the README warns “a large set of rules can take a while”);
- uses an **arbiter that selects one** satisfied rule (`FirstApplicable`, `LeastRecentlyUsed`);
- stores `_system_node` on the Resource itself.

The plan’s event index + fire-all-matching + immutable Resources is a better fit for story/unlock/economy rules than that capstone plugin. Do not converge toward it.

### 1.2 Two-phase evaluate-then-act + FIFO queue is the correct V1 execution model

This is classic production-system structure, simplified:

1. **Match** all rules for the current event (plan §13 steps 1–4).
2. **Act** the passers in deterministic order (steps 5–7).
3. **Queue** newly emitted events; never recurse.

OPS5/CLIPS/Jess use a recognize–act cycle with a conflict set; Drools uses an agenda. The plan’s version is: conflict set = all matching rules for one event, conflict resolution = `priority DESC, id ASC`, then fire *all* of them. That is appropriate for gameplay unlocks (several rules may legitimately react to `mission_completed`). It is *not* RETE and does not need to be — excluding “full forward-chaining inference” is correct.

The queue also matches how you want traces to look: one event, then its listeners, then the next event. Recursive `emit` inside `execute` is how you blow the stack and make “why did this fire?” unanswerable.

This is a **project choice**, not “the” meaning of ECA. HiPAC fires same-coupling sibling rules as concurrent nested transactions with no single-rule conflict set ([McCarthy & Dayal, SIGMOD 1989](https://dl.acm.org/doi/pdf/10.1145/66926.66946)). OPS5/Drools fire **one** activation then rematch. Immediate HiPAC coupling nests cascades as subtransactions; deferred postpones to transaction end. An independent deep-research pass (Partial coverage) confirmed: classic sources do **not** uniquely require evaluate-all-then-act, FIFO-only dispatch, RETE, or a Drools agenda. Keep two-phase+queue because it is teachable and testable for *gameplay* rules — document it as such, not as textbook ECA.

### 1.3 Godot 4.7 actually has the editor APIs the plan assumes

All of the following exist in the **4.7** class reference / tutorials:

| Plan need | Official API | Source |
|---|---|---|
| Main “Rules” workspace | `EditorPlugin._has_main_screen()`, `_make_visible()`, `_get_plugin_name()`, `_get_plugin_icon()`; add the panel with `EditorInterface.get_editor_main_screen().add_child(...)` | [Making main screen plugins](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_main_screen_plugins.html) |
| Workspaces around it | `main_screen_changed` lists **2D, 3D, Script, Game, Asset Store**; the main-screen tutorial still says “AssetLib” | [EditorPlugin](https://docs.godotengine.org/en/4.7/classes/class_editorplugin.html) |
| Inspector plugins | `add_inspector_plugin` / `remove_inspector_plugin`, `EditorInspectorPlugin`, `EditorProperty` | same |
| Undo/Redo | `EditorPlugin.get_undo_redo()` → **`EditorUndoRedoManager`**, not raw `UndoRedo` | [EditorUndoRedoManager](https://docs.godotengine.org/en/stable/classes/class_editorundoredomanager.html); UndoRedo docs say plugins must use the manager |
| Optional autoload | `add_autoload_singleton` / `remove_autoload_singleton` from `_enable_plugin` / `_disable_plugin` | [Making plugins — Registering autoloads](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_plugins.html) |
| Later debugger | `add_debugger_plugin(EditorDebuggerPlugin)`; game side `EngineDebugger.register_message_capture` / `send_message` | [EditorDebuggerPlugin](https://docs.godotengine.org/en/4.7/classes/class_editordebuggerplugin.html) |
| Global class discovery | `ProjectSettings.get_global_class_list()` → `{base, class, icon, language, path}` | [ProjectSettings](https://docs.godotengine.org/en/latest/classes/class_projectsettings.html) |
| Headless CLI | `--headless`, `-s/--script`, `--path` | [Command line tutorial (4.7)](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html) |

The mock `2D | 3D | Script | Game | Rules` is slightly stale: 4.7’s own signal documents **Asset Store** as a first-class workspace. A custom main screen still sits **to the right** of those buttons; that does not block V1.

**Game is still a main screen in 4.7.** Default embedding is a **floating window**, not docked. [PR #120736](https://github.com/godotengine/godot/pull/120736) (docked Game by default) is **4.8**, merged after 4.7.1. Do not assume 4.7 looks like 4.8.

Official attach pattern: `EditorInterface.get_editor_main_screen().add_child(panel)` then **`hide()` immediately** — the editor will not hide it for you. The container is a `VBoxContainer`; the child needs `SIZE_EXPAND_FILL`. `_get_plugin_icon()` should be white, transparent, 16×16. `_handles(object)` can auto-focus the Rules workspace when a Rule Resource is selected.

### 1.4 Resource-as-config + separate runtime state is how Godot wants this done

Official Resources tutorial: Resources are data containers; the engine **loads a path once and returns the cached copy**; `.tres` is VCS-friendly text; **export converts text resources to binary** (`editor/export/convert_text_resources_to_binary` defaults to `true`).

That is exactly why §3.3 (“do not store `rule.has_fired` on the Resource”) is non-negotiable. It is also why “one Rule per `.tres`, RuleBook holds `ExtResource`s” is the right Git strategy: subresource IDs inside a fat RuleBook are merge poison. Godot 4’s TSCN/TRES format uses string-based UIDs for external files (`uid://...`) and separate `id="..."` for subresources ([TSCN file format](https://docs.godotengine.org/pl/4.x/engine_details/file_formats/tscn.html)).

### 1.5 Dictionary iteration is insertion-ordered at runtime

4.7 Dictionary docs: “Dictionaries will preserve the insertion order when adding new entries.” The plan is still right to **sort explicitly** (`priority DESC, id ASC`) rather than trust load order or dict iteration — serialization historically *sorts keys* (godot#90142 / #104503), so “the order we inserted into `event_index`” is not a disk-stable contract. Sorting on dispatch (or once at index rebuild) is the correct determinism story.

### 1.6 Autoload named `Rules` (not `RuleEngine`) is the right optional singleton

Godot 4.7.1 still rejects autoload names that collide with a global `class_name` ([godot#121744](https://github.com/godotengine/godot/issues/121744), [godot#119055](https://github.com/godotengine/godot/issues/119055)). Naming the class `RuleEngine` and the optional autoload `Rules` avoids that trap. Instantiable-without-autoload (§33) is also correct.

---

## 2. Confirmed Godot 4.7 traps the plan understates

### 2.1 `@tool` is stricter than “resources should generally use `@tool`”

Official plugin tutorial, 4.7:

> In addition to the EditorPlugin script, any other GDScript that your plugin uses must *also* be a tool. **Any GDScript without `@tool` used by the editor will act like an empty file!**

And from [Running code in the editor](https://docs.godotengine.org/en/4.7/tutorials/plugins/running_code_in_the_editor.html):

- Any GDScript a tool script *uses* must also be a tool, or the editor cannot construct instances.
- Extending a `@tool` script does **not** make the child a tool.
- `_init()` on custom Resources must give every parameter a default, or Inspector creation breaks.

Implication for this addon: **every** `RuleCondition` / `RuleAction` script that the Rules workspace instantiates — including *project* subclasses — must be `@tool`. A player’s `OwnsVehicleCondition` without `@tool` will look like an empty Resource in the editor. Milestone 5 “automatic discovery” must also warn when a discovered class is not a tool.

There is a long-standing Godot 4 bug where `@tool` scripts sometimes need an editor restart to take effect ([GH-66381](https://github.com/godotengine/godot/issues/66381)). Document that in the user guide; do not treat it as an addon bug.

### 2.2 `class_name AllCondition` will collide

`class_name` is a **process-wide unique identifier**. The official plugin tutorial prefixes (`MyButton`). Names in the plan — `Rule`, `RuleBook`, `AllCondition`, `AnyCondition`, `NotCondition`, `CompareCondition`, `ExistsCondition`, `RuleEngine`, `RuleContext`, `RuleEvent` — are the names every other addon and every game project also wants.

**Required V1 prefix**, e.g. `RERule`, `REAllCondition`, or `RuleEngineAllCondition`. Keep the *folder* names short; keep the *global* names namespaced. This is cheaper to do before the first `.tres` is saved (the script path is stored in the file; the class name is what users type).

### 2.3 Headless validation cannot be “`--script tools/validate_rules.gd`” as currently drawn

4.7 command-line tutorial:

- `--script` scripts **must inherit `SceneTree` or `MainLoop`**.
- Path is interpreted as `res://...` relative to `--path`.
- `--check-only` only *parses* a script; it does not run validation.
- `--test` is the **engine C++ doctest** suite (`scons tests=yes`), not GDScript tests.

Exit codes: `SceneTree.quit(exit_code)` is the supported API (0 = success, non-zero = error, portable range 0–125). A 4.2 bug where `quit(1)` returned 0 under `--script` was fixed in 4.3 ([godot#88055](https://github.com/godotengine/godot/issues/88055) / #89229). On current 4.7, `quit(1)` is the right CI contract.

Sketch the tool as:

```gdscript
extends SceneTree

func _init() -> void:
    var issues := RuleValidator.new().validate_project()
    var errors := issues.filter(func(i): return i.severity == ValidationIssue.Severity.ERROR)
    quit(1 if errors.size() > 0 else 0)
```

Editor APIs (`EditorInterface`, inspector plugins) are **not** available in this path. That matches the plan’s “validation independent from the editor UI” — keep it that way.

### 2.4 There is no official GDScript unit-test runner

Godot’s `--test` is C++. For GDScript in 4.7:

| Framework | 4.7 status |
|---|---|
| **GUT** | [9.7.1 / `godot_4_7` branch](https://github.com/bitwes/Gut) explicitly for 4.7.x; CLI + JUnit XML |
| **GdUnit4** | [master / 6.2.x](https://github.com/godot-gdunit-labs/gdUnit4) lists 4.7 and 4.7.1 |

The plan’s `tests/` tree is right; it never names a runner. **Pick one in Milestone 1.** Recommendation: GUT 9.7.x if the suite is GDScript-only and you want the smallest addon; GdUnit4 if you want C# tests later. Tests live *outside* `addons/rule_engine/` so consumers do not ship them — that part of the plan is correct.

### 2.5 `get_global_class_list().base` is the *immediate* parent

Discovery cannot be `entry.base == "RuleCondition"`. Project subclasses of `AllCondition` have `base == "AllCondition"` (or whatever prefixed name you choose). Walk the `base` chain (and/or instantiate in the editor and use `is RuleCondition`).

`ClassDB.get_inheriters_from_class()` **does not include `class_name` scripts** (ClassDB docs). C# `[GlobalClass]` types appear in `get_global_class_list()` with `language` ≠ GDScript; V1 can ignore them, but the plan should say so.

A 4.7.dev3 bug left `base` empty for `extends Outer.Inner` ([godot#118338](https://github.com/godotengine/godot/issues/118338)). Do not use inner classes as discoverable condition/action types. Official Resources tutorial already warns inner `class` Resources do not serialize custom properties.

### 2.6 Resource cache + `enabled` on the Resource

“When the engine loads a resource from disk, **it only loads it once**.” Mutating `rule.enabled = false` at runtime mutates the shared cached Resource for every `RuleBook` that references it, and it dirties the asset if anything saves.

`enabled` as an *authored* default is fine. Runtime enable/disable belongs in **Rule runtime state** (the thing §3.3 already requires), keyed by rule id. Same for any future “times fired / cooldown remaining”.

### 2.7 Custom Resource `_init` and Inspector

Official Resources tutorial: every `_init` parameter needs a default or Inspector creation/editing breaks. Condition/action scripts must stay parameterless-constructible.

### 2.8 Plugin autoload registration belongs in `_enable_plugin`, not `_enter_tree`

Official pattern (4.7 making-plugins tutorial) registers autoloads in `_enable_plugin` / `_disable_plugin` so disable actually removes them. `_enter_tree` runs on editor load whenever the plugin is on; mixing the two is how you get duplicate autoload errors.

### 2.9 Nested typed collections are **not** valid GDScript

Plan writes `event_index: Dictionary[StringName, Array[Rule]]`. Typed dictionaries exist (4.4+), but **nested typed collections are explicitly unsupported**: `Array[Array[int]]` and `Dictionary[String, Array[Resource]]` are illegal ([GDScript basics — Typed arrays / Typed dictionaries](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)).

Use one of:

```gdscript
var event_index: Dictionary = {}  # untyped; values are Array[Rule] by convention
# or
var event_index: Dictionary[StringName, Array] = {}
```

and keep a **pre-sorted** `Array` per event. Do not trust Dictionary iteration for rule order.

On disk, a typed `Array[CustomResource]` stores the **script** as `ExtResource`, not the `class_name` string ([forum MRP](https://forum.godotengine.org/t/saving-nested-custom-resources/123063)). Inner `class` Resources serialize as `Array[Object]` and drop custom properties ([godot#74712](https://github.com/godotengine/godot/issues/74712); official Resources tutorial warning). Never use inner classes for Condition/Action.

`Resource.new()` as an `@export` default has been observed to become `null` in **release** exports (4.5.1). Use `= []` on typed arrays; do not assign an untyped `[]` in `_init` ([godot#75204](https://github.com/godotengine/godot/issues/75204)).

### 2.10 Resource cycles are forbidden by design

§28 lists “Recursive/cyclic Resource structures” as a validator check. That is not optional polish. Core: Resources/`RefCounted` **do not support circular references**; the editor errors “Recursion detected, unable to assign resource”; `ResourceSaver.save()` **writes `null`** for the back-edge ([godot#89961](https://github.com/godotengine/godot/issues/89961), [godot#86641](https://github.com/godotengine/godot/issues/86641)).

Condition trees that accidentally wrap into themselves will silently lose children on save. Validator DFS is required. Reverse links (action → parent rule) must be `StringName` ids, not Resource pointers.

### 2.11 `@export var value: Variant` only has a type picker in one spelling

KoBeWi’s [PR #89324](https://github.com/godotengine/godot/pull/89324) added a Variant type dropdown. In 4.5+ only this works ([godot#110205](https://github.com/godotengine/godot/issues/110205)):

```gdscript
@export var value: Variant            # type picker
@export var value: Variant = 0        # locked to int
@export var value = 0                 # locked to int
```

`@export_custom` + Variant is unusable (`"<null>"` label, [godot#95693](https://github.com/godotengine/godot/issues/95693)). Milestone 2 still needs a dedicated comparison-RHS `EditorProperty` (or a tagged `CompareValue` Resource). Do not ship Compare with a defaulted Variant.

Getters/setters on exports **do not run in the Inspector unless `@tool`**. Nuance vs §2.1: a *pure data* Resource can omit `@tool` and still show `@export` fields; the moment Compare clamps or migrates in a setter, it must be `@tool`. Plugin-held scripts remain “empty file” without `@tool`.

### 2.12 `==` and `in` disagree on numbers

Official: `1 == 1.0` is **true** ([int operators](https://docs.godotengine.org/en/stable/classes/class_int.html)). Official: `Array.find` / `has` / `in` **do not coerce** int vs float — “`7` (int) and `7.0` (float) are not considered equal” ([Array.find](https://docs.godotengine.org/en/stable/classes/class_array.html)).

So `contains` as specified in §6 is a landmine: Inspector may save `5.0`, authored list may be `[5]`. Normalize numerics (and intern String/StringName) **inside Compare**, never use raw `Array.has` for mixed types. Another reason to drop `contains` from V1.

`String == StringName` is true; `Array ==` of mixed String/StringName elements is not ([PR #68747](https://github.com/godotengine/godot/pull/68747)). Dictionary lookup uses `StringLikeVariantComparator`, so `dict["foo"]` and `dict[&"foo"]` hit the same slot — the stored key type is whichever was inserted first.

### 2.13 Commit `*.uid` (and do not copy `.tres` in Explorer)

Godot 4.4 introduced sidecar `file.gd.uid` because scripts cannot embed a UID. Official 4.4 article: **commit `.uid` files; do not gitignore them**; move the `.uid` with the script; re-save scenes/resources after upgrading ([UID changes coming to Godot 4.4](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)). Gitignoring `.import` produced different UIDs per machine and scene merge hell ([godot#68661](https://github.com/godotengine/godot/issues/68661)).

Copying a `.tres` outside the editor duplicates UIDs ([godot#102490](https://github.com/godotengine/godot/issues/102490)). The Rules workspace “Duplicate Rule” must go through `ResourceSaver` / editor APIs, not `DirAccess.copy`.

Authored `id: StringName` remains the **domain** key. File UID is for moves; `resource_scene_unique_id` is empty on standalone `.tres` and unstable across “Make Unique”. The plan is already right to forbid using subresource IDs as logical identifiers.

### 2.14 `add_custom_type` is not a collision-avoidance strategy on 4.6+

If prefixing `class_name` feels ugly, `EditorPlugin.add_custom_type` looks like an alternative. On **4.6+** a custom type **without a matching `class_name` cannot be instantiated** from the Create dialog ([godot#114349](https://github.com/godotengine/godot/issues/114349)). It also cannot appear in `Array[MyType]`. Prefix `class_name`; do not use `add_custom_type` as the primary registration path.

4.7 `get_global_class_list()` dumps also include undocumented `is_abstract` and `is_tool` keys ([godot#118338](https://github.com/godotengine/godot/issues/118338)). Read them with `.get("is_tool", false)` and prefer that over instantiating to probe `@tool`.

---

## 3. Spec holes that block Milestone 1

These are not style nits. The example in §38 cannot be implemented from §§5–7.

### 3.1 Event payload is not a fact (blocker)

§38 condition:

```
ALL
 ├ event_payload.mission_id == intro_04
 ├ player.reputation >= 10
 └ NOT world.chop_shop_unlocked
```

`CompareCondition` as specified:

```gdscript
@export var fact: StringName
@export var operator: CompareOperator
@export var value: Variant
```

`fact` is resolved only through `RuleFactProvider`. `event_payload.mission_id` is not a fact. Nothing in the condition model reads `context.event_payload`.

**Fix (pick one, document in runtime-semantics.md):**

1. **Preferred:** a first-class `PayloadCompareCondition` (`key`, `operator`, `value`) plus keep `CompareCondition` for facts.
2. Or a `source` enum on Compare: `FACT | PAYLOAD`.
3. Or a reserved fact prefix the engine resolves (`payload.mission_id`) — worse, because it collides with real facts and hides the data plane.

Without this, every real rule in the motivating example needs a custom condition on day one, which contradicts “core V1 conditions are enough for the tutorial”.

### 3.2 `check()` vs `evaluate_rule()` vs actions (blocker)

§10 / §37:

- `check(rule_id, payload) -> bool`
- `evaluate_rule(rule, context) -> bool`

Neither says whether **actions run**. Queryable rules (`event == &""`) are useless if `check()` also fires `EmitEventAction`. Convention in ECA: **query = match only**. Spell it out:

- `check` / `evaluate_rule` — conditions only, no actions, no queue.
- `emit_event` — two-phase match+act for reactive rules.
- Optional later: `fire(rule_id)` for “run this queryable rule’s actions now”.

### 3.3 Missing-fact semantics (Milestone 0, still blank)

`get_fact` returns `null` when absent. Then `player.reputation >= 10` on a missing fact is `null >= 10`. GDScript will either error or yield a surprising bool. `ExistsCondition` exists, which implies missing ≠ false, but Compare is unspecified.

Decide and test:

| Policy | Behavior |
|---|---|
| **A. Missing is false** (SQL three-valued collapsed) | Compare on missing fact → fail the condition, no error |
| **B. Missing is error** | Compare on missing fact → validation error / runtime `push_error` + fail |
| **C. Strict Exists** | Compare is illegal unless Exists also holds; validator enforces |

Recommendation: **A at runtime** (games keep running), **warning in validation** when a fact name is not in an optional catalog. Never throw through the dispatch loop.

### 3.4 `contains` / `not_contains` on `Variant` (underspecified)

What does `contains` mean for `int`, `String`, `Array`, `PackedStringArray`, `Dictionary`? Define a small table or drop `contains` from V1 (you already say “avoid dozens of operators”). Recommendation: V1 operators = `== != > >= < <=`; add `contains` only for `Array`/`Packed*Array`/`String` and fail closed on other types.

### 3.5 `RuleContext.engine` vs “conditions are pure”

Giving every condition a live `RuleEngine` means a custom condition *can* `context.engine.emit_event(...)`. Two-phase + queue cannot save you from that. Either:

- pass a **read-only view** into `evaluate`, and the full context only into `execute`; or
- document “if a condition calls emit/set, that is a project bug” and add a debug-mode guard.

### 3.6 Signal name mismatch in the plan itself

| Location | Name |
|---|---|
| §37 | `signal event_received(event)` |
| §38 | `Rules.event_emitted.connect(_on_rule_event)` |

Also §38 handler takes `(name, payload)` while §37’s signal takes a `RuleEvent`. Freeze one:

```gdscript
signal event_received(event: RuleEvent)
signal event_emitted(event: RuleEvent)  # if you need “engine queued this”
signal rule_evaluated(rule: Rule, passed: bool)
signal rule_fired(rule: Rule)
signal action_executed(rule: Rule, action: RuleAction)
signal dispatch_failed(reason: String)
```

`event_emitted` as used in the example is really “an action asked the engine to emit”, which is easy to confuse with the inbound `emit_event` API.

### 3.7 Queryable rules and the event index

`event == &""` rules must **not** sit in the event index. `emit_event` should never run them. Index only non-empty event names. Document it.

### 3.8 `max_chain_depth` vs `max_events_per_dispatch`

Undefined. Propose:

- `max_events_per_dispatch` — hard cap on queue drains for one public `emit_event` call (includes the seed event).
- `max_chain_depth` — optional; count “hops” from the seed (seed = 0, events emitted by its actions = 1, …). Often redundant with the event cap.

On trip: stop, `dispatch_failed`, do not execute further actions, leave runtime state as-is (do not try to roll back game systems you do not own).

### 3.9 Reentrancy

What happens if `emit_event` is called while a dispatch is already running (from an action that talks to a game system that emits another rule event synchronously)?

**Required:** nested `emit_event` **enqueues** onto the same FIFO and returns; it does not start a second drain. One “outer” drain owns the loop. Otherwise two-phase is fiction.

`unload_book` during dispatch: reject or defer until the drain finishes.

### 3.10 Duplicate IDs, load twice, disabled rules

Milestone 0 lists these as to-be-defined. Propose:

- Duplicate id across loaded books → **hard error** on `load_book`, book not registered.
- `load_book` twice (same Resource) → no-op or replace; do not double-index.
- `enabled == false` → absent from event index (or skipped at match); changing authored `enabled` requires index rebuild; runtime override lives in runtime state.

### 3.11 Blackboard vs “no generic state mutation”

§16 ships `SetBlackboardFactAction`. §17 forbids `Set player.money = 100000`. That is consistent **if and only if** the blackboard is rule-private (`rules.intro_seen`) and is **not** the `RuleFactProvider` for `player.*`.

Make the split mechanical:

- `RuleFactProvider` — **read-only** world/game facts.
- `RuleBlackboard` — **read/write** rule-owned flags, optionally exposed to Compare as a second lookup (`blackboard.intro_seen`) or via `BlackboardCompareCondition`.

A `DictionaryFactProvider` that is also writable from actions will become the “set player.money” backdoor the plan forbids. Don’t give core a `SetFactAction` against the provider.

### 3.12 Fire-once / refraction is runtime state (industry: week-one feature)

Out of scope as a first-class feature in §36.8. Field practice disagrees on the *urgency*, not the *mechanism*:

- Construct **Trigger once while true**, GDevelop **Trigger once**, Fusion **Run this event once** exist because `lives == 0 → play sound` otherwise fires 60 times/sec.
- CLIPS **refraction**: the same rule+facts instantiation does not fire again until facts change.
- GAS cooldowns are **Gameplay Effects**, not bits on the ability asset.

Every example in this plan (`unlock_chop_shop`, `intro_finished`) is a once-rule. A blackboard flag *can* encode it. Designers will still ask for a checkbox.

**Do not store `has_fired` on the Resource.** Split:

| Field | Where | Meaning |
|---|---|---|
| `enabled` | Resource | Designer on/off; git |
| runtime enabled | Engine map keyed by `rule.id` | cheats / stage |
| `fired_count` / last tick | Engine map | once, cooldown, refraction |

V1 minimum: document the blackboard pattern **and** mention that `max_fires: int` (0 = unlimited, 1 = once) writing *runtime state* is the first post-MVP if a real project uses the addon. Cooldown duration can wait.

### 3.16 Two-phase is theater without a fact snapshot

If `RuleFactProvider.get_fact` reads live game objects, and action 1 of a passing rule calls into `BusinessManager.unlock` which mutates reputation **before** rule 2’s conditions… wait: two-phase evaluates *all* conditions first, so same-event conditions are safe **unless a condition itself reads a moving target across the evaluate loop** (e.g. another system on a signal the engine emits mid-evaluate — it should not) **or** the provider is mutated by a *previous event’s* actions that re-entered (forbidden if emit always enqueues).

The remaining hole: **conditions of event N+1 must see writes from event N’s actions.** That is intended. The hole inside one event: **blackboard writes in phase 2 must not change the snapshot used in phase 1** (already implied). **Live providers that other threads/systems mutate during phase 1** are undefined.

**Freeze:** at dequeue, snapshot `payload` (shallow copy) and treat facts/blackboard as a **read view for the whole match phase**. Blackboard writes apply immediately to runtime state but do not change that view. Do not snapshot the entire game — snapshot is “no writes from *this engine* are visible to same-event conditions.” Document that a FactProvider which is not safe to call twice in one event is a project bug.

Industrial precedent: HiPAC **deferred** coupling (same transaction, end); Drools **`drools.sequential=true`** (“evaluate each rule once, ignore insert/modify during the pass”). Construct evaluates-then-acts **per row**, so later rows see earlier mutations — that is the bug class two-phase exists to avoid. Designers from Construct will expect `Emit B` to run B before the next same-event rule. **Draw that diagram in runtime-semantics.md.**

### 3.17 Exclusive / halt (cheap; loot tables)

Drools `activation-group` / `fireAllRules(1)`; Fusion groups. “First matching loot row” and “tutorial beats generic VO” show up constantly. Your sort already defines order. A single authored `exclusive: bool` (or `HaltEventAction`) that skips later passers **of this event** is a one-field feature. Do not build a second arbiter (that is rule-based-godot). Optional for V1; specify the semantics so people do not invent it incompatibly.

### 3.18 Instance identity is out of scope — say so

V1 is global. “This chest, once” needs payload `source_id` + runtime key `(rule.id, source_id)`. GDevelop documents that trigger-once is **not per instance**. Document the limitation; `rules.chest_opened` as a single blackboard flag will not scale. Do not pretend it does.

### 3.13 No event catalog, no fact catalog

Validation of “unknown/empty events” (§28) cannot work if event names are free `StringName`s with no registry. Same for typos in `player.reputaton`.

V1 does not need a heavy schema system. It needs:

- `RuleEventCatalog` Resource (optional): list of known event names (+ optional payload key types).
- `RuleFactCatalog` Resource (optional): list of known fact keys (+ types).
- Validator: unknown names = **warning** if a catalog is loaded, silence if not.

Without this, “headless validation” mostly checks null children and duplicate ids — still worth doing, but weaker than the plan implies.

### 3.14 Payload Dictionary key types

Examples mix `"mission_id"` and `&"mission_id"`. Godot Dictionary uses a string-like comparator, so they often collide, but typed `Dictionary[StringName, Variant]` will not accept String keys. Freeze: **payload keys are `StringName`**. Provide a small helper on `emit_event` that intern’s String keys, or type the parameter as `Dictionary` and normalize on entry.

### 3.15 `value: Variant` in the Inspector

A raw `@export var value: Variant` is a poor authoring UX (type picker + value, easy to save the wrong type). Priority custom `EditorProperty` for “comparison RHS” is correctly listed in §26 — treat it as **Milestone 2 required**, not polish. Until then, consider typed sibling fields (`int_value`, `float_value`, `string_value`, `bool_value`) with an enum, which serializes cleanly.

---

## 4. Prior-art lessons to steal, not copy

### rule-based-godot (rvbatt)

Closest Godot cousin ([repo](https://github.com/rvbatt/rule-based-godot), [thesis](https://linux.ime.usp.br/~rvbatt/mac0499/)). Resource trees, Composite matches, Command actions, Strategy arbiter. It is a **per-frame / poll** engine: `iterate()` gathers all satisfied rules, then fires **one**. No event name, no payload, no queue. `SetProperty`/`CallMethod` is the generic mutation API this plan correctly refuses. `_bindings` and `_system_node` live on Resources.

Steal: AND/OR/NOT trees, “don’t pick Abstract*” in the Inspector, script templates.
Do not steal: NodePath conditions, per-frame iteration, exclusive arbiter as the default, runtime state on Resources.

### FlowKit (negative space)

[Construct/Fusion event sheets for Godot](https://github.com/LexianDEV/FlowKit): `target_node: NodePath`, per-frame poll, `on_process` as a tick. Issue [#53](https://github.com/LexianDEV/FlowKit/issues/53) is last-writer-wins on movement. That is visual scripting for scenes. This addon is named gameplay events over logical facts. Do not grow toward CharacterBody2D actions.

### LimboAI blackboard

Best Godot key/value store ([docs](https://limboai.readthedocs.io/en/stable/classes/class_blackboard.html)): **BlackboardPlan** (schema on the resource) vs **Blackboard** (runtime); `has_var` vs `get_var(default, complain)`; scopes that never write through to parent. Copy the split and the missing-key API. Do **not** copy `bind_var_to_property` — that reintroduces scene coupling.

### Dialogue Manager (nathanhoad) and Questify

[Dialogue Manager State](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/State.md): runtime is **stateless**; the game is authority; mutations call game methods; **Ignore Missing State Values** exists because missing state is an authoring problem.

[Questify](https://github.com/TheWalruzz/godot-questify): runtime **must** `quest.instantiate()` so the authored `.tres` is never mutated; conditions do not reach into the game — the addon emits `condition_query_requested` and the game answers. Same inversion as `RuleFactProvider`. Shared Resource instances sharing state is a documented Godot quest-tutorial footgun.

### Unreal GAS (sibling, not competitor)

[Gameplay Ability System](https://docs.unrealengine.com/5.4/en-US/understanding-the-unreal-engine-gameplay-ability-system/): events (`FGameplayEventData`) vs tags/attributes (world); **tags are catalogued** (`DefaultGameplayTags.ini`) so typos are editor errors; Gameplay Effects are the only legal attribute mutation; cooldowns are runtime GEs; cues are cosmetic and must not write sim. Transfer: catalog names, payload vs facts, `EmitEventAction` as the cue/effect split. GAS still ships once/cooldown in every project’s V1.

### HiPAC / Drools / CLIPS / event sheets

- HiPAC ECA **coupling modes**: your two-phase+queue is **deferred** (same “transaction”, then apply, then next event). Immediate coupling is the recursive dispatch you banned.
- Drools default is Rete agenda (fire one, rematch). **`drools.sequential=true`** is the industrial name for “evaluate each rule once, ignore WM changes during the pass” — that is your V1, and Red Hat documents it as the right mode for *stateless* decision passes.
- CLIPS/OPS5 **refraction** is the once-flag. Rete exists for many-pattern × many-object; gameplay ECA is many-rule × one-event. Do not add it.
- Construct/GDevelop evaluate-then-act **per row** (later rows see earlier mutations) and still needed **trigger once** on week one. Your two-phase fixes the first; you still need an answer for the second.

**When you would revisit RETE:** facts are large relational sets and rules join them (`NPC near player AND faction == X`). That is a query engine. Until then, the event index is the 80% of Rete that ECA needs.

---

## 5. Editor / packaging notes

### 5.1 Main screen + Inspector, not a private Inspector

§25–26 is the right split. LimboAI and AnimationTree succeed because they **select a Resource and let the Inspector edit it**. Rebuilding Inspector inside the Rules dock is how plugins die.

Use `_handles()` + `_edit()` if you want selecting a Rule in the FileSystem dock to focus the Rules workspace (the main-screen tutorial documents this).

Undo: every tree mutation goes through `EditorUndoRedoManager` (`EditorPlugin.get_undo_redo()`). Direct `rule.actions.append(...)` without an undo action violates §27.

**Do not mix UndoRedo APIs.** Godot 4 `UndoRedo` takes `Callable`. `EditorUndoRedoManager` takes **object + method name + varargs** (`add_do_method(target, "set_name", new_name)`). Lambdas will not match. For nested `.tres` edits, pass `custom_context` (outer resource / scene root); `force_fixed_history()` only when the nested resource has no path yet. Docs: **do not** `add_do_reference` / `add_undo_reference` for Resources. Tool-script property writes without the manager create **no** undo.

Inspector plugins: `preload("…").new()` (`RefCounted`), not `instantiate()`. Always `remove_inspector_plugin` on `_exit_tree`. `_parse_property` returning `true` **replaces** the built-in editor.

Debugger (Milestone 7): editor `_capture` sees the **full** prefix (`"rules:ping"`); the game-side capture has the prefix **stripped** (`"ping"`). `EngineDebugger` is core (present in the running game); `EditorDebuggerPlugin` is editor-only. Always `EngineDebugger.is_active()` before spam.

`plugin.cfg` in 4.7.1 **requires** all five keys (`name`, `author`, `version`, `description`, `script`) or the plugin is not listed (`editor_plugin_settings.cpp`). `script` is relative to the addon folder.

### 5.2 Creating *external* Rule files from the workspace is the hard editor problem

The Git layout is easy to describe and annoying to implement: “New Rule” must `ResourceSaver.save` a new `.tres`, then append an `ExtResource` to the RuleBook, all in one undo action, and pick a path. Milestone 2 (plain Inspector) should already support “New inherited Resource” the Godot way so Milestone 3 is not a blocker for dogfooding.

### 5.3 Condition trees as local subresources

§21 allows condition trees as subresources inside a Rule file. That is the right tradeoff (one file per rule). It is still merge-hostile if two people edit the same rule’s tree — subresource `id="CompareCondition_xxxx"` churn. Accept it; do not flatten conditions into a second file per node in V1.

### 5.4 Export binary conversion

`editor/export/convert_text_resources_to_binary` defaults **true**. Runtime will see `.res`, not `.tres`. Do not parse `.tres` text in the engine; always `ResourceLoader.load`. Serialization tests must cover reload-after-save, not string equality of `.tres`.

### 5.5 Runtime must not *mention* editor classes (parse-time, not runtime)

§23 is correct and **stricter than `if Engine.is_editor_hint()`**. Export templates do not contain editor classes. GDScript has **no conditional compilation**. A runtime script that even *names* `EditorInterface` / `EditorPlugin` fails to parse on export ([godot#91713](https://github.com/godotengine/godot/issues/91713)) — the `is_editor_hint()` branch is never reached.

Enforce it:

- `runtime/` and `resources/` never `preload` anything under `editor/`.
- `plugin.gd` is the only file that extends `EditorPlugin`.
- Editor helper types: avoid `class_name` so they are not pulled in by the global class list at game load; or strip them with `EditorExportPlugin._export_file()` + `skip()` (Dialogue Manager and Dialogic both do this).
- CI: `godot --headless --script res://addons/rule_engine/tools/check_runtime.gd --check-only` on runtime files — `--check-only` fails if those files parse `Editor*` identifiers.

`Engine.is_editor_hint()` is still the right *runtime* branch for `@tool` Resources. It does not hide identifiers from the parser.

Last-resort if a `@tool` Resource must talk to the editor: `Engine.get_singleton("EditorInterface")` as a Variant (no typed identifier). Prefer not to.

Feature tags: `OS.has_feature("editor")` is the editor **binary** (including F5); `Engine.is_editor_hint()` is the editor **UI** only; `template` is an exported game ([feature tags](https://docs.godotengine.org/en/latest/tutorials/export/feature_tags.html)).

### 5.5b Autoload must be a Node; RuleEngine can stay RefCounted

Official autoload tutorial: autoloads **must extend Node** (or a scene). You cannot autoload a bare `RefCounted`. The plan’s core `RuleEngine extends RefCounted` is still right for “many instances, no tree.” The optional `Rules` singleton is a **Node wrapper** around one engine, registered in `_enable_plugin` / removed in `_disable_plugin` ([Making plugins](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_plugins.html)).

Dialogue Manager is the canonical pattern (`add_autoload_singleton("DialogueManager", ...)`). Dialogic also adds the singleton in `_enter_tree` so it exists before `project.godot` is rewritten ([godot#108047](https://github.com/godotengine/godot/issues/108047) — `_enable_plugin` autoloads can be late). Autoload name must not equal any `class_name`.

`add_autoload_singleton` writes **Project Settings**. The EditorPlugin does not run in export templates, but the autoload **does** if that entry is still in `project.godot`. Disabling the plugin is what keeps `Rules` out of shipped games that opted out. Autoload scripts must not mention editor types. 4.7.1’s plugin method has no “global/singleton” flag (open PR #80519 is not in 4.7.1).

Signals work on `RefCounted` (they are `Object` features). Connections **do not keep the emitter alive**. If the last `Ref` to a non-autoload engine drops, listeners go dead. Document: “keep a member reference, or use the Node autoload.” RefCounted cycles leak (engine ↔ listener both RefCounted); use `weakref` for back-refs. Do not `queue_free()` an autoload.

### 5.5c Packaging for the 4.7 Asset Store

The [Godot Asset Store](https://godotengine.org/article/introducing-the-godot-asset-store/) is new in 4.7 and replaces in-editor AssetLib. Official submit guide: [Submitting to the Asset Store](https://docs.godotengine.org/en/4.7/community/asset_store/submitting_to_asset_store.html).

- Files under `addons/rule_engine/`.
- `LICENSE` (full text + copyright year/holder) at **repo root and inside the addon folder** — the folder users keep.
- `plugin.cfg`: `name`, `description`, `author`, `version`, `script` (path **relative to the addon folder**). No license key in cfg.
- `.gitattributes` `export-ignore` so store ZIPs do not ship `tests/`, `examples/` extra, screenshots.
- **AI disclosure is mandatory** if any LLM was used (including “AI then hand-edit”).
- `EditorExportPlugin` should skip `editor/` from exported **games** (consumers still need editor files in the project for the plugin).

`--check-only` is parse-only (no `_init`). `--quit-after N` is **frame count**, not seconds. CI sequence: `--import` (warm `.godot/`) then GUT/GdUnit4 headless.

### 5.6 C# / .NET

4.7 ships a .NET editor. V1 GDScript-only is fine. Say so. Do not promise `get_global_class_list()` discovery of `[GlobalClass]` C# conditions until someone asks. C# *does* have `#if TOOLS` (official plugin template); GDScript does not.

---

## 6. Testing gaps relative to the plan’s own claims

§34 lists good unit tests. Add these, because they are where this design actually breaks:

- Two-phase: rule A’s action mutates blackboard; rule B on the **same** event still sees pre-action facts during **condition** eval, then sees post-action blackboard during **its** actions (define this!).
- Nested `emit_event` from a game system called by an action — must enqueue, not reenter.
- `String` vs `StringName` payload keys.
- Missing fact vs Exists vs Compare.
- Shared Resource: two engines load the same RuleBook; runtime enable on engine 1 does not flip the Resource `enabled` seen by engine 2.
- Duplicate `load_book`.
- Cycle A→B→A hits `max_events_per_dispatch`.
- `@tool`-less custom condition is rejected or warned in the editor registry.
- Headless validator: `quit(1)` on ERROR, `quit(0)` on warnings-only.

---

## 7. Recommended amendments

Apply these to the architectural plan (or to `docs/runtime-semantics.md`) before Milestone 1.

1. **Prefix all `class_name`s** (`RE*` or `RuleEngine*`).
2. **Payload compare** as a core condition (or `source` on Compare).
3. **`check()` is match-only**; document query vs reactive.
4. **Missing fact → condition fails** (no exception); validator warning.
5. **Normalize payload keys to StringName** on `emit_event`.
6. **`enabled` runtime override** in runtime state, not on the Resource.
7. **Nested emit enqueues**; one drain loop.
8. **Headless tool extends `SceneTree`**, `quit(code)`.
9. **Name a test runner** (GUT 9.7.x or GdUnit4 6.2.x).
10. **Autoload is a Node wrapper**, registered in `_enable_plugin` / `_disable_plugin`; core engine stays `RefCounted`. Name ≠ any `class_name`.
11. **Walk `base` chain** for type discovery; skip non-`@tool`; skip C# in V1.
12. **Optional event/fact catalogs** for validation.
13. **Blackboard is not the FactProvider.**
14. **Document the once-pattern** (blackboard flag) as the V1 substitute for `max_fires`.
15. **Freeze signal names** (`event_received` vs `event_emitted`).
16. **Drop `contains` from V1** or specify types.
17. **Do not put `engine` on the condition-time context** (or pass a read-only facade).
18. **EditorUndoRedoManager**, not `UndoRedo`.
19. **Custom Variant value EditorProperty in Milestone 2**, not “later”; never default `@export var value: Variant = …`.
20. **Pin Godot 4.7.1+** (4.7.2 exists); mention Asset Store workspace so the mock UI is not wrong.
21. **Event index is not `Dictionary[StringName, Array[Rule]]`** — nested typed collections are illegal; use `Dictionary[StringName, Array]` (or untyped) plus a sorted Array.
22. **Cycle-check Resource graphs** in the validator; never store Resource back-pointers.
23. **Commit `*.uid` and `*.import`**; duplicate rules through the editor, not the filesystem.
24. **Normalize int/float and String/StringName inside Compare**; do not use `Array.has` for `contains`.
25. **Snapshot payload + match-phase read view** at dequeue; blackboard writes must not leak into same-event conditions.
26. **Missing-fact Compare → false**; `NOT missing` is not true unless `Exists` said so. No 3VL.
27. **Event catalog in V1 validation** (warning if loaded); GAS tags exist because free strings silently no-op.
28. **Never write `Editor*` identifiers in runtime/resource scripts** — parse fails on export even inside `is_editor_hint()`. Strip `editor/` with `EditorExportPlugin`.
29. **LICENSE + README inside `addons/rule_engine/`** (Asset Store); GUT 9.7.1 or GdUnit4 ≥ 6.2.0; CI: `--import` then headless tests.

---

## 8. Milestone 0 exit criteria (make these answers explicit)

`docs/runtime-semantics.md` should answer, with a test for each:

1. Missing fact + Compare → ?
2. `check()` runs actions? (no)
3. How do conditions read event payload?
4. Nested `emit_event` during drain → enqueue?
5. Duplicate rule ids → fail load?
6. `enabled` authored vs runtime?
7. Action order for two passing rules on one event?
8. Action order *within* a rule? (array order — say it)
9. Blackboard visibility to conditions of later rules on the **same** event? (two-phase says **no** if blackboard is written by actions; **yes** if a condition could write — forbid that)
10. Runaway: which counter, what is left half-executed, what signal fires?
11. Queryable rules in the event index? (no)
12. Dictionary/Array payload mutation by a condition? (forbid; treat payload as read-only snapshot)
13. Fact/blackboard snapshot for the match phase of one event?
14. `NOT` of a missing fact — false, not true (avoid SQL-style 3VL surprises)?
15. Exclusive/halt for later rules on the same event?
16. Per-instance once (`source_id`) — out of scope, documented?

Until those are written down, Milestone 1 will invent incompatible answers in different files.

---

## 9. What not to change

Do not add a graph editor. Do not add RETE. Do not add delayed actions in V1. Do not put `MissionManager` in the addon. Do not make the autoload mandatory. Do not scan all rules on emit. Do not store runtime flags on `.tres`. Those constraints are the product.

---

## Sources

### Godot 4.7 (primary)

- [Godot 4.7-stable](https://godotengine.org/download/archive/4.7-stable/) (18 Jun 2026); [4.7.1](https://godotengine.org/article/maintenance-release-godot-4-7-1/); [4.7.2-stable](https://github.com/godotengine/godot-builds/releases)
- [EditorPlugin (4.7)](https://docs.godotengine.org/en/4.7/classes/class_editorplugin.html)
- [Making main screen plugins (4.7)](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_main_screen_plugins.html)
- [Making plugins (4.7)](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_plugins.html) — `@tool` emptiness, autoload in `_enable_plugin`
- [Running code in the editor (4.7)](https://docs.godotengine.org/en/4.7/tutorials/plugins/running_code_in_the_editor.html)
- [EditorUndoRedoManager](https://docs.godotengine.org/en/stable/classes/class_editorundoredomanager.html)
- [EditorDebuggerPlugin (4.7)](https://docs.godotengine.org/en/4.7/classes/class_editordebuggerplugin.html)
- [Command line tutorial (4.7)](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Resources tutorial (4.7)](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)
- [Resource (4.7)](https://docs.godotengine.org/en/4.7/classes/class_resource.html)
- [Dictionary (4.7)](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html)
- [StringName (4.7)](https://docs.godotengine.org/en/4.7/classes/class_stringname.html)
- [ProjectSettings.get_global_class_list](https://docs.godotengine.org/en/latest/classes/class_projectsettings.html)
- [SceneTree.quit(exit_code)](https://docs.godotengine.org/en/latest/classes/class_scenetree.html)
- [C++ unit testing (not GDScript)](https://docs.godotengine.org/en/latest/engine_details/architecture/unit_testing.html)
- `editor/export/convert_text_resources_to_binary` default `true` — [ProjectSettings (4.7)](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html)

### Godot issues (version-sensitive)

- [godot#88055](https://github.com/godotengine/godot/issues/88055) — `--script` exit codes (fixed 4.3)
- [godot#121744](https://github.com/godotengine/godot/issues/121744) — autoload vs `class_name` (4.7.1)
- [godot#119055](https://github.com/godotengine/godot/issues/119055) — autoload name collision (4.7 beta / 4.8 milestone)
- [godot#118338](https://github.com/godotengine/godot/issues/118338) — empty `base` in global class list
- [godot#66381](https://github.com/godotengine/godot/issues/66381) — `@tool` sometimes needs editor restart
- [godot#90142](https://github.com/godotengine/godot/issues/90142) / [godot#104503](https://github.com/godotengine/godot/issues/104503) — Dictionary serialization key order
- [GDScript typed collections](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — nested typed arrays/dicts unsupported
- [godot#89961](https://github.com/godotengine/godot/issues/89961) / [godot#86641](https://github.com/godotengine/godot/issues/86641) — Resource cycles forbidden; save writes null
- [PR #89324](https://github.com/godotengine/godot/pull/89324) / [godot#110205](https://github.com/godotengine/godot/issues/110205) — Variant export type picker
- [Array.find type-strict search](https://docs.godotengine.org/en/stable/classes/class_array.html) vs [int == float](https://docs.godotengine.org/en/stable/classes/class_int.html)
- [UID changes coming to Godot 4.4](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)
- [godot#114349](https://github.com/godotengine/godot/issues/114349) — `add_custom_type` without `class_name` (4.6+)
- [godot#74712](https://github.com/godotengine/godot/issues/74712) — inner-class typed arrays become `Array[Object]`
- [PR #68747](https://github.com/godotengine/godot/pull/68747) — String/StringName unification caveats

### Prior art

- [rvbatt/rule-based-godot](https://github.com/rvbatt/rule-based-godot) README / API (RuleBasedSystem, arbiter, NodePath matches)
- [FlowKit](https://godotassetlibrary.com/asset/KS49Hf/flowkit:-godot-visual-scripting) event-sheet model
- [LimboAI](https://godotengine.org/asset-library/asset/KYd7wV/limboai-behavior-trees-state-machines-godot-46) blackboard / debugger
- [Orchestrator compatibility table](https://github.com/CraterCrash/godot-orchestrator) (4.7.x → 2.5.x)
- [GUT 9.7.1 / godot_4_7](https://github.com/bitwes/Gut)
- [GdUnit4 6.2.x supports 4.7 / 4.7.1](https://github.com/godot-gdunit-labs/gdUnit4)

### Execution-model background (secondary)

- Production-system recognize–act / Drools agenda: used only as analogy; this addon should remain event-indexed ECA, not RETE.
- [McCarthy & Dayal, SIGMOD 1989 (HiPAC)](https://dl.acm.org/doi/pdf/10.1145/66926.66946) — coupling modes; sibling rules; nested transactions
- Independent deep-research pass (2026-08-31, status **Partial**): confirmed 4.7 main-screen / plugin.cfg / autoload / Inspector / undo / `get_global_class_list` / headless `--script`; flagged that two-phase+FIFO is not required classic ECA; remaining gaps: cyclic Resource load/save not in 4.7 class docs, Variant Inspector UX not fully documented, inheritance walk for `get_global_class_list().base` not specified. Those gaps are covered in this review via engine issues and GDScript docs, not via that pass.
