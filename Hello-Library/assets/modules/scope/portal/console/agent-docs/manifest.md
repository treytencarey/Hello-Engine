---
depends_on: [scope/portal, core/net, core/world, player]
conflicts_with: []
exposes: [scope/portal/console, scope/portal/console/user, scope/portal/console/request, scope/portal/console/response, scope/portal/console/target]
---

# scope/portal/console

A console beside a scene's door, which re-points the door at another branch of this world's repository. The world's server decides a re-point: it takes a player's request only for a door its scene has, a console naming that door, and a target in this world's own repository. It sets its own copy of the door and keeps a record of the re-point, which reaches every client, a late joiner included. Each client sets its own copy of the door from the record, and from the door's authored value when the record goes. A re-point lasts while the world's server runs: a restart brings back the scene's target. Anyone in the world may re-point a door. Shared, server and client halves.

## Components

- `scope/portal/console = { door, at }`: a custom property on the console's screen node in Blender, which `gltf/mod_registry` inserts on each side's own copy of the scene. Never synced.
  - `door`: the `Name` of the door it re-points, a scene door (a `scope/portal` with `at`).
  - `at`: the node a re-pointed door arrives at in the target's map. Every branch of a repository boots the same map, so the door's own name lands the player at the same door in the other branch. A door pointed back at its authored target keeps its authored `at`.
- `scope/portal/console/user = {}`: on each player, added by `player/server`. While it is there, the player's `core/net/sync` carries `scope/portal/console/request` from the owner's client (`{ authority = "client", target = "owner" }`) and `scope/portal/console/response` to the owner alone (`{ authority = "server", target = "owner" }`): this mod's server half adds the two entries when it arrives and takes them off when it goes from a player that stays.
- `scope/portal/console/request = { door, target }`: written by the owner's client on its own player. `target` is a scope key, `github:<owner>/<name>:<branch>`.
- `scope/portal/console/response = { status, reason }`: the server's answer, on the player, written whole for each request. `status` is `"done"` or `"refused"`; `reason`, with `refused`:
  - `no-such-door`: no door of that `Name` in this scene, or no console names it;
  - `not-this-repository`: the target is not a branch of this world's repository (`core/world/status.scope_root` of this world's own row, then `:` and a branch).
- `scope/portal/console/target = { door, target, at }`: the record of a re-point, one per re-pointed door, keyed by the door's `Name`. Spawned by the server with `core/net/sync = { ["scope/portal/console/target"] = { authority = "server" } }`, so every client gets it, and `["core/script/owner"] = false`, so it outlives a reload of this mod and the scene being written again. A later request for the same door changes it; pointing the door back at its authored target despawns it.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First (server) | `scope/portal/console/server` | On `scope/portal/console/user` added to a player with a `core/net/sync` table: add the request's and response's sync entries |
| First (server) | `scope/portal/console/server` | When `scope/portal/console/user` is removed from a player that stays: take those entries off |
| Update (server) | `scope/portal/console/server` | On a changed request: check it; refused, answer why; taken, set this side's door copy's `scope/portal` to the target and the console's `at` (or to its authored value, for its authored target), keep, move or despawn the door's record, and answer done |
| Update (server) | `scope/portal/console/server` | On a door arriving (its scene written again): set it from its record, if one names it |
| Update (client) | `scope/portal/console/client` | On a record arriving or changing, and on a door arriving: set this side's door copy from the record that names it, only when it differs. A run condition skips it otherwise |
| Update (client) | `scope/portal/console/client` | On a record gone: the door its last value named takes its authored value again, unless another record names it now |

## Use

In Blender, on the console's screen object, the custom property `scope/portal/console` = `{"door": "exit_portal", "at": "exit_portal"}`. Export with Custom Properties on.

```lua
-- a client asking, on its own player (one in its own nets' `core/net/owns`)
commands:entity(player):insert({
    ["scope/portal/console/request"] = { door = "exit_portal", target = "github:<owner>/<name>:<branch>" },
})

-- any side reading where a door leads now: its own copy's `scope/portal`, as for any door
```

## Notes

- A door's authored value is read from its own `GltfExtras`, the custom properties `gltf/mod_registry` turned into its `scope/portal` (`shared/door.lua`). A door no scene authored has none, so a record that goes leaves it where it was.
- Each side spawns its own copy of the scene, so the record names the door by its `Name`, the one identity the two copies share. The record is not a portal: the view never reads it, and the door keeps its one `scope/portal` on each side, whose change the view and the server's links already follow.
- The request is only a door's name and a target; everything else is checked against what the server holds. Each player's crossing still loads the target through their own root.
- Not built yet: the screen (the branch list, New branch, and pointing at the screen with the mouse), which waits for names of its own. Until then a request is written by another mod or a suite.
- Suites, headless: `test_console_server.lua` (the request, the refusals, the record, the door's scene written again); `test_console_client.lua` (the record re-points the door copy, its change follows, its removal restores the authored value, a late door takes its record); `test_console_net.lua` (over a real connection: the owner's request reaches the server, the owner hears done, and the record reaches the owner and a client that joined after it was made).
