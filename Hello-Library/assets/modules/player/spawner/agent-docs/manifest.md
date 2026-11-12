---
depends_on: [player, core/net/peer]
conflicts_with: []
exposes: [player/spawner, player/spawner/point, player/spawner/player, player/spawner/players]
---

# player/spawner

Players for a world's server: one for each connected client, on a free, ready spawn point that the world's map carries, despawned when the client leaves or goes back to only watching, and each linked to its spawner. A client waits with no player until a point is ready. A world's boot puts it on an entity on the server. A game whose players need more extends it: its spawner has this mod as its `base`, as a creature's spawner has `ai/spawner` (Use). Runs where its component is (a root `init.lua`); never synced.

## Components

- `player/spawner = { lift }`: missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `lift` | metres above a point, along the point's up, that a player's body is placed | 1 |

- `player/spawner/point = {}`: a spawn point. It is on a map's node, which gives it a `Name` (claims go by name, which a re-export keeps) and its place: its `GlobalTransform`, facing its −Z. A map made in Blender carries it as a custom property named `player/spawner/point` on an empty, which `gltf/mod_registry` turns into this component; a map built in Lua spawns an entity with it, a `Name` and a `Transform` (`map/default` does). Each side has its own copy of the map's points, so it is never synced.
  - **Ready:** a point is ready when the nearest `SceneRoot` above it has `collider/status.state == "done"`, which `collider` writes once `collider/mesh` and `collider/bb` have built the scene's colliders, or at once when no scene holds it. A point in a scene with no collider mod on any node gets no status, and is never ready.
  - **Claims:** every player claims a point, a handed-over one included: the first ready point by name that nobody holds, else the least held, the first by name of a tie. A point claimed earlier in the same run counts as held. A claim counts the player in its point's occupancy, wherever the player stands.
  - **Re-claims:** a player whose claim names no point any more (a re-export renamed or deleted it), or that has none (it arrived when no point was ready), claims the least held ready point the same way, on the spawner's next edge: `player.spawn_point` changes, and the player is not moved. A claim whose point is still there is kept, ready or not, so a re-export that keeps the name keeps the claim.
- Each player it spawns is a root with `player = { client_id, spawn_point }`, `player/spawner/player` (below), `Transform`, a kinematic capsule body (`RigidBody3d`, `Collider3d`, `LockedAxes3d`, `Velocity3d`), `core/net/owner = { client_id }`, `["core/net/peer/share"] = { stable_id = "player_<client_id>" }` (so a world linked to this one by a portal mirrors it, and core's peer switch can hand it over), the `core/net/sync/Transform` shadow the owner's Transform arrives in, and `core/net/sync` (Transform from the owning client, unreliable; the body from the server). `["core/script/owner"] = false`: a player is not reaped with this mod, and lives until its client leaves.
  - A fresh player stands `lift` above its point, with `player.spawn_point` the point's `Name`, and `camera = { yaw }` turned to the point's facing (the body's rotation is locked), with `camera`'s sync (`{ authority = "client", target = "owner" }`) in the spawn.
  - Its place and its camera ride the spawn: from then on the owning client keeps its own Transform and camera, and a later write moves only the server's copy.
- `player/spawner/player = { entity = <its spawner> }`, on each player it spawns: a relationship with target `player/spawner/players` and `linked_spawn = false`. A player's life follows its client's connection, not its spawner: when the spawner despawns, its players stay in the world and lose the link. The link is never synced and never crosses to another world.
- `player/spawner/players`: a spawner's players, in the order they were spawned, kept by the engine.
- A player handed over by another world's server (a portal's handover, `core/net/peer`) arrives as `core/net/connection.synced_state` on the client's connection while it still only watches. When the connection stops only watching, the player is spawned at `synced_state.Transform` (translation and rotation), whatever points this world has, ready or not, and claims the least held ready point as a fresh player would (none while no point is ready); with the shadow seeded there, and with the whole of `synced_state.camera` as its `camera` and `camera`'s sync in the spawn, so the carried camera reaches the owner in the spawn itself and the view stays where it was (height and offset as well as yaw, pitch and distance). The timers that crossed with it, `synced_state.cooldown` (a portal's crossing timer, `scope/portal`), are its `cooldown`, with `cooldown`'s sync (`{ authority = "server", target = "owner" }`) in the spawn, so the owner's client has them from the player's first frame. They are there only when this world accepts `cooldown` from a peer. No other field of `synced_state` is taken: this world's defaults are its own. This mod names no timer.
- A player arrived by handover when its client's connection (the `core/net/connection` with the player's `client_id`) holds `synced_state.Transform` with a `translation`. This mod adds no mark of its own: a subclass reads the connection to tell such a player apart.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| PostUpdate, after `TransformSystems.Propagate` | `player/spawner/spawn` | On a changed connection, a changed `collider/status` or an added point: a player whose claim names no point, or that has none, claims the least held ready point; then each client that is not only watching and has no player gets one, linked to the spawner, with a claim: on a free, ready point, or where it stood in the world that handed it over, with its camera and the timers that crossed with it. A client with no ready point and nothing handed waits for the next of those edges. After the propagation, as a point spawned this frame has its world place only then |
| PreUpdate | `player/spawner/left` | When a connection goes, or turns to only watching, its client's player is despawned |
| PostUpdate, before `core/net/peer/authority_switch` | `player/spawner/left` | On `core/net/peer/switch` added to a player (a portal handing it over), set `core/net/peer/share.transfer_data.camera` to its whole `camera`, keeping the other entries (the portal's timer), which core's switch sends in the same frame |

## Use

```lua
-- in a world's boot, on the server; the world's map carries the points
commands:spawn({ ["player/spawner"] = {}, ChildOf = boot:id() })

-- a point in a map built in Lua: it needs a Name
commands:spawn({ Name = "start", Transform = { translation = at }, ["player/spawner/point"] = {}, ChildOf = map })
```

In Blender, give the spawn empty the custom property `player/spawner/point` with the value `{}`, and export with Custom Properties included. Put the empty on the floor, upright: the body goes `lift` above it.

A game's own spawner is a subclass. Its server half returns `{ base = "player/spawner" }`, and the registry adds `player/spawner` beside it, so this mod places, links, shares and despawns the players. The subclass adds what its players need beyond that on the link's `added` edge, for the players whose `player/spawner/player.entity` carries its own component (`spawners:contains(link.entity)`), as `ai/archetype/wanderer/spawner` does for `ai/spawner`. What it writes into a player's Transform or camera reaches the owning client only in the spawn, so it runs in `PostUpdate`, `:after("player/spawner/spawn")`, in the frame the player is spawned: core sends the spawn in the next `First`.

```lua
-- <game>/spawn/server/init.lua
app:add_systems(PostUpdate, {
    Query[{
        added = { "player/spawner/player" },
        with = { Mut["Transform"] },
    }],
    Query[{ with = { "<game>/spawn" } }],
}, function(arrived, spawners)
    for _, p in ipairs(arrived:iter_mut()) do
        if spawners:contains(p:get("player/spawner/player").entity) then
            p:get_mut("Transform").scale = { x = 0.8, y = 0.8, z = 0.8 }
        end
    end
end):in_set("<game>/spawn/body"):after("player/spawner/spawn")

return { base = "player/spawner" }
```

A game shares its own things through a handover as the camera and the portal's crossing timer do, with no change here. Each mod stamps its own entry, named after its component, into the leaving player's `core/net/peer/share.transfer_data` before core's switch sends it: on `core/net/peer/switch`'s `added` edge, in `PostUpdate` before `core/net/peer/authority_switch` (or in `Update`, as the portal does), through `get_mut` or `entry("core/net/peer/share"):and_modify`, keeping the other entries. The target world's `core/net/peer/accept` decides which entries cross. On arrival there the mod reads its entry back from `synced_state` on the client's connection, on the player's `added` edge. Names stay literal in each mod.

## Notes

- A world whose map carries no point spawns no fresh player, and says so in the log on each edge: `[PLAYER/SPAWNER] <n> client(s) waiting for a ready player/spawner/point`.
- A spawner added after clients connected serves them: the mod loads with it, and its condition's first run sees every connection as changed.
- Players outlive their spawner: removing it stops this mod, and its players stay, unlinked, until their clients leave.
- The registry takes a mod's parts with it when the mod stops, and `player/spawner/point` is one: when the last spawner goes, every map's points lose the component, so a spawner added later finds none until the map's nodes or entities are made again.
- The client drives the Transform, as there is no client prediction yet.
- Crossing: the target world's mirror of the player holds its synced state, which core's switch reads, and the camera rides the switch itself (`transfer_data`, whose entries win), as the mirror may be an unreliable update behind. Each entry crosses only if the target accepts its name (`core/net/peer/accept`). Leaving, the player stays in this world as a mirror of the target's new one (`player` skips setting it up again), and the client turns its body back to kinematic (`player/local`).
- A respawn for a connection that still holds `synced_state` arrives where it stood again, with the timers that crossed.
- Suites, headless: `tests/test_player_spawner.lua` (waiting, readiness, claims, the link, players outliving their spawner); `tests/test_player_spawner_scene.lua` (a scene made in Blender: no player until `collider`'s status is "done", then the player on the scene's point); `tests/test_player_spawner_net.lua` (over a real connection: no player without a point, then the player arrives on it, in the frame it arrives); `player/tests/test_player_handover.lua` (the share; a handed player's place with no point, then its claim once one is ready; a handed player claiming the least held ready point and standing where it was handed; its camera and crossing timer). `player/tests/test_player_server.lua` is windowed.
