---
depends_on: [player, core/net/peer]
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

- Each player it spawns is a root with `player`, `Transform`, a kinematic capsule body (`RigidBody3d`, `Collider3d`, `LockedAxes3d`, `Velocity3d`), `core/net/owner = { client_id }`, `["core/net/peer/share"] = { stable_id = "player_<client_id>" }` (so a world linked to this one by a portal mirrors it, and core's peer switch can hand it over), the `core/net/sync/Transform` shadow the owner's Transform arrives in, and `core/net/sync` (Transform from the owning client, unreliable; the body from the server). `["core/script/owner"] = false`: a player is not reaped with this mod, and lives until its client leaves.
- A player handed over by another world's server (a portal's handover, `core/net/peer`) arrives as `core/net/connection.synced_state` on the client's connection while it still only watches. When the connection stops only watching, the player is spawned at `synced_state.Transform` (translation and rotation), with the shadow seeded there, still claiming the lowest free point; and with `camera = { yaw, pitch, distance }` from `synced_state.camera` and `camera`'s sync (`{ authority = "client", target = "owner" }`) in the spawn, so the carried camera reaches the owner in the spawn itself. It arrives cooling: `cooldown = { ["scope/portal/cooling"] = { remaining = 3 } }`, with `cooldown`'s sync (`{ authority = "server", target = "owner" }`) in the spawn, so for 3 s neither this world's server hands it over nor its client flips it (`scope/portal`), and it does not bounce straight back through a portal standing where it arrives; the owner's client has the timer from the player's first frame. No other field of `synced_state` is taken: this world's defaults are its own. A player spawned with no `synced_state` has no timer.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `player/spawner/spawn` | On a changed connection, a client that is not only watching and has no player gets one, at the lowest free point (point 0, the centre, when all are taken), or where it stood in the world that handed it over, with its camera's yaw, pitch and distance and a 3 s crossing timer |
| PreUpdate | `player/spawner/left` | When a connection goes, or turns to only watching, its client's player is despawned |
| PostUpdate, before `core/net/peer/authority_switch` | `player/spawner/left` | On `core/net/peer/switch` added to a player (a portal handing it over), set `core/net/peer/share.transfer_data = { camera = { yaw, pitch, distance } }` from its `camera`, which core's switch sends in the same frame |

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
- Crossing: the target world's mirror of the player holds its synced state, which core's switch reads, and the camera rides the switch itself (`transfer_data`, whose entries win), as the mirror may be an unreliable update behind. Each entry crosses only if the target accepts its name (`core/net/peer/accept`). Leaving, the player stays in this world as a mirror of the target's new one (`player` skips setting it up again), and the client turns its body back to kinematic (`player/local`).
- The crossing timer's name is `scope/portal`'s, written as data in `cooldown`. A respawn for a connection that still holds `synced_state` arrives where it stood again, and cools again.
- Suites: `player/tests/test_player_handover.lua` (the share, a handed player's place, camera and crossing timer), headless; `player/tests/test_player_server.lua` for the rest.
