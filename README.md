# Godot Rule Engine

A planned Godot 4.7 addon for deterministic, data-driven gameplay rules using
an Event–Condition–Action model:

```text
event + facts + conditions -> actions
```

The engine is designed for gameplay rules such as unlocks, progression,
economy decisions, and event reactions. Rules are authored as Godot Resources,
evaluated independently of the scene tree, and executed in deterministic order.

## Status

The project is currently implementation-ready but not yet implemented. The V1
scope, runtime behavior, interfaces, tests, and delivery tasks have been
specified and reviewed.

Read the planning documents in this order:

1. [V1 scope](plan/v1-scope.md) — product boundary, architecture, and acceptance criteria.
2. [Runtime semantics](plan/runtime-semantics.md) — frozen behavioral contract.
3. [Implementation plan](plan/implementation-plan.md) — ordered, test-first delivery plan.
4. [Research review](research/godot-rule-engine-plan-review.md) — sourced Godot API and architecture review.

The [plan index](plan/README.md) summarizes the decisions and records the
planning verification evidence.

## V1 direction

- Godot 4.7.1+ within the Godot 4.7 release line.
- GDScript and `.tres` Resources.
- Event-indexed reactive rules and manually queried rules.
- Pure, composable conditions and ordered actions.
- Match-all-before-actions evaluation with a non-recursive FIFO event queue.
- Per-engine runtime state; authored Resources remain immutable at runtime.
- Native Inspector authoring, validation, extension discovery, and headless CI.
- Optional `Rules` autoload over an independently usable `RERuleEngine`.
- Asset Store-safe packaging with strict runtime/editor separation.

## Not V1

V1 will not include a graph editor, dedicated Rules workspace, runtime
debugger, dry-run UI, RETE/forward chaining, save-game integration, arbitrary
Node-path mutation, multiplayer replication, or C# extension discovery.

## Intended package

Consumers will install the self-contained directory:

```text
addons/rule_engine/
```

The addon will remain usable without custom editor UI and without modifying
Godot itself.

## Development

Use Godot 4.7.1 or a later 4.7 patch release. GUT 9.7.1 is vendored under
`addons/gut/` from tag `v9.7.1` (commit
`aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605`). Run the headless suite with:

```powershell
godot --headless --path . --script addons/gut/gut_cmdln.gd -- '-gdir=res://tests' -gexit
```

Generated `.godot/` data and local tool binaries under `.tools/` are ignored.

<!-- verification-evidence:start -->
## Verification evidence

- **Checked:** `2026-09-01T12:15:53+02:00`
- **Claimed outcome:** The repository has a project-level README and no longer contains the superseded architectural-plan file or its plan-index link.
- **Overall result:** `verified`

| Claim | Evidence | Result |
| --- | --- | --- |
| Project README exists | Fresh filesystem check found a non-empty root `README.md` describing purpose, status, scope, and document navigation. | pass |
| Superseded plan was removed | Fresh literal-path check confirmed `Godot Rule Engine Addon — Architectural Plan.md` is absent. | pass |
| README navigation is valid | Every relative Markdown link in the root and plan-index READMEs resolved to an existing local file. | pass |
| Change is whitespace-clean | `git diff --check` exited successfully. | pass |

- **Coverage gaps:** None for this documentation change.
- **Next route:** Begin implementation from `plan/implementation-plan.md` when requested.
<!-- verification-evidence:end -->
