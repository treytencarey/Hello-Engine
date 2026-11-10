---
depends_on: [core/player/attest, core/net, camera/third_person, movement, animation, abilities/fireball, abilities/grenade, ai/perception, ai/noisemaker, input, sidebar, sidebar/profiler, sidebar/profile, sidebar/invites, sidebar/file_browser, git/panel, git/collaborators, player/vr]
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
  | `user_id` | who the player is, from its join ticket: the `user` of `core/player/attest` on the server's `core/net/connection` with this `client_id`, while it is `attested`; `""` otherwise | `""` |
  | `smoothing` | how fast the server's Transform follows the owner's, per second | 15 |

- What each player gets, by side. Names are written in the code:
  - server: `camera/third_person`, `movement`, `animation` (the default model), `abilities/fireball` (a fireball on Q), `abilities/grenade` (a grenade on G), `ai/perception/target` (for agents to look for), `ai/noisemaker` (for them to hear), `sidebar/file_browser` (the file browser panel, synced to its owner: a panel with server work is the server's to add), `git/panel` (the GitHub panel, synced to its owner, for the same reason: its server half answers the owner's asks and opens the portals they ask for) and `player/vr` (the VR stack, which does nothing until a headset is tracking);
  - the owning client: `input`, `input/mode = { mode = "input/game" }`, `sidebar`, `sidebar/profiler`, `sidebar/profile` (the sign-in panel), `sidebar/invites` (the invite cards, which need no open panel), `git/collaborators` (the collaborators panel), and its `RigidBody3d` switched to `Dynamic`. Each is local UI with no server half, so the client adds it.

  If `player` is removed from an entity that stays, each half removes what it added.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (server) | `player/init` | On an added `player` that is neither a `WorldMirror` nor a peer mirror (`core/net/peer/mirror`), add the camera, movement, the model, the abilities, what agents look for and hear, the file browser and GitHub panels and the VR stack |
| First (server) | `player/init` | On an added `player` that is a peer mirror (not a `WorldMirror`): add only `abilities/fireball` and `abilities/grenade`, so the player's cast shows here too (below) |
| Update (server) | `player/identity` | On a changed `core/player/attest` on a connection, and on an added `player`: set `player.user_id` from the connection with its `client_id`. Who the client is lives on the connection, so a player spawned again for it is who it was |
| Update (server) | `player/follow` | Polls: ease the server's Transform toward the owner's (`core/net/sync/Transform`). Not a peer mirror: a player handed to another world stays here as that world's mirror, moved by its peer, and its shadow is stale |
| First (server) | `player/removed` | When `player` is removed from an entity that stays, remove the camera, movement, the model, the abilities, what agents look for and hear, the file browser and GitHub panels and the VR stack |
| First (client) | `player/local` | When the player is this client's (`core/net/local`, which arrives frames after the player), start game input, the sidebar with its profiler, sign-in and collaborators panels and the invite cards, and make its body dynamic |
| First (client) | `player/local` | When `core/net/local` leaves a player that stays (another world's server took it through a portal), make its body `KinematicPositionBased` again with zero velocity: it is moved by what this world's server sends |
| First (client) | `player/removed` | When `player` is removed from an entity that stays, remove input, the sidebar, its profiler, sign-in and collaborators panels and the invite cards |

## Use

A world does not add `player` itself: `player/spawner` spawns one for each client that joins, with its body, collider and sync, and this mod sets it up.

```lua
-- in a world's boot, on the server
commands:spawn({ ["player/spawner"] = {}, ChildOf = boot:id() })
```

## Notes

- Mirrored players from another world (`WorldMirror`, or a peer mirror, `core/net/peer/mirror`) are not set up here, except that a peer mirror gets the abilities: its press arrives from its source's server with the mirror (the press's sync crosses the peer link), and the ability casts here from the mirror's own place and look (`Transform` and `camera`, which cross too) as this world's own projectile, which flies and explodes on this world's geometry. Nothing cast crosses: the source world casts its own, a few milliseconds apart, and a mirror sends nothing back. Each world runs its own cooldown.
- The body only changes type on the client: it arrives from the server together with its collider, and a body added after its collider never attaches. The server's body is kinematic throughout, and core's peer switch zeroes its velocity when it hands the player over.
- Crossing between worlds through a portal: `player/spawner` gives every player its `core/net/peer/share`, and places a handed player where it stood, with the timers that crossed with it; `scope/portal` hands it over and sends its 3 s crossing timer (`scope/portal/cooling`) along.
- Not done yet: the streaming panels and the account providers, whose mods are not in this library yet.
- Suites: a server one and a client one (windowed: input and the sidebar act on a window); `test_player_handover.lua` and `test_player_handover_client.lua` for crossing, headless.
