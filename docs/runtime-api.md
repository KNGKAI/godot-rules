# Runtime API

## Ownership and state

`RERuleEngine` is a `RefCounted` runtime object. Retain it in a field; local
instances can otherwise be released after setup. Each engine owns its loaded
book index, enabled overrides, queue, fact provider, and `REBlackboard`.
Loading one authored book into two engines does not share runtime state.

The optional `Rules` autoload delegates the same API to one retained engine.

## Registration

```gdscript
func load_book(book: RERuleBook) -> Error
func unload_book(book: RERuleBook) -> void
func get_rule(rule_id: StringName) -> RERule
```

Registration is atomic. Invalid books are rejected without partial changes,
and an ID already owned by another loaded book returns `ERR_ALREADY_EXISTS`.
Loading the same book object again is idempotent.

## Reactive events and queries

```gdscript
func emit_event(name: StringName, payload: Dictionary = {}) -> void
func check(rule_id: StringName, payload: Dictionary = {}) -> bool
```

`emit_event()` selects reactive rules with that event. Candidates are sorted by
priority descending and then ID ascending. All conditions see one pre-action
snapshot; only after matching completes do passing rules execute their ordered
actions. Events emitted by actions or listeners append to a FIFO queue instead
of recursively reentering dispatch.

`check()` evaluates an enabled queryable rule only. It never runs actions,
queues events, or emits `rule_fired`.

Payload keys must be `String` or `StringName`; they are normalized to
`StringName`. Nested dictionaries and arrays are frozen for the match view.

## Facts, comparisons, and missing data

```gdscript
func set_fact_provider(provider: REFactProvider) -> void
```

Implement `REFactProvider.has_fact()` and `get_fact()`, or use
`REDictionaryFactProvider`. Facts are memoized for one match phase.

Compare supports equal, not-equal, greater, greater-equal, less, less-equal,
`CONTAINS`, and `NOT_CONTAINS`. Integers and floats compare numerically;
`String` and `StringName` compare textually. `CONTAINS` uses substring
membership for text, element membership for Arrays and packed arrays, and key
membership for Dictionaries. Ordered comparisons require two numbers or two
textual values. A missing key or incompatible operands produces an invalid
condition result, and NOT/`NOT_CONTAINS` preserve invalidity rather than
turning malformed data into a match.

## Runtime controls

```gdscript
var max_events_per_dispatch: int
var max_chain_depth: int
func set_rule_enabled(rule_id: StringName, enabled: bool) -> Error
func clear_rule_enabled_override(rule_id: StringName) -> void
func get_blackboard() -> REBlackboard
```

Overrides never mutate authored Resources. The event limit defaults to 1000;
when reached, the queue is cleared and `dispatch_failed` is emitted. Blackboard
values are memory-only. Serialize and restore them through game-owned save code
when persistence is required. Built-in writes recursively copy mutable
containers, packed arrays, and Resources so engines do not share runtime state
with one another or with authored action Resources.

`max_chain_depth` defaults to `64` and clamps to at least `1`. An external
`emit_event()` is a root at depth `0`; every event emitted while the engine is
dispatching is queued at the current event depth plus one. If a queued event
would exceed the limit, that dispatch queue is cleared and
`dispatch_failed(&"chain_depth", processed_events)` is emitted. The engine
recovers for a later root event.

A one-time rule can require `NOT EXISTS` for a blackboard key, then set that key
as its first action.

## Signals

```gdscript
signal event_received(event: RERuleEvent)
signal rule_evaluated(rule: RERule, passed: bool)
signal rule_fired(rule: RERule)
signal action_executed(rule: RERule, action: REAction)
signal dispatch_failed(reason: StringName, processed_events: int)
```

These signals provide a deterministic event/rule/action trace and let game code
translate rule events into domain behavior without Node-path actions.
