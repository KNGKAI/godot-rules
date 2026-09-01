# Rule Engine Runtime Semantics

This document freezes behavior for V1. Implementations and tests must conform
to it; ambiguous behavior must be resolved here before code changes.

## 1. Values and names

- Rule IDs, event names, lookup keys, and blackboard keys are `StringName`.
- At the public boundary, payload keys that are `String` are copied to
  `StringName`; other key types make the event invalid.
- Payloads are deep-duplicated when enqueued. Dictionaries and arrays in the
  copy are recursively made read-only before condition or action access.
- Numeric comparison treats equal-valued `int` and `float` operands as equal.
- `String` and `StringName` compare by text value.
- Ordered operators accept only numbers or two values of the same ordered
  scalar type. Invalid pairs fail the condition and produce a debug warning.

## 2. Lookup sources

Conditions read exactly one of three namespaces:

- `FACT`: game state exposed by `REFactProvider`.
- `PAYLOAD`: the current event payload, or the payload passed to `check()`.
- `BLACKBOARD`: engine-owned mutable rule state.

The blackboard is not a fact provider. Source is explicit on compare/exists so
identical names in different namespaces cannot shadow each other.

For one event match phase the engine creates one shared view:

- payload: immutable enqueue snapshot;
- blackboard: immutable snapshot taken when the event is dequeued;
- facts: a shared memoizing view over the configured provider, caching both
  presence and value on first lookup of each key.

Conditions must be pure. They receive `REMatchContext`, which has no engine or
mutation API. Custom conditions that mutate returned collection values violate
the extension contract.

## 3. Missing values

- `REExistsCondition` matches exactly when its source contains its key.
- `RECompareCondition` with a missing key does not match.
- Negating an invalid/missing comparison does not turn it into a match.
- Conditions return `REConditionResult(matched, valid)`. `RENotCondition`
  negates `matched` only when `valid` is true; invalid remains non-matching.
  Validity reports unusable input and is not a third truth value: the engine
  fires only when both fields are true.
- Authors who mean “missing” use `NOT Exists(key)`; authors who require a value
  use `Exists(key) AND Compare(key, ...)`.

## 4. Rule registration

- IDs must be non-empty and unique across all loaded books.
- `load_book()` validates the entire incoming book before modifying indexes.
- A duplicate ID from another loaded book rejects the whole book with
  `ERR_ALREADY_EXISTS`; no rules from that book become visible.
- Loading the identical book Resource instance again is idempotent (`OK`).
- Duplicate references to one rule within a book are validation errors.
- `unload_book()` removes only registrations owned by that book and clears
  runtime enabled overrides for rules no longer registered. Blackboard values
  are unaffected.
- A reactive rule has a non-empty event and is placed in the event index.
- A queryable rule has an empty event and is never placed in the event index.

## 5. Enabled state

`RERule.enabled` is the authored default. The effective value is the engine's
runtime override when present, otherwise the authored value. Overrides never
write the Resource and never leak between engine instances.

Disabled rules are returned by `get_rule()` but are skipped by reactive
dispatch and `check()`.

## 6. Query evaluation

`check(rule_id, payload)`:

1. Returns `false` for an unknown, disabled, or reactive rule.
2. Normalizes and snapshots payload as for an event.
3. Creates a match view and evaluates the queryable rule once.
4. Returns the condition result.

It never executes actions, queues events, or emits action/firing signals.

## 7. Event dispatch

`emit_event(name, payload)` rejects an empty name. A valid event is appended to
the engine's FIFO queue. If no drain is active, the caller drains synchronously.
If a drain is active—including a call made by game code from an action—the new
event only appends and the current event finishes first.

For each dequeued event:

1. Before dequeuing, stop the entire drain if the dispatch event counter equals
   `max_events_per_dispatch`.
2. Dequeue the next event and increment the dispatch event counter.
3. Emit `event_received`.
4. Copy the indexed candidates and sort by `priority DESC, id ASC`.
5. Create the event's shared match view.
6. Evaluate every effectively enabled candidate and record passers.
7. Emit `rule_evaluated` for each candidate that was evaluated.
8. Execute recorded rules in the same order.
9. Execute each rule's non-null actions in array order.
10. Emit `action_executed` after each successful action and `rule_fired` after
    the rule's final action.
11. Continue with the next queued event.

There is no rematch between actions. There is no halt, exclusivity, or
stop-propagation in V1: every recorded rule fires.

Actions receive `REActionContext`. It exposes the immutable event payload, the
live engine blackboard, and `emit_event()`. Actions do not receive a mutable
fact provider. Thus later actions can observe earlier blackboard writes, while
conditions for the same event retain the pre-action snapshot.

## 8. Runaway behavior

`max_events_per_dispatch` counts dequeued events in one outermost drain. Its
default is 1,000 and it must be greater than zero. The limit check happens
before dequeue and increment, so `processed_count` never exceeds the limit and
always equals the number of events actually processed.

When the next event would exceed the limit, the engine:

1. clears every event still queued;
2. ends the drain and resets its internal draining flag in guaranteed cleanup;
3. emits `dispatch_failed(&"event_limit", processed_count)`;
4. reports an error containing the last processed event name.

Actions already completed remain completed; V1 provides no transaction or
rollback. A later independent `emit_event()` starts a fresh counter and works.

## 9. Runtime errors

- A null condition makes a rule invalid at load time.
- Null composite children and null actions are validation/load errors.
- An action returning a non-`OK` Godot `Error` stops the remaining actions of
  that rule, emits
  `dispatch_failed(&"action_failed", processed_count)`, clears the queue, and
  ends the drain. Completed effects are not rolled back.
- Signals are observations only. Listeners must not alter engine semantics;
  events emitted by listeners follow the same queue rule.

## 10. Once behavior

V1 has no `once`, cooldown, or `max_fires` field. Authors implement once-only
behavior with a blackboard guard and final write:

```text
condition: NOT Exists(BLACKBOARD, "intro_seen")
actions:
  1. EmitEvent("show_intro")
  2. SetBlackboard("intro_seen", true)
```

This state is per engine and is not persisted by the addon.
