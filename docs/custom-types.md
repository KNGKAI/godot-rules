# Custom conditions and actions

Custom types are project-owned GDScript Resources. Add `@tool` so Godot can
instantiate them in the Inspector, declare a global `class_name`, and ensure
every constructor argument has a default value.

## Condition

```gdscript
@tool
class_name HasInventorySpace
extends RECondition

@export var required_slots: int = 1

func evaluate(context: REMatchContext) -> REConditionResult:
	var lookup := context.lookup(REMatchContext.Source.FACT, &"inventory.free_slots")
	if not lookup.present or typeof(lookup.value) != TYPE_INT:
		return REConditionResult.new(false, false)
	return REConditionResult.new(lookup.value >= required_slots, true)
```

Conditions should only read the match context and return a result. Keep them
free of mutations so all same-event candidates share deterministic pre-action
semantics.

## Action

```gdscript
@tool
class_name SpendCurrencyAction
extends REAction

@export var amount: int = 0

func execute(context: REActionContext) -> Error:
	if amount < 0:
		return ERR_INVALID_PARAMETER
	context.emit_event(&"currency_spend_requested", {&"amount": amount})
	return OK
```

Prefer emitting a domain event for game systems to consume. This keeps addon
rules independent of scene paths and avoids baking game-specific managers into
the reusable addon. Return a non-`OK` error when execution cannot continue; the
engine clears the pending queue and emits `dispatch_failed`.

## Discovery troubleshooting

The plugin follows transitive GDScript inheritance, so an indirect subclass is
valid. It warns about candidates that omit `@tool`. Godot's global script-class
cache can lag after a tool script or `class_name` change; save all scripts and
reopen the project if the new type does not appear. Constructors that require
arguments cannot be created by the Inspector, so use defaults and validate the
configured Resource during rule-book validation.
