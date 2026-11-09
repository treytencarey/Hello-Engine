---
depends_on: [notification, cooldown, ui/style, core/registry, core/world, scope/portal, git/panel]
conflicts_with: []
exposes: [sidebar/invites, sidebar/invites/state, sidebar/invites/notification, sidebar/invites/notification/row, sidebar/invites/request]
---

# sidebar/invites

The player's invites to other worlds, one card each, answered from the card. Root holds the player's Hello! session and makes every Site call: this mod asks root's `core/registry/invites` for the list and `core/registry/invites/answer` for each answer, and shows what root says. An accepted invite then has root load the host's world join-only, and asks this world's server for a portal to it on `git/panel`'s request slot; the server stands it 3 m ahead of the player. Sending invites is `git/collaborators`'s. Local UI: never synced, and it needs no open panel: the cards are `notification` toasts.

## Components

- `sidebar/invites = {}` on the local player, which carries it whether or not a panel is open. The player's client half adds and removes it.
- `sidebar/invites/state = { feedback, feedback_kind }` on the carrier, added by this mod when the carrier arrives, and again if taking `sidebar` off the player took it (a `sidebar/` part goes with `sidebar`). `feedback` is the last thing an answer, its world or its portal said; `feedback_kind` is `"ok"`, `"error"` or `"stale"`. Nothing here draws it: `git/collaborators` shows it under its send result.
- `sidebar/invites/notification = { invite_id, sender_login, scope_key, message }` on each card, beside `notification` (no `timeout`, so it stays until answered or withdrawn). `invite_id` is the invite's id in root's list, or `"debug-<n>"` for a debug invite; `sender_login` is root's `inviter`; `scope_key` its `scope`; `message` is `"wants you in <scope>"`.
- `sidebar/invites/notification/row`: marks each part of a card's content, its children.
- `sidebar/invites/request = { op, invite_id, scope_key }`:
  - on a hold, a child of the carrier, for each answer: `op` is `"accept"` or `"decline"`. A real answer's hold carries `cooldown = { ["sidebar/invites/request"] = { remaining = 30 } }`, so `cooldown` takes the component off after 30 s; root's request is the hold's child. A debug answer's hold has no timer and goes once handled.
  - on a record of a portal ask, `{ op = "drop_portal", scope_key }` with no `invite_id`, a child of the carrier (`core/script/owner = false`), from the ask until the server answers it.

Root's requests carry nothing of this mod's and outlive a reload of it (`core/script/owner = false`):
- the list, standing while the carrier is here: `{ ["core/registry/invites"] = {}, Request = {} }`, a child of the carrier. Its reply is `{ invites = { { id, scope, inviter, expires_at } }, error }`.
- an answer, a child of its hold: `{ ["core/registry/invites/answer"] = { id, action }, Request = {} }`, replied `{ status = "asking" | "ok" | "refused", scope, reason }`.
- the load of an accepted world, a child of the carrier: `{ ["core/world/load"] = { scope, join_only = true }, WorldShared = {}, ["core/net/sync"] = false }`. Root claims it and writes `status` (`"ready"` or `"failed"` with `reason`) on it.

The portal ask: `git/panel/request = { op = "drop_portal", target_sk = <scope> }` on the carrier, the slot `git/panel` gives the player, and cross-mod input through a sub-component. The server answers on `git/panel/response { op = "drop_portal", scope, status }` and spawns the portal itself, placed, 3 m ahead of the player (`git/panel`); it reaches this client as the player's own (`core/net/local`, `core/net/owner`). The carrier must carry `git/panel`.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `sidebar/invites` | A new carrier gets its state, if it has none, and its standing list request, if it has none; the state comes back if `sidebar` going took it |
| First | `sidebar/invites` | When `sidebar/invites` is removed from an entity that stays, close its list request and its load requests, and every hold whose timer ended (a running hold goes as a part of the mod) |
| Update | `sidebar/invites` | Reconcile the cards with root's list: one card per listed invite that has no card and no running hold; a card whose invite left the list (not a debug card) gets `notification.dismiss = true`. Runs on a list reply, a hold ending, a card going, and a carrier arriving |
| Update, after `sidebar/invites` | `sidebar/invites/render` | Draw a card's content when it is added or changed, and every card when a carrier arrives (a reload) |
| Update | `sidebar/invites` | On an answer's reply turning `ok` or `refused`: say the outcome; for an accepted `ok`, spawn the join-only load for the reply's `scope` (else the hold's `scope_key`) unless the carrier already has one for it; despawn the hold, with its request, if its timer has ended |
| Update | `sidebar/invites` | When a hold's timer ends, despawn it, with its request, if root has answered |
| Update | `sidebar/invites` | On a carrier's load turning `ready`, or a debug accept, ask for the portal after the checks below, and spawn the ask's record; on `failed`, say why and despawn the load |
| Update | `sidebar/invites` | On a changed `git/panel/response` answering one of the carrier's records (`op = "drop_portal"`, `scope` equal to the record's `scope_key`): `opened` says "Portal opened - walk through to join"; anything else says "You have too many portals open" and despawns the carrier's load for that scope; the record goes either way |
| Update | `sidebar/invites` | A portal going despawns the carrier's load for its target when no other portal of this player names it |

## What the card says and does

- "INVITE" (size 9, `accent`), "<sender> invited you" (12, `text`; "someone" with no sender), the scope (10, `text_dim`), the message (10, `text_dim`), then a row of Accept (`icon_active`) and Decline (`icon_bg`), each 26 px high with `row_hover` on hover.
- A click on either sets the card's `notification.dismiss` at once and spawns the hold with root's answer under it. A click on a card already fading does nothing, except on a debug card: "That invite no longer exists".
- While a hold runs, its invite gets no card, though root's list (asked every 20 s) still names it. When the timer ends and the list still names the invite, the card comes back.

## What follows an answer

- `ok`, decline: "Invite declined". `refused`: "Invite <action> failed: <reason>", or "Sign in to answer invites" for `sign-in-required`. Accept: "Opening a door to <scope>".
- The load answers on its own entity. `failed` with `not-running` or `no-gateway`: "That world has ended" (`stale`); any other reason: "Could not open that world: <reason>". The load goes either way.
- `ready`: the portal is asked for. Before it is, the client checks what the server will, and says:
  - no row of this world's own (`core/world/status` without `WorldMirror`), or a carrier without `git/panel`: "No active scope to place a portal in";
  - the target is this world's `scope_key`: "You are already in that world";
  - the player already has 8 portals here (counted over `scope/portal` entities that are `core/net/local` or owned by the carrier's `core/net/owner.client_id`): "You have too many portals open".
  A refused drop also despawns the carrier's load for that scope. A target the player already has a portal to, or an ask out for, asks nothing more; a second `ready` asks nothing.
- The server refusing the ask says "You have too many portals open": the other checks passed here.
- The load stays while a portal of this player's names its world, so the observed world is not let go between the load and the portal's own view.

## Debug invites

A debug card is spawned by `git/collaborators` when its `DEBUG_INVITES` is on: `sidebar/invites/notification { invite_id = "debug-<n>", scope_key = "<this world's scope root>:debug-hub-<n>", sender_login = "you (debug)", message = "Debug invite to a fresh hub world" }`. It is in no list, so it is never dismissed by the reconcile. This mod answers it itself: accept asks for the portal at once, with no request to root and no load; decline says "Invite declined".

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ ["sidebar/invites"] = {} })
```

## Notes

- Only the card's own requests count: an answer is read off a request under the carrier's hold, with neither `RequestFrom` nor `WorldMirror`; a load is read only off a child of the carrier. A load another world shares arrives as a root, so it drops nothing.
- Once root claims a load, the asker's copy is a mirror of root's, and despawning it there doesn't reach root: root keeps its load, and the observed world, until another ask for that scope replaces it.
- The scope's canonical form is checked by no library mod: root canonicalizes it when the portal's view observes it, and a scope root cannot take ends as a locked portal with root's reason.
- The ask's op is not the panel's (`portal`), so an answer the panel's ask left standing never stands for it.
- A record whose ask the server never answers stays until `sidebar/invites` goes, and asks for that scope wait on it.
- A reload takes the cards' content and may take the cards (a card handed to the overlay stays); the carrier's new edge redraws or respawns each once. Holds, requests and loads outlive it.
- Taking `sidebar/invites` off an entity that stays while a hold runs: the hold goes as a part of this mod, and `cooldown`'s next tick of it can log Bevy's warning about a missing entity.
- `test_invites.lua` runs headless with `world_id` set off root's, so root's mods answer nothing and the suite writes every reply, load status and server answer itself, and spawns the portal the server would.
