---
depends_on: [player, core/net/peer]
conflicts_with: []
exposes: [player/spawner, player/spawner/player, player/spawner/players]
---

# player/spawner

Players for a world's server: one for each connected client, at a free spawn point, despawned when the client leaves or goes back to only watching, and each linked to its spawner. A world's boot puts it on an entity on the server. A game that places its players its own way extends it: its spawner has this mod as its `base`, as a creature's spawner has `ai/spawner` (Use). Runs where its component is (a root `init.lua`); never synced.

## Components

- `player/spawner = { count, radius, height }`: missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `count` | spawn points, on a circle around the origin | 8 |
  | `radius` | metres from the origin | 3 |
  | `height` | metres above the origin | 5 |

- Each player it spawns is a root with `player`, `player/spawner/player` (below), `Transform`, a kinematic capsule body (`RigidBody3d`, `Collider3d`, `LockedAxes3d`, `Velocity3d`), `core/net/owner = { client_id }`, `["core/net/peer/share"] = { stable_id = "player_<client_id>" }` (so a world linked to this one by a portal mirrors it, and core's peer switch can hand it over), the `core/net/sync/Transform` shadow the owner's Transform arrives in, and `core/net/sync` (Transform from the owning client, unreliable; the body from the server). `["core/script/owner"] = false`: a player is not reaped with this mod, and lives until its client leaves.
- `player/spawner/player = { entity = <its spawner> }`, on each player it spawns: a relationship with target `player/spawner/players` and `linked_spawn = false`. A player's life follows its client's connection, not its spawner: when the spawner despawns, its players stay in the world and lose the link. The link is never synced and never crosses to another world.
- `player/spawner/players`: a spawner's players, in the order they were spawned, kept by the engine.
- A player handed over by another world's server (a portal's handover, `core/net/peer`) arrives as `core/net/connection.synced_state` on the client's connection while it still only watches. When the connection stops only watching, the player is spawned at `synced_state.Transform` (translation and rotation), with the shadow seeded there, still claiming the lowest free point; and with `camera = { yaw, pitch, distance }` from `synced_state.camera` and `camera`'s sync (`{ authority = "client", target = "owner" }`) in the spawn, so the carried camera reaches the owner in the spawn itself. The timers that crossed with it, `synced_state.cooldown` (a portal's crossing timer, `scope/portal`), are its `cooldown`, with `cooldown`'s sync (`{ authority = "server", target = "owner" }`) in the spawn, so the owner's client has them from the player's first frame. They are there only when this world accepts `cooldown` from a peer. No other field of `synced_state` is taken: this world's defaults are its own. This mod names no timer.
- A player arrived by handover when its client's connection (the `core/net/connection` with the player's `client_id`) holds `synced_state.Transform` with a `translation`. This mod adds no mark of its own: a subclass reads the connection to leave such a player where it stood.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `player/spawner/spawn` | On a changed connection, a client that is not only watching and has no player gets one, linked to the spawner, at the lowest free point (point 0, the centre, when all are taken), or where it stood in the world that handed it over, with its camera's yaw, pitch and distance and the timers that crossed with it |
| PreUpdate | `player/spawner/left` | When a connection goes, or turns to only watching, its client's player is despawned |
| PostUpdate, before `core/net/peer/authority_switch` | `player/spawner/left` | On `core/net/peer/switch` added to a player (a portal handing it over), set `core/net/peer/share.transfer_data.camera = { yaw, pitch, distance }` from its `camera`, keeping the other entries (the portal's timer), which core's switch sends in the same frame |

## Use

```lua
-- in a world's boot, on the server
commands:spawn({ ["player/spawner"] = { count = 4, radius = 6 }, ChildOf = boot:id() })
```

A game's own spawner is a subclass. Its server half returns `{ base = "player/spawner" }`, and the registry adds `player/spawner` beside it, so this mod spawns, links, shares and despawns the players. The subclass decides what a player it is linked to does on arrival, on the link's `added` edge, for the players whose `player/spawner/player.entity` carries its own component (`spawners:contains(link.entity)`), as `ai/archetype/wanderer/spawner` does for `ai/spawner`. Backrooms' `player/spawn` is one: it places each fresh player on a map's spawn point.

```lua
-- <game>/spawn/server/init.lua
app:add_systems(First, {
    Query[{
        added = { "player/spawner/player" },
        with = { Mut["Transform"], Mut["core/net/sync/Transform"] },
    }],
    Query[{ with = { "<game>/spawn" } }],
}, function(arrived, spawners)
    for _, p in ipairs(arrived:iter_mut()) do
        if spawners:contains(p:get("player/spawner/player").entity) then
            p:get_mut("Transform").translation = { x = 0, y = 1, z = 0 }
            p:get_mut("core/net/sync/Transform").translation = { x = 0, y = 1, z = 0 }
        end
    end
end):in_set("<game>/spawn/place"):after("player/spawner/spawn"):before("core/net/sync_track")

return { base = "player/spawner" }
```

- A subclass moves a fresh player in the frame this mod spawns it, `:after("player/spawner/spawn")` and `:before("core/net/sync_track")`, so core's spawn of the player carries the place. The owning client drives its Transform and keeps its own from then on: a later write moves only the server's copy, which the owner's next update replaces. It writes the shadow too, which `player` eases the server's copy toward.
- A player that arrived by handover is left where it stood (Components).

A game shares its own things through a handover as the camera and the portal's crossing timer do, with no change here. Each mod stamps its own entry, named after its component, into the leaving player's `core/net/peer/share.transfer_data` before core's switch sends it: on `core/net/peer/switch`'s `added` edge, in `PostUpdate` before `core/net/peer/authority_switch` (or in `Update`, as the portal does), through `get_mut` or `entry("core/net/peer/share"):and_modify`, keeping the other entries. The target world's `core/net/peer/accept` decides which entries cross. On arrival there the mod reads its entry back from `synced_state` on the client's connection, on the player's `added` edge. Names stay literal in each mod.

## Notes

- A point is free when no player holds its index in `player.spawn_index`; a point given in the same run counts as taken.
- A spawner added after clients connected serves them: the mod loads with it, and a mod's first run sees every connection as changed.
- Players outlive their spawner: removing it stops this mod, and its players stay, unlinked, until their clients leave.
- The client drives the Transform, as there is no client prediction yet.
- Crossing: the target world's mirror of the player holds its synced state, which core's switch reads, and the camera rides the switch itself (`transfer_data`, whose entries win), as the mirror may be an unreliable update behind. Each entry crosses only if the target accepts its name (`core/net/peer/accept`). Leaving, the player stays in this world as a mirror of the target's new one (`player` skips setting it up again), and the client turns its body back to kinematic (`player/local`).
- A respawn for a connection that still holds `synced_state` arrives where it stood again, with the timers that crossed.
- Suites, headless: `tests/test_player_spawner.lua` (the link, the spawner's list, players outliving their spawner); `player/tests/test_player_handover.lua` (the share, a handed player's place, camera and crossing timer); `player/tests/test_player_server.lua` for the rest.
