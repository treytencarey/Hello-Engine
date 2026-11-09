---
depends_on: [notification, cooldown, ui/style, core/registry, core/world, scope/portal]
conflicts_with: []
exposes: [sidebar/invites, sidebar/invites/state, sidebar/invites/notification, sidebar/invites/notification/row, sidebar/invites/request]
---

# sidebar/invites

The player's invites to other worlds, one card each, answered from the card. Root holds the player's Hello! session and makes every Site call: this mod asks root's `core/registry/invites` for the list and `core/registry/invites/answer` for each answer, and shows what root says. An accepted invite then has root load the host's world join-only, and a portal to it opens 3 m behind the player's back. Sending invites is `git/collaborators`'s. Local UI: never synced, and it needs no open panel: the cards are `notification` toasts.

## Components

- `sidebar/invites = {}` on the local player, which carries it whether or not a panel is open. The player's client half adds and removes it.
- `sidebar/invites/state = { feedback, feedback_kind }` on the carrier, added by this mod when the carrier arrives, and again if taking `sidebar` off the player took it (a `sidebar/` part goes with `sidebar`). `feedback` is the last thing an answer, its world or its portal said; `feedback_kind` is `"ok"`, `"error"` or `"stale"`. Nothing here draws it: `git/collaborators` shows it under its send result.
- `sidebar/invites/notification = { invite_id, sender_login, scope_key, message }` on each card, beside `notification` (no `timeout`, so it stays until answered or withdrawn). `invite_id` is the invite's id in root's list, or `"debug-<n>"` for a debug invite; `sender_login` is root's `inviter`; `scope_key` its `scope`; `message` is `"wants you in <scope>"`.
- `sidebar/invites/notification/row`: marks each part of a card's content, its children.
- `sidebar/invites/request = { op, invite_id, scope_key }`:
  - on a hold, a child of the carrier, for each answer: `op` is `"accept"` or `"decline"`. A real answer's hold carries `cooldown = { ["sidebar/invites/request"] = { remaining = 30 } }`, so `cooldown` takes the component off after 30 s; root's request is the hold's child. A debug answer's hold has no timer and goes once handled.
  - on a portal this mod dropped, `op = "drop_portal"`, until the server confirms it.

Root's requests carry nothing of this mod's and outlive a reload of it (`core/script/owner = false`):
- the list, standing while the carrier is here: `{ ["core/registry/invites"] = {}, Request = {} }`, a child of the carrier. Its reply is `{ invites = { { id, scope, inviter, expires_at } }, error }`.
- an answer, a child of its hold: `{ ["core/registry/invites/answer"] = { id, action }, Request = {} }`, replied `{ status = "asking" | "ok" | "refused", scope, reason }`.
- the load of an accepted world, a child of the carrier: `{ ["core/world/load"] = { scope, join_only = true }, WorldShared = {}, ["core/net/sync"] = false }`. Root claims it and writes `status` (`"ready"` or `"failed"` with `reason`) on it.

The dropped portal: `{ Transform = { translation }, ["scope/portal"] = { target = <scope> }, ["scope/portal/view"] = { mode = "3d" }, ["core/net/sync"] = { Transform = { authority = "client" } } }`, with no `placement`, so it is placed at once. The net client predicts it, and the world's server approves or refuses it.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `sidebar/invites` | A new carrier gets its state, if it has none, and its standing list request, if it has none; the state comes back if `sidebar` going took it |
| First | `sidebar/invites` | When `sidebar/invites` is removed from an entity that stays, close its list request and its load requests, and every hold whose timer ended (a running hold goes as a part of the mod) |
| Update | `sidebar/invites` | Reconcile the cards with root's list: one card per listed invite that has no card and no running hold; a card whose invite left the list (not a debug card) gets `notification.dismiss = true`. Runs on a list reply, a hold ending, a card going, and a carrier arriving |
| Update, after `sidebar/invites` | `sidebar/invites/render` | Draw a card's content when it is added or changed, and every card when a carrier arrives (a reload) |
| Update | `sidebar/invites` | On an answer's reply turning `ok` or `refused`: say the outcome; for an accepted `ok`, spawn the join-only load for the reply's `scope` (else the hold's `scope_key`) unless the carrier already has one for it; despawn the hold, with its request, if its timer has ended |
| Update | `sidebar/invites` | When a hold's timer ends, despawn it, with its request, if root has answered |
| Update | `sidebar/invites` | On a carrier's load turning `ready`, or a debug accept, drop the portal after the checks below; on `failed`, say why and despawn the load |
| Update | `sidebar/invites` | A portal confirmed (its `core/net/predict` removed while it stays) says "Portal opened - walk through to join" and loses its `drop_portal` mark; a marked portal that despawned was refused; a portal going despawns the carrier's load for its target when no other portal of this player names it |

## What the card says and does

- "INVITE" (size 9, `accent`), "<sender> invited you" (12, `text`; "someone" with no sender), the scope (10, `text_dim`), the message (10, `text_dim`), then a row of Accept (`icon_active`) and Decline (`icon_bg`), each 26 px high with `row_hover` on hover.
- A click on either sets the card's `notification.dismiss` at once and spawns the hold with root's answer under it. A click on a card already fading does nothing, except on a debug card: "That invite no longer exists".
- While a hold runs, its invite gets no card, though root's list (asked every 20 s) still names it. When the timer ends and the list still names the invite, the card comes back.

## What follows an answer

- `ok`, decline: "Invite declined". `refused`: "Invite <action> failed: <reason>", or "Sign in to answer invites" for `sign-in-required`. Accept: "Opening a door to <scope>".
- The load answers on its own entity. `failed` with `not-running` or `no-gateway`: "That world has ended" (`stale`); any other reason: "Could not open that world: <reason>". The load goes either way.
- `ready`: the portal drops at the carrier's `Transform.translation` plus its rotation applied to `(0, 0, 3)` (Bevy's `back()`, 3 m). Before it does, the client checks what the server will, and says:
  - no row of this world's own (`core/world/status` without `WorldMirror`): "No active scope to place a portal in";
  - the target is this world's `scope_key`: "You are already in that world";
  - the player already has 8 portals here (counted over `scope/portal` entities that are `core/net/local`, carry this mod's mark, or are owned by the carrier's `core/net/owner.client_id`): "You have too many portals open".
  A refused drop also despawns the carrier's load for that scope. A target the player already has a portal to drops nothing more; a second `ready` drops nothing.
- The server refusing the predicted portal (it despawns with no confirmation) says "You have too many portals open": the other checks passed here.
- The load stays while a portal of this player's names its world, so the observed world is not let go between the load and the portal's own view.

## Debug invites

A debug card is spawned by `git/collaborators` when its `DEBUG_INVITES` is on: `sidebar/invites/notification { invite_id = "debug-<n>", scope_key = "<this world's scope root>:debug-hub-<n>", sender_login = "you (debug)", message = "Debug invite to a fresh hub world" }`. It is in no list, so it is never dismissed by the reconcile. This mod answers it itself: accept drops the portal at once, with no request to root and no load; decline says "Invite declined".

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ ["sidebar/invites"] = {} })
```

## Notes

- Only the card's own requests count: an answer is read off a request under the carrier's hold, with neither `RequestFrom` nor `WorldMirror`; a load is read only off a child of the carrier. A load another world shares arrives as a root, so it drops nothing.
- Once root claims a load, the asker's copy is a mirror of root's, and despawning it there doesn't reach root: root keeps its load, and the observed world, until another ask for that scope replaces it.
- The scope's canonical form is not checked here: core's parser is not a library mod's to require. The scope is the Site's, through root, and the server's approval checks it.
- A reload takes the cards' content and may take the cards (a card handed to the overlay stays); the carrier's new edge redraws or respawns each once. Holds, requests and loads outlive it.
- Taking `sidebar/invites` off an entity that stays while a hold runs: the hold goes as a part of this mod, and `cooldown`'s next tick of it can log Bevy's warning about a missing entity.
- `test_invites.lua` runs headless with `world_id` set off root's, so root's mods answer nothing and the suite writes every reply, load status and net confirmation itself.
