---
depends_on: [player/2d, camera, animation/sprite]
conflicts_with: []
exposes: [player/2d/spawner]
---

# player/2d/spawner

2D players for a world's server: one for each connected client, at a free spawn point, despawned when the client leaves or goes back to only watching. A world's boot puts it on an entity on the server. Runs where its component is (a root `init.lua`); never synced.

## Components

- `player/2d/spawner = { count, radius, z, sprite }`: missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `count` | spawn points, on a circle around the origin, in the plane | 8 |
  | `radius` | pixels from the origin | 96 |
  | `z` | how far above the origin the players are drawn | 0 |
  | `sprite` | the `animation/sprite` every player starts with | `{}`: no sheet, so no sprite is drawn |

- Each player it spawns is a root with `player/2d`, `camera = { distance = 1 }` (its starting zoom), `animation/sprite`, `Transform`, a kinematic capsule body (`RigidBody2d`, `Collider2d`, `LockedAxes2d`, `GravityScale2d = 0`, `Velocity2d`), `core/net/owner = { client_id }`, the `core/net/sync/Transform` shadow the owner's Transform arrives in, and `core/net/sync` (Transform from the owning client, unreliable; the body from the server). `["core/script/owner"] = false`: a player is not reaped with this mod, and lives until its client leaves.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `player/2d/spawner/spawn` | On a changed connection, a client that is not only watching and has no player gets one, at the lowest free point (point 0, the centre, when all are taken) |
| PreUpdate | `player/2d/spawner/left` | When a connection goes, or turns to only watching, its client's player is despawned |

## Use

```lua
-- in a world's boot, on the server
commands:spawn({
    ["player/2d/spawner"] = { count = 4, radius = 200, sprite = { image = "hero.png", tile_size = { x = 64, y = 64 }, columns = 13 } },
    ChildOf = boot:id(),
})
```

## Notes

- A point is free when no player holds its index in `player/2d.spawn_index`; a point given in the same run counts as taken.
- A spawner added after clients connected serves them: the mod loads with it, and a mod's first run sees every connection as changed.
- Players outlive their spawner (removing it stops this mod; its players stay until their clients leave).
- `camera/2d` syncs as that mod declares; the spawner sets no override. `camera`'s own default distance is 8, a 3D one, so the spawner states the starting zoom.
- There is no default sheet: a world names its own in `sprite`, and a player with none has no sprite.
- Not done yet: crossing between worlds (portal promotion, departure).
