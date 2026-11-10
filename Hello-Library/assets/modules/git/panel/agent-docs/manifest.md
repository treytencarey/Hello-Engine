---
depends_on: [sidebar, sidebar/panel, ui/style, vault/github, core/world/flip, git/world/head, placement, scope/portal, core/net]
conflicts_with: []
exposes: [git/panel, git/panel/state, git/panel/button, git/panel/view, git/panel/row, git/panel/request, git/panel/response]
---

# git/panel

A sidebar panel, "GitHub", 280 px wide: the player's GitHub repositories and a repository's branches, with Switch to move to a branch's world, Portal to ask the world's server for a portal to it, Pull on this world's own branch, and the chosen branch's latest commits. Root holds the GitHub token and makes every GitHub call (`vault/github`); the panel asks root and shows only what root answers.

Two halves. The client half (`client/init.lua`) is the panel: its UI, its asks of root, and the owner's asks of the world's server, written on a request slot. The server half (`server/init.lua`) builds no UI: it gives the slot its sync, answers the owner's asks, and opens the portals they ask for. The world's server does the deciding for the portal and the pull.

The panel's button is in the bar only while the player is signed in to GitHub (root's reply to the panel's sign-in ask names a `login`). Until root has answered, the button stays as it was. Signing out takes the button and closes the panel, saving it closed. The sign-in itself is the Accounts panel's (`sidebar/profile`). If the panel ever renders while signed out, it shows only "Sign in to GitHub in Accounts".

## Components

- `git/panel = {}` on the player, on the world's server. `player/server` adds and removes it. It syncs from the server to the owner alone (the server half's return declares `{ authority = "server", target = "owner" }`), so only the owner's client has the panel, and only on its own player.
- `git/panel/request = { op = "portal" | "drop_portal", target_sk }`: the owner's ask of the world's server, on the carrier. The owner's client writes it and only the owner's connection carries it (`{ authority = "client", target = "owner" }`). `target_sk` is the scope key of the world the portal is to lead to. `{}` is the ask taken back. `portal` is the panel's ask, a portal to place; `drop_portal` is `sidebar/invites`' ask for an accepted invite's portal, which stands 3 m ahead, placed.
- `git/panel/response = { op, scope, status, message }`: the server's answer, `op` the op it answers, on the carrier, synced to the owner alone (`{ authority = "server", target = "owner" }`). `scope` is the target asked for, `status` is `"opened"` or `"failed"`, and `message` says why it failed: `"not a scope key"`, `"this world's own scope"` or `"8 portals already"`. It stands until the owner takes its ask back, and is then `{}`.
- `git/panel/state = { open, repo, branch }` on the owner's carrier, client only, added by the client half when the carrier arrives, if it has none. `open`: whether the panel is open, kept through a reload. `repo`: the chosen repository, the string `"<owner>/<name>"` as GitHub spells it (`git/collaborators` reads it). `branch`: the chosen branch. It goes with the carrier, and with `git/panel`.
- `git/panel/button`: marks the client half's `sidebar/button` (`title = "GitHub"`, `order = 3`), in the bar, only while the player is signed in to GitHub.
- `git/panel/view`: on the panel, a plain `sidebar/panel` in the container, there only while the panel is open.
- `git/panel/row`: marks each top-level row in the panel's scroll area, in this order: the REPOSITORY picker, the BRANCH picker, the actions (Switch, Pull, Portal), the portal refusal line, the RECENT COMMITS header and one row per commit; or the one signed-out line.

The client half's asks of root are root's requests, children of the carrier, opened with `["core/script/owner"] = false` so they outlive a reload, and carrying nothing of this mod's:

- standing: `{ ["vault/github/repos"] = {}, Request = {} }`, opened when the carrier arrives, with `{ ["vault/github/signin"] = {}, Request = {} }` as its child. The sign-in ask hangs under the repositories ask, not the carrier, because a standing `vault/github/signin` among the carrier's children is `sidebar/profile`'s;
- `{ ["vault/github/branches"] = { owner, name }, Request = {} }` for the chosen repository;
- `{ ["vault/github/commits"] = { owner, name, branch }, Request = {} }` for the chosen branch.

What a click spawns is the player's, not the panel's, with `["core/script/owner"] = false`, and stays when the panel closes or `git/panel` goes:

- Switch: core's flip ask, `{ ["core/world/flip"] = { scope = <target> }, WorldShared = {}, ["core/net/sync"] = false }`. It crosses VMs to root, never the wire.
- Pull: `{ ["git/world/head/pull"] = { sha = <this world's git/world/head.sha> } }`, which the world's server takes (`git/world/head`).

Portal writes the slot instead: `git/panel/request = { op = "portal", target_sk = <target> }` on the carrier.

The target is the chosen repository's canonical key, `github:<owner>/<name>:<branch>`, with the owner and the name lowercased and the branch as it is: git branches are case-sensitive. Never a short form, which core would read as a subpath of the engine's repository.

## The portal the server opens

On an ask with `op = "portal"` or `"drop_portal"`, the server checks only that `target_sk` is a string, not empty, at most 512 bytes, and not this world's own scope (`scope_key` of this world's own `core/world/status`, with `WorldShared` and without `WorldMirror`), and that the owner holds fewer than 8 portals here (counted by query over `scope/portal` with `core/net/owner`, with the ones this run opened). No library mod checks that a scope key is canonical: root canonicalizes the target when a client's view observes it, and a target root refuses ends as a locked portal with root's reason (`scope/portal/view`).

A refused ask is answered `failed` with its reason and opens nothing. An accepted one is answered `opened`, with the op it answers. For `portal` the server spawns, for everyone to see and the owner to place:

```lua
{
    ["scope/portal"] = { target = <target_sk> },
    ["scope/portal/view"] = { mode = "3d" },
    placement = {},
    Transform = { translation = <3 m ahead of the carrier, as for drop_portal below> },
    ["core/net/owner"] = { client_id = <the asker> },
    ["core/net/sync"] = {
        placement = { authority = "client" },
        Transform = { authority = "client", reliable = false },
        ["scope/portal"] = { authority = "server" },
        ["scope/portal/view"] = { authority = "server" },
        ["scope/portal/hosted"] = { authority = "server" },
    },
    ["core/script/owner"] = false,
}
```

The owner's client marks it `core/net/local` and places it (`placement`); confirming hands its `Transform` back to the server.

It starts 3 m ahead, not at the carrier, so it is in view before the pointer moves it, and a portal placed where it started holds nobody who asked for it. For `drop_portal` the server spawns the same portal with no `placement`, already placed, at that same point, 3 m ahead of the carrier on the ground plane (the carrier's translation plus 3 times the x and z of its rotation applied to +Z, Bevy's `back()`, as v0.7.0 did; the height kept), with `Transform` synced from the server (`{ authority = "server" }`) and no `placement` sync.

Either portal is the world's, not the panel's: closing the panel, taking `git/panel` off or reloading either half keeps it.

The slot is a handshake. The client half takes its ask back (`git/panel/request = {}`) when an answer with an `op` lands, so the next ask is a change even when it asks the same; the server then takes its answer back (`git/panel/response = {}`). An ask that the standing answer already answers (same `op`, `scope` equal to `target_sk`) is not answered again: a reload of the server half runs it over every standing ask. An ask with the other op is answered, so `sidebar/invites`' ask is never taken for the panel's. While an answer stands on the client, a Portal click asks nothing, so an ask for the same target never meets the answer to the last one.

## The rows

- **REPOSITORY:** root's repositories, the one root marks `is_base` (the repository root launched from) first, the rest in GitHub's order (most recently updated first). The button shows the chosen repository's name, or "(none)", and "▼" shut or "▲" open. The open list is 180 px tall at most and scrolls 20 px per wheel step, without scrolling the panel. The chosen option is highlighted and has no click.
- **BRANCH:** the chosen repository's branches, the same way.
- Opening one picker closes the other. Choosing an option closes its picker.
- **Defaults:** with no repository chosen, the first listed is chosen (so the base one when root names it). With no branch chosen, the first listed, even when this world's own branch is listed too.
- **Choosing a repository** clears the branch: its branches ask and the commits ask close, and its own branches are asked. **Choosing a branch** closes the commits ask and asks that branch's.
- **Switch** ("↗ Switch") spawns the flip ask for the target, and asks the target's commits again. Its label follows the flip asks naming the target: "⏳ Switching…" while one is resolving, loading or promoting; "⚠ <reason> — retry" after one failed, and a click is the retry (root's driver retires the failed ask); "● Current" when the target is this world's own scope (`core/world/status.scope_key` of this world's own row), never before the world has switched. Current has no click.
- **Pull** ("⭳ Pull") is offered only on this world's own branch. It reads "⏳ Pulling…", with no click, while a `git/world/head/pull` ask is out in this world.
- **Portal** ("🌀 Portal") asks the server for a portal to any repository listed. On this world's own scope it is dimmed and has no click.
- **The portal refusal line:** "⚠ portal refused: <reason>" while a portal in this world naming the target carries `scope/portal/locked { reason }`; it goes when the lock does.
- **RECENT COMMITS:** root answers the latest 10; the panel shows 8, each the short sha in the accent colour and the message's first line, cut to 30 characters (27 and "..."), rows alternating colours.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First (server) | `git/panel/server` | On `git/panel` added to a carrier whose `core/net/sync` is a table: add the slot's and the answer's sync entries |
| First (server) | `git/panel/server` | When `git/panel` is removed from a carrier that stays: take those two entries off its sync |
| Update (server) | `git/panel/server` | On a changed `git/panel/request` on a carrier with `core/net/owner` (not a `WorldMirror` or peer mirror): an ask taken back takes a standing answer back; a portal ask not already answered is checked, answered, and opens its portal when it passes |
| First (client) | `git/panel` | Give a new carrier its state, if it has none, and its standing repositories ask, if it has none |
| First (client) | `git/panel` | When `git/panel` is removed from an entity that stays, close its asks |
| Update (client) | `git/panel` | On a changed `git/panel/response` with an `op` on the local carrier: take the ask back |
| Update (client) | `git/panel` | On the state or a repositories or branches reply changing: choose the defaults, and keep one branches ask for the chosen repository and one commits ask for the chosen branch, closing the others |
| Update (client) | `git/panel` | On a sign-in reply under the panel's repositories ask changing: ask again what root answered the other way (an error while now signed in, an answer while now signed out) |
| Update (client) | `git/panel` | On a new bar, a new local carrier or a sign-in reply changing: while signed in, spawn the button in the bar if there is none; signed out, despawn the button and the panel and save it closed; with no reply yet, nothing |
| Update (client) | `git/panel` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update (client) | `git/panel` | When the button is opened, spawn the panel in the container and save it open |
| Update (client) | `git/panel` | When a button still here is closed, despawn the panel and save it closed |
| Update (client), after `git/panel` | `git/panel/render` | Build the rows, again only when what they say changes. A run condition skips it while the panel is closed, and runs it on a new scroll area, the state, an ask or a reply, a flip ask, this world's status row, a pull ask or a portal lock changing |

Clicks are `On[Pointer[Click]]` observers on the rows' buttons. A picker's open state lives on its list (`Node.display`) and its arrow, so a click opens or closes it without a rebuild, and a rebuild reads the arrow back and keeps it as it was.

## Use

```lua
-- the player's server half, for each player
commands:entity(player):insert_if_new({ ["git/panel"] = {} })

-- another mod asking for a portal on the owner's client: on the local player, which carries git/panel
commands:entity(player):insert({ ["git/panel/request"] = { op = "drop_portal", target_sk = scope } })
```

## Notes

- Root answers each ask once. Signing in or out, in the Accounts panel or anywhere, changes the panel's sign-in reply; the panel then replaces each of its asks whose answer was given the other way, so a first sign-in fills the pickers.
- The asks outlive a reload of the client half, and a reload opens no second standing ask. A reload keeps the panel open with its choices, as `sidebar/profile` does; the button and the panel are this mod's spawns and come back. An open picker closes on a reload.
- The server, not the panel, checks a portal: its target, this world's own scope, and how many portals the player holds. The panel needs no parser.
- A pull's outcome is not shown: `git/world/head/pull` is answered only by the world's commit moving, and the server's pull reply reaches no client.
- The old panel's sessions list and its despawn button are not in this build. Their rows would go between the actions and the commits.
- A value written on the slot before its sync entry reaches the client is never sent. The server adds the entry as the player is set up, long before a click.
- Two mods writing the slot in one frame keep only the last ask.
- Suites: `tests/test_panel.lua`, the client half, headless, posing as a client world (`world_id = 7`) on `github:zzpanel/world:main`, with root's replies, the flip ask's statuses and the server's answers stubbed, driven by real clicks, and a wheel step on an open picker's list with its layout stood in (a headless trigger does not bubble from an option row, and the stop of propagation needs a window, so neither is checked); `tests/test_panel_server.lua`, the server half, headless, with the owner's asks written as the net delivers them; `tests/test_panel_net.lua`, over a real connection with two clients and real players.
