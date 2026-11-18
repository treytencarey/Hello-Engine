---
depends_on: [scope/portal, core/net, core/world, player, input, ui/style, vault/github/branches, animation/clip]
conflicts_with: []
exposes: [scope/portal/console, scope/portal/console/user, scope/portal/console/request, scope/portal/console/response, scope/portal/console/target, scope/portal/console/state, scope/portal/console/camera, scope/portal/console/view, scope/portal/console/row]
---

# scope/portal/console

A console beside a scene's door, which re-points the door at another branch of this world's repository. The world's server decides a re-point: it takes a player's request only for a door its scene has, a console naming that door, and a target in this world's own repository. It sets its own copy of the door and keeps a record of the re-point, which reaches every client, a late joiner included. Each client sets its own copy of the door from the record, and from the door's authored value when the record goes. A re-point lasts while the world's server runs: a restart brings back the scene's target. Anyone in the world may re-point a door. The screen is each client's own, drawn as the VR panels are: the console's mesh shows an image a camera of the console draws its UI into. The player points at it with the mouse and clicks: it lists this repository's branches, through root, re-points the door at one, or makes a new branch and re-points the door at it once its world is up. Shared, server and client halves.

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
- `scope/portal/console/state = { listed, branches, error, typing }`: on the console, this client's own, added when the console arrives (one a reload finds stays). `listed`: root has answered the branch list; `branches`: its names; `error`: root's or the load's reason, shown on the screen; `typing`: the new branch's name while its field is open.
- `scope/portal/console/camera = { image }`: the camera drawing the screen, a `Camera2d` into the screen's image, a child of the screen's mesh. `image` is that image's handle, which the mouse's click is written to: the handle read back from the screen's material does not build a `PointerInput`.
- `scope/portal/console/view = {}`: the screen's UI root, on that camera (`UiTargetCamera`), a root of its own: a UI node under the scene is not laid out.
- `scope/portal/console/row = { target } | { new = true } | {}`: a row that acts on a click: a branch (re-point the door at `target`), "New branch" (open the name field) or "Create" while it is open (make the branch), or "List branches" (ask root).

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First (server) | `scope/portal/console/server` | On `scope/portal/console/user` added to a player with a `core/net/sync` table: add the request's and response's sync entries |
| First (server) | `scope/portal/console/server` | When `scope/portal/console/user` is removed from a player that stays: take those entries off |
| Update (server) | `scope/portal/console/server` | On a changed request: check it; refused, answer why; taken, set this side's door copy's `scope/portal` to the target and the console's `at` (or to its authored value, for its authored target), keep, move or despawn the door's record, and answer done |
| Update (server) | `scope/portal/console/server` | On a door arriving (its scene written again): set it from its record, if one names it |
| Update (client) | `scope/portal/console/client` | On a record arriving or changing, and on a door arriving: set this side's door copy from the record that names it, only when it differs. A run condition skips it otherwise |
| Update (client) | `scope/portal/console/client` | On a record gone: the door its last value named takes its authored value again, unless another record names it now |
| First (client) | `scope/portal/console/client` | On a console added: give it its state |
| First (client) | `scope/portal/console/client` | On a console added, or this client's own player arriving: bind `portal_console = { press = { button = "Left" } }` in its `input/game` and `input/ui` |
| First (client) | `scope/portal/console/client` | The last console gone: take the binding off |
| Update (client) | `scope/portal/console/client` | On a console or an `Aabb` added: once the console's mesh (the node's own, or its first descendant's) has its bounds, build the screen: an image of its size at 0.0008 m a pixel, the camera, the UI root, and the image unlit on the mesh |
| Update (client) | `scope/portal/console/client` | On a camera gone (its mesh gone): the UI root it drew goes |
| Update (client) | `scope/portal/console/client` | On a UI root added, a state changed, a door changed or a load changing or gone: rebuild the rows: "Points to <branch>", the error, then "List branches", or the branches (the door's own marked) and "New branch", or the name field and "Create" ("..." while its load runs) |
| Update (client) | `scope/portal/console/client` | On root's branch list answered: the state takes the branches or the error, and the ask goes |
| Update (client) | `scope/portal/console/client` | While a name field is open: keys type into it; Backspace takes a character, Enter makes the branch, Escape closes the field and gives game input back |
| Update (client) | `scope/portal/console/client` | On a new branch's load changing: ready, re-point the door at it, the load goes, the field closes and game input comes back; failed, the load goes and the screen says why |
| Update (client) | `scope/portal/console/client` | On this client's own player's `portal_console/press` added: a ray from its eye through the cursor (along the eye's forward when there is none); if the first thing within 3 m is a console's screen, Bevy's picking gets a move and a press at that pixel of its image |
| Update (server) | `scope/portal/console/server` | On a request taken (any branch, the authored one included): the door's rig on this side closes from where it stands (`speed = -1`); `animation/clip` publishes it |
| Update (server) | `scope/portal/console/server` | On the rig's published record (`animation/clip/node`) arriving or changing, closing and at 0: it opens (`speed = 1`) |
| Update (client) | `scope/portal/console/client` | On its `portal_console/press` removed: the same ray; on a screen, a release there |

## Use

In Blender, on the console's screen object, the custom property `scope/portal/console` = `{"door": "exit_portal", "at": "exit_portal"}`. Export with Custom Properties on.

```lua
-- a client asking, on its own player (one in its own nets' `core/net/owns`)
commands:entity(player):insert({
    ["scope/portal/console/request"] = { door = "exit_portal", target = "github:<owner>/<name>:<branch>" },
})

-- any side reading where a door leads now: its own copy's `scope/portal`, as for any door
```

The screen writes the same request, so a gate on the re-point (a door that must be open first, say) goes in the one place it is written, `repoint` in the client half.

The branch list is the console's `vault/github/branches = { owner, name }` ask, a `Request` under the console, and root's `vault/github/branches/reply = { branches } | { error }`. A new branch is a `core/world/load = { scope = "github:<owner>/<name>:<branch>" }` ask from this world, which root's resolve answers by making the branch, behind its own dialog.

## Notes

- A door's animation is the clip of its rig: the nearest node at or above the door carrying `animation/clip` (in the prologue map, `portal_rig` around `exit_portal`). Its state is authored: the rig carries `animation/clip` `{ clips = { ["<map>#Animation<N>"] = 1 }, speed = 0 }` and `animation/clip/seek` `{ to = "end" }` from Blender, so the door stands open. A door without one is only re-pointed.
- The server drives the door: a pick closes it on the server's copy of the rig, from where it stands, and once `animation/clip` publishes it shut, opens it. Each client plays its own copy from that record, which `animation/clip` copies; a client joining finds the door where the record says, open when nothing moves it.
- Each client plays the door on its own clock between records, so clients may differ a little.

- A door's authored value is read from its own `GltfExtras`, the custom properties `gltf/mod_registry` turned into its `scope/portal` (`shared/door.lua`). A door no scene authored has none, so a record that goes leaves it where it was.
- Each side spawns its own copy of the scene, so the record names the door by its `Name`, the one identity the two copies share. The record is not a portal: the view never reads it, and the door keeps its one `scope/portal` on each side, whose change the view and the server's links already follow.
- The request is only a door's name and a target; everything else is checked against what the server holds. Each player's crossing still loads the target through their own root.
- The screen's size comes from its mesh's `Aabb`, which Bevy computes once the mesh loads, at the mesh's world scale: its width along the mesh's own X, its height the larger of its Y and Z. A click's pixel is the hit's uv times that size, so the mesh's UVs are taken to span 0 to 1, u along X from the left and v down from the top.
- Every UI in the world shares one pixel space for the pointer, so the rows keep 64 px clear on the left, where the HUD's left bar is.
- The click reuses the mouse pointer: a pointer of its own would be `PointerId::Custom`, which Lua cannot build.
- The press and the release come on the button's own frames: Bevy clicks on a release only what the pointer hovered the frame before, so a move, press and release in one frame click nothing.
- A character key's `logical_key` reads back as `{ Character = { "<char>" } }`, a one-item list; Backspace, Enter and Escape read back as their names.
- The name field takes letters, digits, `-`, `.`, `_` and `/`, up to 100 characters.
- The screen goes with its mesh's camera; the screen's entities otherwise go with the mod, when its last console goes.
- Suites, headless: `test_console_server.lua` (the request, the refusals, the record, the door's scene written again); `test_console_client.lua` (the record re-points the door copy, its change follows, its removal restores the authored value, a late door takes its record); `test_console_net.lua` (over a real connection: the owner's request reaches the server, the owner hears done, and the record reaches the owner and a client that joined after it was made); `test_console_screen.lua` (the screen, with the mesh's `Aabb` written in Bevy's place and the rows clicked through Bevy's click: the binding, the screen built from the mesh, the list asked, refused and shown, a branch re-pointed, the name field typed into, Create's load and the re-point once it is ready, a screen's mesh gone and the last console gone).
- Suite, headless: `test_console_door.lua` (on a server, with where the rig stands written by the suite: the door published open as authored, a pick closing it from where it stands, opening once published shut, and a pick of the authored branch closing it too).
- Suites, windowed: `test_console_door_windowed.lua` (over time, on a client from the server's record: the door arriving open without playing the opening; closing it all the way and opening it again, twice) and `test_console_windowed.lua` (a real mesh: its `Aabb` read and the screen sized and laid out from it, the image drawn unlit, the UV assumption, a click on a row through the real pick, and nothing past 3 m).
