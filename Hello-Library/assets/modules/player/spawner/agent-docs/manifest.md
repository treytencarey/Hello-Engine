---
depends_on: [player]
conflicts_with: []
exposes: [player/spawner]
---

# player/spawner

Players for a world's server: one for each connected client, at a free spawn point, despawned when the client leaves or goes back to only watching. A world's boot puts it on an entity on the server. Runs where its component is (a root `init.lua`); never synced.

## Components

- `player/spawner = { count, radius, height }`: missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `count` | spawn points, on a circle around the origin | 8 |
  | `radius` | metres from the origin | 3 |
  | `height` | metres above the origin | 5 |

- Each player it spawns is a root with `player`, `Transform`, a kinematic capsule body (`RigidBody3d`, `Collider3d`, `LockedAxes3d`, `Velocity3d`), `core/net/owner = { client_id }`, the `core/net/sync/Transform` shadow the owner's Transform arrives in, and `core/net/sync` (Transform from the owning client, unreliable; the body from the server). `["core/script/owner"] = false`: a player is not reaped with this mod, and lives until its client leaves.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `player/spawner/spawn` | On a changed connection, a client that is not only watching and has no player gets one, at the lowest free point (point 0, the centre, when all are taken) |
| PreUpdate | `player/spawner/left` | When a connection goes, or turns to only watching, its client's player is despawned |

## Use

```lua
-- in a world's boot, on the server
commands:spawn({ ["player/spawner"] = { count = 4, radius = 6 }, ChildOf = boot:id() })
```

## Notes

- A point is free when no player holds its index in `player.spawn_index`; a point given in the same run counts as taken.
- A spawner added after clients connected serves them: the mod loads with it, and a mod's first run sees every connection as changed.
- Players outlive their spawner (removing it stops this mod; its players stay until their clients leave).
- The client drives the Transform, as there is no client prediction yet.
- Not done yet: crossing between worlds (portal promotion with `synced_state`, demotion, departure `transfer_data`), which waits for a planned rewrite of `core/net`.
