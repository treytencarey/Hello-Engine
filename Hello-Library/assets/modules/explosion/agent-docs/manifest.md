---
depends_on: [cooldown]
conflicts_with: []
exposes: [explosion, explosion/burning]
---

# explosion

A glowing ball at a point that grows to its radius and is gone after its duration. It is local: each side spawns its own from what it saw (`projectile/explode` reacts on every side), places it, runs its timer and despawns it when it ends. It is never synced. Spawned by what explodes (`projectile/explode`). It does no damage: a damage mod would react to it.

## Components

- `explosion = { at, radius, duration, color }`: put on a new entity. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `at` | `{ x, y, z }`, where it is | `{ 0, 0, 0 }` |
  | `radius` | metres it grows to | 1.5 |
  | `duration` | seconds it lasts | 0.4 |
  | `color` | `{ r, g, b }`, its color and glow | `{ 1, 0.5, 0.1 }` |

  Never synced (`["core/net/sync"] = false`).
- `explosion/burning`: present on every side while it lasts, as a `cooldown` timer. Added and removed through `cooldown`.
- On both sides it sets `Transform` to `at` and adds a `cooldown` entry; on a client also `Mesh3d` and `MeshMaterial3d<StandardMaterial>`, and it scales the `Transform` as it grows. If `explosion` is removed from an entity that stays, it stops the timer and a client removes the mesh and material.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First (both) | ExplosionInit | On an added `explosion`, fill in missing fields |
| First (both), after `ExplosionInit` | ExplosionPlace | Place it at `at` and start its timer |
| First (both) | ExplosionRemoved | When `explosion` is removed from an entity that stays, stop the timer |
| First (both) | ExplosionEnded | When the timer ends, despawn it |
| First (client), after `ExplosionPlace` | ExplosionDraw | Add a glowing unit sphere of its color, scaled to nothing |
| Update (client) | ExplosionGrow | While it burns, scale it from nothing to its radius |
| First (client) | ExplosionUndraw | When `explosion` is removed from an entity that stays, remove the mesh and material |

## Use

```lua
-- on each side, from what that side saw
spawn({ explosion = { at = { x = 0, y = 1, z = 0 }, radius = 2 }, ["core/script/owner"] = false })
```

## Notes

- Timed work polls: `ExplosionGrow` runs every frame, but only over explosions still burning.
- A mod that spawns one from an entity about to despawn (a projectile) spawns it with `["core/script/owner"] = false`, or it is reaped when that mod's last carrier goes.
