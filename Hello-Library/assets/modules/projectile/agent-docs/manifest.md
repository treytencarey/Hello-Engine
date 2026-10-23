---
depends_on: [cooldown]
conflicts_with: []
exposes: [projectile, projectile/flying, projectile/caster, projectile/casts]
---

# projectile

A ball launched from a point at a velocity, flying under scaled gravity. The server and every client simulate it from the same launch state, its lifetime timer included, so it flies smoothly everywhere and only `projectile` is synced. The server decides when it ends and despawns it. Spawned by whatever fires it (`abilities`).

## Components

- `projectile = { from, velocity, radius, gravity, lifetime, color }`: put on the entity when it is spawned. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `from` | `{ x, y, z }`, where it is launched from | `{ 0, 0, 0 }` |
  | `velocity` | `{ x, y, z }`, metres per second at launch | `{ 0, 0, 0 }` |
  | `radius` | the ball's radius, for its collider and its mesh | 0.2 |
  | `gravity` | gravity scale | 0.3 |
  | `lifetime` | seconds until the server despawns it | 3 |
  | `color` | `{ r, g, b }`, its color and glow | `{ 1, 0.3, 0.1 }` |

  Synced from the server.
- `projectile/flying`: present on every side while the lifetime runs, as a `cooldown` timer started from the synced `lifetime`, so a client has the time left (`cooldown/left`) without waiting for the server. Added and removed through `cooldown`. Only the server despawns the projectile when it ends.
- `projectile/caster = { entity = <the caster> }`: who fired it, put on the projectile by whatever fires it (`abilities/fireball`). A relationship, declared in this mod's return value: `relationships = { ["projectile/caster"] = { target = "projectile/casts" } }`. When the caster despawns, the projectile loses `projectile/caster` and flies on. Synced by whatever spawns it with one, in the spawn itself, so a client has it from the first frame (`abilities/fireball`).
- `projectile/casts = { <projectile>, ... }`: on a caster, kept by the engine: what it has in flight, in the order fired. Added with the first, removed with the last; read only.
- On both sides it sets `Transform` to `from` and adds `RigidBody3d`, `Collider3d`, `GravityScale3d`, `Velocity3d` and a `cooldown` entry; on a client also `Mesh3d` and `MeshMaterial3d<StandardMaterial>`. If `projectile` is removed from an entity that stays, it removes what it added; the `Transform` stays.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `projectile/init` | On an added `projectile`, fill in missing fields |
| First (both), after `projectile/init` | `projectile/launch` | Place it at `from` and add the body with its collider and velocity |
| First (both), after `projectile/init` | `projectile/flying` | Start the lifetime timer |
| First (both) | `projectile/removed` | When `projectile` is removed from an entity that stays, remove the body and stop the timer |
| First (server) | `projectile/landed` | When the lifetime timer ends, despawn the projectile |
| First (client), after `projectile/init` | `projectile/draw` | Add a glowing sphere of its radius and color |
| First (client) | `projectile/undraw` | When `projectile` is removed from an entity that stays, remove the mesh and material |

## Use

```lua
-- on the server
commands:spawn({
    projectile = { from = muzzle, velocity = { x = 0, y = 0, z = -20 }, lifetime = 2 },
})
```

## Notes

- Do not sync its `Transform`: each side simulates it, and a synced `Transform` would snap a client's ball back every update.
- A client's ball can drift from the server's where the two worlds differ when it hits something (another player standing elsewhere on each side); the server's despawn ends it everywhere.
- Prediction (later) spawns the same `projectile` on the shooter's client at once and runs this same code.
- It is not parented to whatever fired it, so it does not move with the shooter.
- Removing `projectile` removes only the `projectile/flying` entry from the entity's `cooldown`, not the `cooldown` component, which other timers on the entity may share.
