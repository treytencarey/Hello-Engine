---
depends_on: [collision_trigger, placement, cooldown, core/net, core/net/peer, core/world/flip]
conflicts_with: []
exposes: [scope/portal, scope/portal/hosted, scope/portal/locked, scope/portal/cooling, scope/portal/return, scope/portal/returns]
---

# scope/portal

A way into another world, named by its scope key. Walking in moves the player there. When the target runs in the same process as this world, with its peer link up, this world's server hands the player's entity over and the player arrives where it stood; otherwise root flips the player into the target (starting it if nobody runs it) and the player arrives at that world's spawn point. Shared, server and client halves. How a portal looks and what it shows is `scope/portal/view`.

A portal a player dropped in world X that leads to world Y also stands in Y, at the same place, leading back to X, wherever the handover works: both worlds run in one process, X's peer link to Y is up, and the portal is `scope/portal/hosted`. It stands in Y only: no other world linked with X gets it. Elsewhere, and for a scene's door, a portal is one-ended: the way back is the other world's own portal.

```
world X (server)                                 world Y (server)
portal { target = Y }  --hosted-->  link X->Y    mirror of the return end:
  ^ scope/portal/returns                           scope/portal { target = X } at the portal's place,
  | scope/portal/return { entity }                 replicated to Y's clients: viewed, hosted (Y's own
return end { target = X } --core/net/peer/share--> link Y->X), walked into
  (here it leads to X itself: ignored)  { to = { Y } }: to Y alone
```

## Components

- `scope/portal = { target }`: `target` is the scope key of the world the portal leads to (`github:<owner>/<name>:<branch>`).
- `scope/portal/hosted = {}`: on a placed portal whose target's peer link here is connected and welcomed by a world of that scope. Written by the server, synced from the server on a portal a player opened. It means the server can hand a player over.
- `scope/portal/locked = { reason }`: on a client's portal whose target root refused to show (`not-running`, a Gateway's refusal; `refused` when root gave none). Root canonicalizes the target there, so a target it cannot take ends locked too, with root's reason; no library mod checks a key's form. Written by `scope/portal/view`.
- `scope/portal/cooling = {}`: on a player handed in from another world, for 3 s, while it may not cross again. It is a `cooldown` timer that crosses with the player: at the handover the server adds `cooldown = { ["scope/portal/cooling"] = { remaining = 3 } }` to `core/net/peer/share.transfer_data`, which core's switch sends to the target world; the target keeps it only if its `core/net/peer/accept` list takes `cooldown` (a world's boot declares that list; Hello-Backrooms' `world/boot/server` accepts `"all"`). `player/spawner` there spawns the player with the timers that crossed, synced to its owner, and `cooldown` adds and removes the mark on each side. A world that does not accept `cooldown` does not cool.
- Placed means without `placement`. On both sides, a placed portal gets `RigidBody3d = "Fixed"`, `Collider3d = { ball = { radius = 1.2 } }` and `collision_trigger = { entered = {}, exited = {}, inside = <who already overlaps> }`: when `placement` is removed (the portal is dropped), or when `scope/portal` arrives on an entity that has no `placement` (a scene's door, from its spawn), each one only if the entity lacks it, in one insert (a body must arrive with its collider). A portal still being placed has none of them: it follows its placer (`git/panel`'s preview) and must never hold or hand over anyone. Taking `scope/portal` off an entity that stays takes those three off, and on the server its peer links and its return end.
- **Only walking in counts.** The trigger starts out holding every body that already overlaps the ball at the portal's place (Rapier's `intersect_shape` with `Collider.ball(1.2)` and `flags = "EXCLUDE_FIXED"`, as a fixed trigger sees no fixed collider; a scene's node is asked at its world place). `collision_trigger` reads `entered` as what overlaps now minus `inside`, so the player a portal is dropped on, or a door spawns around, is not taken in: it crosses only after walking out and back in. A body that comes to Rapier later inside a placed portal (a player spawned in a door, one handed in there) joins that portal's `inside` before the trigger reads it, so it has not walked in either. A player handed in through a two-ended portal still cools for 3 s as before.
- The body is inserted before `collision_trigger/init`, so the trigger's sensor parts land in the same frame and Rapier never builds the portal as a solid ball. The exception is the first trigger in a world, whose own component loads `collision_trigger`: its parts come once the mod has loaded, a frame or so later.
- A peer link the server keeps, as a child of a placed portal naming its target: `{ ["core/net/peer/link"] = { name = "peer_to_127.0.0.1_<target's world port>", port = <target's peer port>, scope_key = <target>, server_addr = "127.0.0.1" }, ["core/net/sync"] = false, ["core/script/owner"] = false }`. It outlives a reload of the server half, which keeps it.
- `scope/portal/return = { entity = <the portal> }`: on a return end, on the server of the portal's world. A relationship with target `scope/portal/returns` on the portal, `linked_spawn = true`, so the return end goes with its portal. It is never synced and never crosses.
- A return end, which the server spawns for a placed, `scope/portal/hosted` portal whose `core/net/sync` is a table (one a player dropped; a scene's door is never replicated, and each side's scene has its own), that is no mirror itself (`core/net/peer/mirror`). It is what the portal syncs: every component its `core/net/sync` names, copied from the portal (its `Transform`, its `scope/portal/view`, and whatever another mod syncs on it), under the portal's own `core/net/sync`, with `scope/portal.target` turned to this world's scope. `scope/portal/hosted` is not copied, though its sync entry is: it is the server half's own mark, which the return end never has here and the target's server writes there. Beside the copy: `["scope/portal/return"] = { entity = <the portal> }`, `["core/net/peer/share"] = { stable_id = "scope/portal/return:<this world's scope>><target>@<x>,<y>,<z>", to = { <target> } }` (the place to three decimals) and `["core/script/owner"] = false`. The server half names none of the copied components: it reads them by the names the sync lists (a query's `with_columns`).
  - A portal that comes to sync a name its return end's sync lacks gets a new return end, a run after the old one goes: the target keeps a mirror's sync as it arrived, so a name added later would never reach the target's clients, and a despawn and a spawn of one id in one frame would reach the target spawn first. A copied component whose value changes later is not followed.
  - Here it leads to this world itself, which every half ignores: no link, no `hosted`, no handover, no flip, and `scope/portal/view` neither asks nor draws for it. This world's clients get it as a replica that shows nothing.
  - Core's peer layer mirrors it into the target, and only the target: its share names the target in `to`, written whole in the spawn, so core sends its spawn, updates and despawn only to the peer whose world scope that is (`core/net/peer`). Every other world linked with this one, either way (one this world has another hosted portal to, or one whose own portal leads here), would otherwise take it for a portal to this world at the portal's place.
  - The target keeps what it accepts (`scope/portal`, `scope/portal/view`, `scope/portal/hosted`, `Transform`; Hello-Backrooms accepts `"all"`). The mirror keeps its sync, so the target's server replicates it to its clients, and there it is an ordinary portal to this world: its server links back here and marks it hosted, its clients view it, and walking in hands the player back.
  - The stable id names the two worlds and the place, as an entity is never named in data: two portals at one place to one target share one return end, and a portal moved or given another target gets a new one.
  - Lifetime: it goes with its portal (the relationship), when the portal loses `scope/portal/hosted`, and when `scope/portal` is taken off the portal; it comes back with `hosted`. It outlives a reload of the server half, which keeps it. A source's despawn reaches the mirror as core's `entity_despawn`, and a dropped connection takes the mirrors that came over it.

The mod's return declares no sync, so a portal a scene spawns on each side (a glTF door, whose node carries `scope/portal` as a custom property) is never replicated. A portal a player opens is spawned on the server by `git/panel`'s server half, with its sync in the spawn, so every client sees it.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `scope/portal/shared` | On `scope/portal` added or `placement` removed, for a portal that is placed: the body, ball collider and trigger, its `inside` the bodies already overlapping the ball; before `collision_trigger/init`. A cancelled placement despawned the portal and gets nothing. On `scope/portal` removed from an entity that stays: remove them |
| First (both) | `scope/portal/shared` | On a `RapierColliderHandle3d` added to an entity that is not a portal (a body new to Rapier): each placed portal whose ball overlaps it adds it to its trigger's `inside` (`entry("collision_trigger"):and_modify`), before `collision_trigger` reads. Runs only on that edge |
| Update (server) | `scope/portal/server` | Link: for each target a placed portal names (not this world's scope) whose `core/world/status` row here says `mode = "server"`, `status = "ready"` and has `ports.peer`, keep exactly one link, a child of a portal naming it. A link whose row went, whose port or name no longer matches, or that duplicates another is despawned. Runs on `scope/portal` added, changed or removed, `placement` removed, a row added, changed or removed, and a link removed |
| Update (server) | `scope/portal/server` | On `scope/portal` removed from an entity that stays: despawn its child links and its return end |
| Update (server) | `scope/portal/server` | Return ends: each placed portal this world holds (not a mirror, not a return end) keeps the one return end its world, target and place name while it is hosted, has a sync table and this world's scope is known, and none otherwise; a return end whose stable id no longer matches, or that another portal's already holds, is despawned, one whose sync lacks a name the portal's lists is despawned and made again on the next run, and one is spawned, a copy of what the portal syncs, where none is held. Runs on `scope/portal`, `scope/portal/hosted` or a row added, `scope/portal` or `core/net/sync` changed, and `scope/portal/hosted`, `scope/portal/return` or `placement` removed |
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

### Two-ended map doors

A map door gets no return end. A door that leads both ways is two door empties at the same spot, one leading each way. Branches of one repository share one map file, so both empties exist in each world, and the one leading to the world it is in is ignored there: a portal to its own world links nothing, takes no one in and shows nothing. Each empty's own `scope/portal/view` decides whether that side sees the other world: in branch `room-a` the empty leading to `room-b` is the door, so its view is what `room-a` sees; leave the view off for a door that is only walked through.

In Blender, two empties at the same location, each with two custom properties (Object Properties > Custom Properties, typed as JSON strings), exported with Include > Custom Properties:

```
Empty "door_to_b":  scope/portal       {"target": "github:<owner>/<repo>:room-b"}
                    scope/portal/view  {"mode": "3d"}
Empty "door_to_a":  scope/portal       {"target": "github:<owner>/<repo>:room-a"}
                    scope/portal/view  {"mode": "3d"}
```

With `{"mode": "none"}` instead, the door shows the other world on its own mesh: the empty's mesh children.

## Notes

- The handover is core's peer switch (`core/net/peer`): it sends the player's synced state to the target's server and demotes the player here to a mirror of the target's new one. The demoted player has no `core/net/owner`, so walking into a portal again matches nothing here. The player's own side is `player` and `player/spawner`.
- The client follows the server instead of flipping on entry into a hosted portal: a flip at once would race the handover, and a client that won would arrive at the spawn point.
- The handover reaches only worlds in this process: branches of one repository, and repositories hosted in one Gateway's own process. Elsewhere the flip starts or joins the target, and the player arrives at its spawn point.
- Root drops a second flip ask for a flip already under way, and an ask is root's once made, so a reload of this mod does not take it back.
- The server spawns a player's portal itself (`git/panel`), so the portal's own component loads this mod there. A client's predicted spawn reaches the server only as `core/net/predict.requested`, which loads nothing, so nothing here approves one.
- A scene's door is each side's own entity: the server's `scope/portal/hosted` never reaches the client's copy, so the client flips on entry into a door at once, racing the handover, and the player may arrive at the spawn point.
- The server's trigger fires from the server's copy of the player, which eases toward what the client sends (`player`). If it never sees the entry, the client stays in this world; walking in again retries.
- A player handed in arrives where it stood, maybe inside a portal of this world: it cools for 3 s first, when this world accepts `cooldown`, so it does not bounce straight back. The server skips a cooling player at the handover, and its client skips its own flip. The client does not skip following a handover the server made: the server's timer decides that, and the client's may run a little behind it.
- A player handed through a two-ended portal arrives inside its return end. `collision_trigger.entered` holds only the latest change, so a player who stays inside after its timer ends is not handed back; walking out and in again hands it back.
- A link spawned again (a reload that took it) drops `hosted` until it is welcomed, which would take every return end there and back, and with each mirror the target's link back here. Links are therefore kept through a reload.
- Suites: `tests/test_portal_server.lua` (links, hosted, handover, the timer it carries, the cooling, no body while placing and the body once placed, no handover while placing, and with real physics: dropped on a player, a player spawned inside, a door spawned around a player, none handed over, walking out and back in handed over, and no portal reaching Rapier as a solid ball), `tests/test_portal_client.lua` (the two flips, the cooling, and with real physics a portal being placed on the player with no body and asking nothing, then dropped on it asking nothing, and walking out and back in asking one), `tests/test_portal_cross.lua` (two worlds: the timer crossing into a world that accepts `cooldown`) and `tests/test_portal_return.lua` (three worlds with real links both ways: the return end in the target and in the portal's world, each linked world holding only the return end meant for it, none for a door or a portal being placed, hosted there, nothing in the portal's world, a reload keeping it, a player handed through and back with real physics, its lifetime with the link and the portal, a portal placed later, `scope/portal` taken off a portal that stays, and the return end being what the portal syncs, a component synced later too), all headless; the portal a player opens is `git/panel`'s suites.
