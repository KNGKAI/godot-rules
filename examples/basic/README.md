# Basic progression example

This scene demonstrates the intended boundary between game code and rules:

1. `main.gd` translates its `mission_completed` signal into a rule event.
2. The rule matches payload `mission_id == first_steps` and fact
   `player.reputation >= 10`.
3. A NOT-EXISTS blackboard condition prevents a second firing.
4. Actions mark the business as unlocked and emit
   `business_unlock_requested`.
5. The game-owned `BusinessManager` translates that event back into a signal.

No rule action looks up or mutates a scene path.

From the repository root:

```powershell
godot --path .
```

For a bounded headless run:

```powershell
godot --headless --path . --quit-after 3
```
