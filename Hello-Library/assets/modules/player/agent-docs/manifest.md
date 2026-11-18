---
depends_on: [core/player/attest, core/net, camera/third_person, movement, facing, animation, abilities/fireball, abilities/grenade, ai/perception, ai/noisemaker, input, sidebar, sidebar/profiler, sidebar/profile, sidebar/invites, sidebar/menu, sidebar/file_browser, git/panel, git/collaborators, player/respawn, player/vr, scope/portal/console, pointer/view]
conflicts_with: []
exposes: [player]
---

# player

A player: what every player has, who it is, and how its Transform moves. `player/spawner` spawns players on a world's server; this mod sets each one up on both sides.

The owning client drives its player's Transform, as there is no client prediction yet: the server's body is kinematic, the owner's turns dynamic, and the server eases its Transform toward what the owner sends.

## Components

- `player = { client_id, spawn_point, user_id, smoothing }`, synced from the server:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `client_id` | the owning client | set by the spawner |
  | `spawn_point` | the `Name` of the `player/spawner/point` it claims, a player handed over from another world included; absent while no point is ready | set by the spawner |
  | `user_id` | who the player is, from its join ticket: the `user` of `core/player/attest` on the server's `core/net/connection` with this `client_id`, while it is `attested`; `""` otherwise | `""` |
  | `smoothing` | how fast the server's Transform follows the owner's, per second | 15 |

- What each player gets, by side. Names are written in the code:
  - server: `camera/third_person`, `movement`, `facing/velocity` (it faces where it walks), `animation` (no model unless the world sets `animation.model`, for example through carrier defaults), `abilities/fireball` (a fireball on Q), `abilities/grenade` (a grenade on G), `ai/perception/target` (for agents to look for), `ai/noisemaker` (for them to hear), `sidebar/file_browser` (the file browser panel, synced to its owner: a panel with server work is the server's to add), `git/panel` (the GitHub panel, synced to its owner, for the same reason: its server half answers the owner's asks and opens the portals they ask for) `player/vr` (the VR stack, which does nothing until a headset is tracking) and `scope/portal/console/user` (so a portal-room console's request and response reach this player's owner alone; it does nothing in a world with no console);
  - the owning client: `input`, `input/mode = { mode = "input/game" }`, `sidebar`, `sidebar/profiler`, `sidebar/profile` (the sign-in panel), `sidebar/invites` (the invite cards, which need no open panel), `sidebar/menu` (the menu, which holds other mods' items), `git/collaborators` (the collaborators panel), `player/respawn` (Respawn, an item in the menu), `pointer/view` (the desktop's ray source for `pointer`, unless `vr/pointer` is there; `player/vr` swaps them), its `RigidBody3d` switched to `Dynamic` once this client's copy of the map is ready under it, and its `GravityScale3d` at 1. Each is local UI with no server half, so the client adds it.

  If `player` is removed from an entity that stays, each half removes what it added.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (server) | `player/init` | On an added `player` that is neither a `WorldMirror` nor a peer mirror (`core/net/peer/mirror`), add the camera, movement, its facing, the model, the abilities, what agents look for and hear, the file browser and GitHub panels, the VR stack and the console carrier |
| First (server) | `player/init` | On an added `player` that is a peer mirror (not a `WorldMirror`): add only `abilities/fireball` and `abilities/grenade`, so the player's cast shows here too (below) |
| Update (server) | `player/identity` | On a changed `core/player/attest` on a connection, and on an added `player`: set `player.user_id` from the connection with its `client_id`. Who the client is lives on the connection, so a player spawned again for it is who it was |
| Update (server) | `player/follow` | Polls: ease the server's Transform toward the owner's (`core/net/sync/Transform`). Not a peer mirror: a player handed to another world stays here as that world's mirror, moved by its peer, and its shadow is stale |
| First (server) | `player/removed` | When `player` is removed from an entity that stays, remove the camera, movement, its facing (either variant), the model, the abilities, what agents look for and hear, the file browser and GitHub panels, the VR stack and the console carrier |
| First (client) | `player/local` | When the player is this client's (in one of its own nets' `core/net/owns`, on the owner's `added` or `changed` edge, which can come after the player), start game input, the sidebar with its profiler, sign-in and collaborators panels, the invite cards, and the menu with Respawn in it |
| First (client) | `player/local` | On a changed or removed `collider/status`: hold this client's own player kinematic while the scene holding its claimed point is not ready (a re-export rebuilding its colliders) |
| Update (client), after `collider/status` | `player/local` | Make this client's own player's body dynamic once it may fall: at once with no claim, else once its claimed point is ready here. On it becoming this client's, a changed status, a new point, a changed claim, and again whenever its `RigidBody3d` changes: core's server sends a new owner its values a second time when the player spawns, and that copy of the server's kinematic body can land after the switch; once, a player who walked in through a portal stood frozen. Beside it, give the body a `GravityScale3d` of 1 if it has none. After `collider/status`; a mod that puts a held player back on its point runs between the two, and finds it still held |
| First (client) | `player/local` | When `GravityScale3d` is taken off this client's own player, while it is still a player and this client's, put 1 back |
| First (client) | `player/local` | When a player that stays stops being this client's (its `core/net/owner` taken off, which was one of this client's nets, or given to another connection: another world's server took it through a portal), make its body `KinematicPositionBased` again with zero velocity: it is moved by what this world's server sends |
| First (client) | `player/removed` | When `player` is removed from an entity that stays, remove input, the sidebar, its profiler, sign-in and collaborators panels, the invite cards, the menu and respawn, and the gravity scale |

## Use

A world does not add `player` itself: `player/spawner` spawns one for each client that joins, on a spawn point the world's map carries, with its body, collider and sync, and this mod sets it up.

```lua
-- in a world's boot, on the server
commands:spawn({ ["player/spawner"] = {}, ChildOf = boot:id() })
```

## Notes

- Mirrored players from another world (`WorldMirror`, or a peer mirror, `core/net/peer/mirror`) are not set up here, except that a peer mirror gets the abilities: its press arrives from its source's server with the mirror (the press's sync crosses the peer link), and the ability casts here from the mirror's own place and look (`Transform` and `camera`, which cross too) as this world's own projectile, which flies and explodes on this world's geometry. Nothing cast crosses: the source world casts its own, a few milliseconds apart, and a mirror sends nothing back. Each world runs its own cooldown.
- Rapier applies `GravityScale3d` only when it changes and ignores its removal, so a body whose scale is taken off keeps the last one it had. Whatever takes the local body's scale off, this mod puts 1 back. Taken off with `player`, the scale stays 1 in Rapier, its default.
- **Ready:** as the spawner decides on the server (`player/spawner`), a point is ready when the nearest `SceneRoot` above it has `collider/status.state == "done"`, or at once when no scene holds it. The client waits again because its own copy of the map can land seconds after the player, and a body freed first falls through it. A claim naming a point this client has not loaded yet holds the body until the point arrives ready.
- The body only changes type on the client: it arrives from the server together with its collider, and a body added after its collider never attaches. The server's body is kinematic throughout, and core's peer switch zeroes its velocity when it hands the player over.
- Crossing between worlds through a portal: `player/spawner` gives every player its `core/net/peer/share`, and places a handed player where it stood, with the timers that crossed with it; `scope/portal` hands it over and sends its 3 s crossing timer (`scope/portal/cooling`) along.
- Not done yet: the streaming panels and the account providers, whose mods are not in this library yet.
- Suites: a server one and a client one (windowed: input and the sidebar act on a window); `test_player_handover.lua` and `test_player_handover_client.lua` for crossing, headless; `test_player_hold.lua`, headless, for the hold on a scene whose `collider/status` the suite writes.
