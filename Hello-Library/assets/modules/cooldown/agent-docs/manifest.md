---
depends_on: []
conflicts_with: []
exposes: [cooldown, cooldown/left]
---

# cooldown

Named timers on an entity. While a timer runs, the entity carries the component the timer is named after; when it ends or is cancelled, both are removed. Runs on both sides and never syncs: each side runs the timers started on it. A timer a client needs (to show time left, to predict) is started on both sides from synced data, by the using mod's `shared/` half (`projectile`); the server's side decides what the end does.

## Components

- `cooldown = { <component> = { remaining = <seconds> } }`: one entry per timer, written by the mod that wants the timer. `cooldown` removes an entry when its timer ends.
- `cooldown/left = { <component> = <seconds still to run> }`: the time left on each running timer. Added and removed by `cooldown`.
- `<component>`: the component a timer is named after, present while that timer runs. Added and removed by `cooldown`.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First | CooldownStart | On a changed `cooldown`, start each new timer and add its component. A timer already running is not restarted, so writing its entry again while it runs does nothing |
| First | CooldownTick | Count running timers down; at zero, remove the timer's component and entry. A cancelled timer's component is removed |

## Use

```lua
-- start a 3 s timer that keeps `abilities/dash/cooling` on the player while it runs
player:patch({ cooldown = { ["abilities/dash/cooling"] = { remaining = 3 } } })

-- react to it ending
world:query({ removed = { "abilities/dash/cooling" } })

-- cancel it
player:patch({ cooldown = { ["abilities/dash/cooling"] = null } })
```

## Notes

- Two mods that name the same component share one timer. Name timers after a component your mod owns.
- Timed work polls: `CooldownTick` runs every frame, but only over entities with a running timer.
