---
depends_on: [core/player/attest, camera/2d, movement/2d, animation/sprite, input, sidebar]
conflicts_with: [player]
exposes: [player/2d]
---

# player/2d

A top-down 2D player: what every 2D player has, who it is, and how its Transform moves. `player/2d/spawner` spawns them on a world's server; this mod sets each one up on both sides. It is a mod of its own: `player` means the 3D stack, and an entity carries one or the other.

The owning client drives its player's Transform, as there is no client prediction yet: the server's body is kinematic, the owner's turns dynamic (`movement/2d`), and the server eases its Transform toward what the owner sends.

## Components

- `player/2d = { client_id, spawn_index, user_id, smoothing }`, synced from the server:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `client_id` | the owning client | set by the spawner |
  | `spawn_index` | its spawn point, 0 for the centre | set by the spawner |
  | `user_id` | who the player is, from its join ticket; `""` until known | `""` |
  | `smoothing` | how fast the server's Transform follows the owner's, per second | 15 |

- What each player gets, by side:
  - server: `core/player/attest` (identity), `camera/2d`, `movement/2d` and `animation/sprite`;
  - the owning client: `input`, `input/mode = { mode = "input/game" }` and `sidebar`.

  If `player/2d` is removed from an entity that stays, each half removes what it added.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (server) | `player/2d/init` | On an added `player/2d`, add identity, the camera, movement and the sprite |
| Update (server) | `player/2d/identity` | When the join ticket is verified, set `player/2d.user_id` |
| Update (server) | `player/2d/follow` | Polls: ease the server's Transform toward the owner's (`core/net/sync/Transform`), its translation only |
| First (server) | `player/2d/removed` | When `player/2d` is removed from an entity that stays, remove identity, the camera, movement and the sprite |
| First (client) | `player/2d/local` | When the player is this client's (`core/net/local`, which arrives frames after the player), start game input and the sidebar |
| First (client) | `player/2d/removed` | When `player/2d` is removed from an entity that stays, remove input and the sidebar |

## Use

A world does not add `player/2d` itself: `player/2d/spawner` spawns one for each client that joins, with its body, collider and sync, and this mod sets it up.

```lua
-- in a world's boot, on the server
commands:spawn({ ["player/2d/spawner"] = {}, ChildOf = boot:id() })
```

## Notes

- Mirrored players from another world (`WorldMirror`) are not set up here.
- Not done yet: crossing between worlds, which waits for a planned rewrite of `core/net`.
- A 2D player has no abilities, as they are 3D today, and not the 3D player's panels (`sidebar/profiler`, `sidebar/file_browser`).
- Suites: `tests/test_player_2d_net.lua` over a real connection, and `player/2d/spawner`'s for the server half. Both run headless.
