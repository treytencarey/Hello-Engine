---
depends_on: [projectile]
conflicts_with: []
exposes: [abilities/projectile]
---

# abilities/projectile

A projectile fired by an ability. It is launched from a point, 1 m along a look (yaw and pitch, the shooter's camera), at a speed, and becomes a `projectile` on the same entity, which then flies and ends on its own. An ability spawns it (`abilities/grenade`, `abilities/fireball`).

## Components

- `abilities/projectile = { at, yaw, pitch, speed, radius, gravity, lifetime, color }`: put on a new entity when the ability fires. Missing fields get defaults:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `at` | `{ x, y, z }`, the point the look starts from | `{ 0, 0, 0 }` |
  | `yaw`, `pitch` | radians, the look: `from_rotation_y(yaw) × from_rotation_x(pitch)` applied to −Z | 0 |
  | `speed` | metres per second along the look | 20 |
  | `radius`, `gravity`, `lifetime`, `color` | passed to `projectile` | `projectile`'s |

  It never crosses the network; the `projectile` it adds does.
- It adds `projectile = { from, velocity, … }` to its entity. If `abilities/projectile` is removed from an entity that stays, it removes that `projectile`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `abilities/projectile/init` | On an added `abilities/projectile`, fill in its missing `at`, `yaw`, `pitch` and `speed` |
| First | `abilities/projectile/launch` | On an added `abilities/projectile`, add the `projectile`: 1 m along the look from `at`, at `speed` |
| First | `abilities/projectile/removed` | When `abilities/projectile` is removed from an entity that stays, remove the `projectile` |

## Use

```lua
-- on the server, in the ability's fire system
commands:spawn({
    ["abilities/projectile"] = { at = above_player, yaw = camera.yaw, pitch = camera.pitch, speed = 20 },
})
```

## Notes

- The look is the same rotation `camera/3d` gives its eye, so it flies where the player is looking.
- It is a root, not the caster's child: a child body is dragged along by a moving parent (measured; Rapier treats the parent-moved pose as an edit). An ability links it to its caster with `projectile/caster` (`abilities/fireball`).
