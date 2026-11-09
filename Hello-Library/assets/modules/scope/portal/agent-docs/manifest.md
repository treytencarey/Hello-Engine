---
depends_on: [collision_trigger, placement, core/net, core/net/peer, core/world/flip]
conflicts_with: []
exposes: [scope/portal, scope/portal/hosted, scope/portal/locked]
---

# scope/portal

A way into another world, named by its scope key. A portal is one-ended: the way back is the other world's own portal. Walking in moves the player there. When the target runs in the same process as this world, with its peer link up, this world's server hands the player's entity over and the player arrives where it stood; otherwise root flips the player into the target (starting it if nobody runs it) and the player arrives at that world's spawn point. Shared, server and client halves. How a portal looks and what it shows is `scope/portal/view`.

## Components

- `scope/portal = { target }`: `target` is the scope key of the world the portal leads to (`github:<owner>/<name>:<branch>`).
- `scope/portal/hosted = {}`: on a placed portal whose target's peer link here is connected and welcomed by a world of that scope. Written by the server, synced from the server on a portal a client placed. It means the server can hand a player over.
- `scope/portal/locked = { reason }`: on a client's portal whose target root refused to show (`not-running`, a Gateway's refusal; `refused` when root gave none). Written by `scope/portal/view`.
- Placed means without `placement`. On both sides, a placed portal gets `RigidBody3d = "Fixed"`, `Collider3d = { ball = { radius = 1.2 } }` and `collision_trigger = {}`, each one only if the entity lacks it, in one insert (a body must arrive with its collider). Taking `scope/portal` off an entity that stays takes those three off, and on the server its peer links.
- A peer link the server keeps, as a child of a placed portal naming its target: `{ ["core/net/peer/link"] = { name = "peer_to_127.0.0.1_<target's world port>", port = <target's peer port>, scope_key = <target>, server_addr = "127.0.0.1" }, ["core/net/sync"] = false }`.

The mod's return declares no sync, so a portal a scene spawns on each side (a glTF door, whose node carries `scope/portal` as a custom property) is never replicated. A portal a client places gets its sync from the server's approval.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `scope/portal/shared` | On `scope/portal` added without `placement`, or `placement` removed: the body, ball collider and trigger. On `scope/portal` removed from an entity that stays: remove them |
| Update (server) | `scope/portal/server` | Approve: on an added `core/net/predict` whose `requested` holds `scope/portal`, refuse (despawn) unless the target is a canonical `github:` scope key (`Canonical.canonical(Canonical.parse(target)) == target`, not reserved) other than this world's scope, and the client holds fewer than 8 portals here (counted over `scope/portal` with `core/net/owner`, and over this run's approvals). Approved, it inserts `scope/portal { target }`, `scope/portal/view { mode }` (`"3d"` or `"none"` as asked, else `"3d"`), `placement` if asked, `Transform` at the asked translation, `core/net/sync` (`placement` client and `Transform` client unreliable while placing, else `Transform` server; `scope/portal`, `scope/portal/view` and `scope/portal/hosted` server) and `["core/script/owner"] = false`, and removes `core/net/predict` |
| Update (server) | `scope/portal/server` | Link: for each target a placed portal names (not this world's scope) whose `core/world/status` row here says `mode = "server"`, `status = "ready"` and has `ports.peer`, keep exactly one link, a child of a portal naming it. A link whose row went, whose port or name no longer matches, or that duplicates another is despawned. Runs on `scope/portal` added, changed or removed, `placement` removed, a row added, changed or removed, and a link removed |
| Update (server) | `scope/portal/server` | On `scope/portal` removed from an entity that stays: despawn its child links |
| Update (server) | `scope/portal/server` | Hosted: a placed portal whose target has a link with `core/net/peer/link/state` connected, welcomed, not given up and `scope_key` equal to the target gets `scope/portal/hosted`; one that no longer has such a link loses it. Every placed portal, synced or not (a scene's door is marked too, on the server only). Runs on link state and portal edges |
| Update (server) | `scope/portal/server` | Hand over: on a changed `collision_trigger` on a placed portal whose target's link is welcomed (and is not this world's scope), each entity in `entered` that carries `player`, `core/net/owner` and `core/net/peer/share`, and neither `core/net/peer/mirror` nor `WorldMirror`, gets `["core/net/peer/switch"] = { target_scope = target }` |
| Update (client) | `scope/portal/client` | Not hosted: on a changed `collision_trigger` on a placed portal without `scope/portal/hosted`, if `entered` holds this client's player (`player` with `core/net/local`), the target is not this world's scope and this world is not only observing, spawn `{ ["core/world/flip"] = { scope = target }, WorldShared = {}, ["core/net/sync"] = false, ["core/script/owner"] = false }` |
| Update (client) | `scope/portal/client` | Hosted: on `core/net/local` removed from a `player` that stays, spawn the same flip ask for the first hosted placed portal whose `collision_trigger.inside` holds it |

## Use

A client places a portal by predicting it (as `git/panel`'s Portal row does); the server approves it:

```lua
commands:spawn({
    ["scope/portal"] = { target = "github:treytencarey/hello-backrooms:new-room" },
    ["scope/portal/view"] = { mode = "3d" },
    placement = {},
    Transform = { translation = at },
    ["core/net/sync"] = {
        placement = { authority = "client" },
        Transform = { authority = "client", reliable = false },
    },
})
```

A scene door: give the node the custom properties `scope/portal = {"target": "<scope key>"}` and `scope/portal/view = {"mode": "none"}`; `gltf/mod_registry` inserts them on each side.

## Notes

- The handover is core's peer switch (`core/net/peer`): it sends the player's synced state to the target's server and demotes the player here to a mirror of the target's new one. The demoted player has no `core/net/owner`, so walking into a portal again matches nothing here. The player's own side is `player` and `player/spawner`.
- The client follows the server instead of flipping on entry into a hosted portal: a flip at once would race the handover, and a client that won would arrive at the spawn point.
- The handover reaches only worlds in this process: branches of one repository, and repositories hosted in one Gateway's own process. Elsewhere the flip starts or joins the target, and the player arrives at its spawn point.
- Root drops a second flip ask for a flip already under way, and an ask is root's once made, so a reload of this mod does not take it back.
- The server's approval runs only where this mod is loaded on the server, which a portal there does (a placed portal or a scene's door). A world with no portal on its server never answers the first predicted one: core's net server times it out.
- A scene's door is each side's own entity: the server's `scope/portal/hosted` never reaches the client's copy, so the client flips on entry into a door at once, racing the handover, and the player may arrive at the spawn point.
- The server's trigger fires from the server's copy of the player, which eases toward what the client sends (`player`). If it never sees the entry, the client stays in this world; walking in again retries.
- Not done yet: a crossing cooldown, which would stop a player handed into a world bouncing straight back through a portal standing where it arrives.
- Suites: `tests/test_portal_server.lua` (approval, links, hosted, handover, the body) and `tests/test_portal_client.lua` (the two flips), both headless.
