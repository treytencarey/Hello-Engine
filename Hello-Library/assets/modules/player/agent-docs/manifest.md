---
depends_on: [core/player/attest, camera/third_person, movement, animation, abilities/fireball, abilities/grenade, ai/perception, ai/noisemaker, input, sidebar, sidebar/profiler, sidebar/profile, sidebar/file_browser, player/vr]
conflicts_with: []
exposes: [player]
---

# player

A player: what every player has, who it is, and how its Transform moves. `player/spawner` spawns players on a world's server; this mod sets each one up on both sides.

The owning client drives its player's Transform, as there is no client prediction yet: the server's body is kinematic, the owner's turns dynamic, and the server eases its Transform toward what the owner sends.

## Components

- `player = { client_id, spawn_index, user_id, smoothing }`, synced from the server:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `client_id` | the owning client | set by the spawner |
  | `spawn_index` | its spawn point, 0 for the centre | set by the spawner |
  | `user_id` | who the player is, from its join ticket; `""` until known | `""` |
  | `smoothing` | how fast the server's Transform follows the owner's, per second | 15 |

- What each player gets, by side. Names are written in the code:
  - server: `core/player/attest` (identity), `camera/third_person`, `movement`, `animation` (the default model), `abilities/fireball` (a fireball on Q), `abilities/grenade` (a grenade on G), `ai/perception/target` (for agents to look for), `ai/noisemaker` (for them to hear), `sidebar/file_browser` (the file browser panel, synced to its owner: a panel with server work is the server's to add) and `player/vr` (the VR stack, which does nothing until a headset is tracking);
  - the owning client: `input`, `input/mode = { mode = "input/game" }`, `sidebar`, `sidebar/profiler`, `sidebar/profile` (the sign-in panel), and its `RigidBody3d` switched to `Dynamic`.

  If `player` is removed from an entity that stays, each half removes what it added.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (server) | `player/init` | On an added `player`, add identity, the camera, movement, the abilities, the file browser panel and the VR stack |
| Update (server) | `player/identity` | When the join ticket is verified, set `player.user_id` |
| Update (server) | `player/follow` | Polls: ease the server's Transform toward the owner's (`core/net/sync/Transform`) |
| First (server) | `player/removed` | When `player` is removed from an entity that stays, remove identity, the camera, movement, the abilities, the file browser panel and the VR stack |
| First (client) | `player/local` | When the player is this client's (`core/net/local`, which arrives frames after the player), start game input, the sidebar and its profiler panel, and make its body dynamic |
| First (client) | `player/removed` | When `player` is removed from an entity that stays, remove input, the sidebar and its profiler panel |

## Use

A world does not add `player` itself: `player/spawner` spawns one for each client that joins, with its body, collider and sync, and this mod sets it up.

```lua
-- in a world's boot, on the server
commands:spawn({ ["player/spawner"] = {}, ChildOf = boot:id() })
```

## Notes

- Mirrored players from another world (`WorldMirror`) are not set up here.
- The body only changes type on the client: it arrives from the server together with its collider, and a body added after its collider never attaches.
- Not done yet: the streaming panels and the account providers, whose mods are not in this library yet, and crossing between worlds (promotion, demotion, transfer).
- Suites: a server one (headless) and a client one (windowed: input and the sidebar act on a window).
