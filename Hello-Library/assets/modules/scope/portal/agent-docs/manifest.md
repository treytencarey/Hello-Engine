---
depends_on: [collision_trigger, placement, cooldown, core/net, core/net/peer, core/world/flip]
conflicts_with: []
exposes: [scope/portal, scope/portal/hosted, scope/portal/locked, scope/portal/cooling]
---

# scope/portal

A way into another world, named by its scope key. A portal is one-ended: the way back is the other world's own portal. Walking in moves the player there. When the target runs in the same process as this world, with its peer link up, this world's server hands the player's entity over and the player arrives where it stood; otherwise root flips the player into the target (starting it if nobody runs it) and the player arrives at that world's spawn point. Shared, server and client halves. How a portal looks and what it shows is `scope/portal/view`.

## Components

- `scope/portal = { target }`: `target` is the scope key of the world the portal leads to (`github:<owner>/<name>:<branch>`).
- `scope/portal/hosted = {}`: on a placed portal whose target's peer link here is connected and welcomed by a world of that scope. Written by the server, synced from the server on a portal a player opened. It means the server can hand a player over.
- `scope/portal/locked = { reason }`: on a client's portal whose target root refused to show (`not-running`, a Gateway's refusal; `refused` when root gave none). Root canonicalizes the target there, so a target it cannot take ends locked too, with root's reason; no library mod checks a key's form. Written by `scope/portal/view`.
- `scope/portal/cooling = {}`: on a player handed in from another world, for 3 s, while it may not cross again. It is a `cooldown` timer that crosses with the player: at the handover the server adds `cooldown = { ["scope/portal/cooling"] = { remaining = 3 } }` to `core/net/peer/share.transfer_data`, which core's switch sends to the target world; the target keeps it only if its `core/net/peer/accept` list takes `cooldown` (a world's boot declares that list; Hello-Backrooms' `world/boot/server` accepts `"all"`). `player/spawner` there spawns the player with the timers that crossed, synced to its owner, and `cooldown` adds and removes the mark on each side. A world that does not accept `cooldown` does not cool.
- Placed means without `placement`. On both sides, a placed portal gets `RigidBody3d = "Fixed"`, `Collider3d = { ball = { radius = 1.2 } }` and `collision_trigger = {}`, each one only if the entity lacks it, in one insert (a body must arrive with its collider). Taking `scope/portal` off an entity that stays takes those three off, and on the server its peer links.
- A peer link the server keeps, as a child of a placed portal naming its target: `{ ["core/net/peer/link"] = { name = "peer_to_127.0.0.1_<target's world port>", port = <target's peer port>, scope_key = <target>, server_addr = "127.0.0.1" }, ["core/net/sync"] = false }`.

The mod's return declares no sync, so a portal a scene spawns on each side (a glTF door, whose node carries `scope/portal` as a custom property) is never replicated. A portal a player opens is spawned on the server by `git/panel`'s server half, with its sync in the spawn, so every client sees it.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `scope/portal/shared` | On `scope/portal` added without `placement`, or `placement` removed: the body, ball collider and trigger. On `scope/portal` removed from an entity that stays: remove them |
| Update (server) | `scope/portal/server` | Link: for each target a placed portal names (not this world's scope) whose `core/world/status` row here says `mode = "server"`, `status = "ready"` and has `ports.peer`, keep exactly one link, a child of a portal naming it. A link whose row went, whose port or name no longer matches, or that duplicates another is despawned. Runs on `scope/portal` added, changed or removed, `placement` removed, a row added, changed or removed, and a link removed |
| Update (server) | `scope/portal/server` | On `scope/portal` removed from an entity that stays: despawn its child links |
| Update (server) | `scope/portal/server` | Hosted: a placed portal whose target has a link with `core/net/peer/link/state` connected, welcomed, not given up and `scope_key` equal to the target gets `scope/portal/hosted`; one that no longer has such a link loses it. Every placed portal, synced or not (a scene's door is marked too, on the server only). Runs on link state and portal edges |
| Update (server) | `scope/portal/server` | Hand over: on a changed `collision_trigger` on a placed portal whose target's link is welcomed (and is not this world's scope), each entity in `entered` that carries `player`, `core/net/owner` and `core/net/peer/share`, and none of `core/net/peer/mirror`, `WorldMirror` and `scope/portal/cooling`, gets `["core/net/peer/switch"] = { target_scope = target }`, and `transfer_data.cooldown["scope/portal/cooling"] = { remaining = 3 }` on its `core/net/peer/share` (other entries kept) |
| Update (client) | `scope/portal/client` | Not hosted: on a changed `collision_trigger` on a placed portal without `scope/portal/hosted`, if `entered` holds this client's player (`player` with `core/net/local`, not `scope/portal/cooling`), the target is not this world's scope and this world is not only observing, spawn `{ ["core/world/flip"] = { scope = target }, WorldShared = {}, ["core/net/sync"] = false, ["core/script/owner"] = false }` |
| Update (client) | `scope/portal/client` | Hosted: on `core/net/local` removed from a `player` that stays, spawn the same flip ask for the first hosted placed portal whose `collision_trigger.inside` holds it |

## Use

A player asks for a portal on `git/panel`'s request slot, and the world's server opens it for the player to place:

```lua
commands:entity(player):insert({ ["git/panel/request"] = { op = "portal", target_sk = "github:treytencarey/hello-backrooms:new-room" } })
```

A scene door: give the node the custom properties `scope/portal = {"target": "<scope key>"}` and `scope/portal/view = {"mode": "none"}`; `gltf/mod_registry` inserts them on each side.

## Notes

- The handover is core's peer switch (`core/net/peer`): it sends the player's synced state to the target's server and demotes the player here to a mirror of the target's new one. The demoted player has no `core/net/owner`, so walking into a portal again matches nothing here. The player's own side is `player` and `player/spawner`.
- The client follows the server instead of flipping on entry into a hosted portal: a flip at once would race the handover, and a client that won would arrive at the spawn point.
- The handover reaches only worlds in this process: branches of one repository, and repositories hosted in one Gateway's own process. Elsewhere the flip starts or joins the target, and the player arrives at its spawn point.
- Root drops a second flip ask for a flip already under way, and an ask is root's once made, so a reload of this mod does not take it back.
- The server spawns a player's portal itself (`git/panel`), so the portal's own component loads this mod there. A client's predicted spawn reaches the server only as `core/net/predict.requested`, which loads nothing, so nothing here approves one.
- A scene's door is each side's own entity: the server's `scope/portal/hosted` never reaches the client's copy, so the client flips on entry into a door at once, racing the handover, and the player may arrive at the spawn point.
- The server's trigger fires from the server's copy of the player, which eases toward what the client sends (`player`). If it never sees the entry, the client stays in this world; walking in again retries.
- A player handed in arrives where it stood, maybe inside a portal of this world: it cools for 3 s first, when this world accepts `cooldown`, so it does not bounce straight back. The server skips a cooling player at the handover, and its client skips its own flip. The client does not skip following a handover the server made: the server's timer decides that, and the client's may run a little behind it.
- Suites: `tests/test_portal_server.lua` (links, hosted, handover, the timer it carries, the cooling, the body), `tests/test_portal_client.lua` (the two flips, the cooling) and `tests/test_portal_cross.lua` (two worlds: the timer crossing into a world that accepts `cooldown`), all headless; the portal a player opens is `git/panel`'s suites.
