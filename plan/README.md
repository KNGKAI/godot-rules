# Godot Rule Engine V1 Plan

This directory is the implementation authority for V1. The original
architectural plan and its research review remain source material; where they
disagree with these files, these files win.

Read in this order:

1. [v1-scope.md](v1-scope.md) — product boundary, architecture, and acceptance criteria.
2. [runtime-semantics.md](runtime-semantics.md) — frozen behavioral contract.
3. [implementation-plan.md](implementation-plan.md) — ordered, test-first delivery plan.

Source material:

- [Sourced plan review](../research/godot-rule-engine-plan-review.md)

## Decision summary

- Target Godot 4.7.1 or newer in the 4.7 series; use GDScript only.
- Build an event-indexed Event–Condition–Action engine, not a general inference engine.
- Keep authored Resources immutable while the engine owns all runtime state.
- Match every candidate before executing any action; nested events join one FIFO queue.
- Ship normal Inspector authoring before any bespoke workspace.
- Use prefixed global class names (`RE*`) to avoid addon and project collisions.
- Keep all consumer files, documentation, and licensing inside `addons/rule_engine/`.

<!-- verification-evidence:start -->
## Verification evidence

- **Checked:** `2026-09-01T12:23:09+02:00`
- **Claimed outcome:** The research review has been converted into a scoped, internally consistent V1 specification, runtime contract, and executable implementation plan.
- **Overall result:** `verified`

| Claim | Evidence | Result |
| --- | --- | --- |
| Required artifacts exist | Fresh filesystem check found four non-empty files under `plan/`. | pass |
| Review blockers are represented | Automated coverage check found all 13 selected decision terms, including version/test pins, missing-result type, duplicate-ID behavior, queue limit, headless exit, editor undo, and runtime override semantics. | pass |
| Plan is implementation-structured | Heading check found exactly seven task sections with files, interfaces, test cycles, commands, and commits. | pass |
| No known stale or vague contract remains | Placeholder and deprecated-interface scans returned no matches. | pass |
| Dispatch count is bounded | The runtime contract checks the limit before dequeue/increment, defines `processed_count` as events actually processed, and requires the cycle test to equal the configured limit. | pass |
| Markdown patch is clean | `git diff --check` exited successfully. | pass |

- **Coverage gaps:** Godot implementation and runtime tests do not exist yet; they are deliverables of this plan, not evidence required for the document rewrite.
- **Next route:** Execute `plan/implementation-plan.md` with the required implementation workflow.
<!-- verification-evidence:end -->
