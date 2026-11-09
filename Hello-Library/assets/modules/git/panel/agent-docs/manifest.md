---
depends_on: [sidebar, sidebar/panel, ui/style, vault/github, core/world/flip, git/world/head, placement, scope/portal]
conflicts_with: []
exposes: [git/panel, git/panel/state, git/panel/button, git/panel/view, git/panel/row]
---

# git/panel

A sidebar panel, "GitHub", 280 px wide: the player's GitHub repositories and a repository's branches, with Switch to move to a branch's world, Portal to drop a portal to it, Pull on this world's own branch, and the chosen branch's latest commits. Root holds the GitHub token and makes every GitHub call (`vault/github`); the panel asks root and shows only what root answers. Local UI, at root `init.lua`: nothing here is synced, and the world's server does the deciding for the portal and the pull.

The panel's button is in the bar only while the player is signed in to GitHub (root's reply to the panel's sign-in ask names a `login`). Until root has answered, the button stays as it was. Signing out takes the button and closes the panel, saving it closed. The sign-in itself is the Accounts panel's (`sidebar/profile`). If the panel ever renders while signed out, it shows only "Sign in to GitHub in Accounts".

## Components

- `git/panel = {}` on the local player, beside `sidebar`. `player/client` adds and removes it.
- `git/panel/state = { open, repo, branch }` on the carrier, added by this mod when the carrier arrives, if it has none. `open`: whether the panel is open, kept through a reload. `repo`: the chosen repository, `"<owner>/<name>"` as GitHub spells it. `branch`: the chosen branch. It goes with the carrier, and with `git/panel`.
- `git/panel/button`: marks this mod's `sidebar/button` (`title = "GitHub"`, `order = 3`), in the bar, only while the player is signed in to GitHub.
- `git/panel/view`: on the panel, a plain `sidebar/panel` in the container, there only while the panel is open.
- `git/panel/row`: marks each top-level row in the panel's scroll area, in this order: the REPOSITORY picker, the BRANCH picker, the actions (Switch, Pull, Portal), the portal refusal line, the RECENT COMMITS header and one row per commit; or the one signed-out line.

The asks are root's requests, children of the carrier, opened with `["core/script/owner"] = false` so they outlive a reload, and carrying nothing of this mod's:

- standing: `{ ["vault/github/repos"] = {}, Request = {} }`, opened when the carrier arrives, with `{ ["vault/github/signin"] = {}, Request = {} }` as its child. The sign-in ask hangs under the repositories ask, not the carrier, because a standing `vault/github/signin` among the carrier's children is `sidebar/profile`'s;
- `{ ["vault/github/branches"] = { owner, name }, Request = {} }` for the chosen repository;
- `{ ["vault/github/commits"] = { owner, name, branch }, Request = {} }` for the chosen branch.

What a click spawns is the player's, not the panel's, with `["core/script/owner"] = false`, and stays when the panel closes or `git/panel` goes:

- Switch: core's flip ask, `{ ["core/world/flip"] = { scope = <target> }, WorldShared = {}, ["core/net/sync"] = false }`. It crosses VMs to root, never the wire.
- Portal: a predicted portal for the player to place, approved or refused by the world's server (`scope/portal`):

  ```lua
  {
      placement = {},
      Transform = { translation = <the player's> },
      ["scope/portal"] = { target = <target> },
      ["scope/portal/view"] = { mode = "3d" },
      ["core/net/sync"] = {
          placement = { authority = "client" },
          Transform = { authority = "client", reliable = false },
          ["scope/portal"] = { authority = "server" },
          ["scope/portal/view"] = { authority = "server" },
          ["scope/portal/hosted"] = { authority = "server" },
      },
  }
  ```

- Pull: `{ ["git/world/head/pull"] = { sha = <this world's git/world/head.sha> } }`, which the world's server takes (`git/world/head`).

The target is the chosen repository's canonical key, `github:<owner>/<name>:<branch>`, with the owner and the name lowercased and the branch as it is, as core's canonical form has it. Never a short form, which core would read as a subpath of the engine's repository.

## The rows

- **REPOSITORY:** root's repositories, the one root marks `is_base` (the repository root launched from) first, the rest in GitHub's order (most recently updated first). The button shows the chosen repository's name, or "(none)", and "▼" shut or "▲" open. The open list is 180 px tall at most and scrolls 20 px per wheel step, without scrolling the panel. The chosen option is highlighted and has no click.
- **BRANCH:** the chosen repository's branches, the same way.
- Opening one picker closes the other. Choosing an option closes its picker.
- **Defaults:** with no repository chosen, the first listed is chosen (so the base one when root names it). With no branch chosen, the first listed, even when this world's own branch is listed too.
- **Choosing a repository** clears the branch: its branches ask and the commits ask close, and its own branches are asked. **Choosing a branch** closes the commits ask and asks that branch's.
- **Switch** ("↗ Switch") spawns the flip ask for the target, and asks the target's commits again. Its label follows the flip asks naming the target: "⏳ Switching…" while one is resolving, loading or promoting; "⚠ <reason> — retry" after one failed, and a click is the retry (root's driver retires the failed ask); "● Current" when the target is this world's own scope (`core/world/status.scope_key` of this world's own row), never before the world has switched. Current has no click.
- **Pull** ("⭳ Pull") is offered only on this world's own branch. It reads "⏳ Pulling…", with no click, while a `git/world/head/pull` ask is out in this world.
- **Portal** ("🌀 Portal") spawns the portal for any repository listed. On this world's own scope it is dimmed and has no click.
- **The portal refusal line:** "⚠ portal refused: <reason>" while a portal in this world naming the target carries `scope/portal/locked { reason }`; it goes when the lock does.
- **RECENT COMMITS:** root answers the latest 10; the panel shows 8, each the short sha in the accent colour and the message's first line, cut to 30 characters (27 and "..."), rows alternating colours.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `git/panel` | Give a new carrier its state, if it has none, and its standing repositories ask, if it has none |
| First | `git/panel` | When `git/panel` is removed from an entity that stays, close its asks |
| Update | `git/panel` | On the state or a repositories or branches reply changing: choose the defaults, and keep one branches ask for the chosen repository and one commits ask for the chosen branch, closing the others |
| Update | `git/panel` | On a sign-in reply under the panel's repositories ask changing: ask again what root answered the other way (an error while now signed in, an answer while now signed out) |
| Update | `git/panel` | On a new bar, a new local carrier or a sign-in reply changing: while signed in, spawn the button in the bar if there is none; signed out, despawn the button and the panel and save it closed; with no reply yet, nothing |
| Update | `git/panel` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update | `git/panel` | When the button is opened, spawn the panel in the container and save it open |
| Update | `git/panel` | When a button still here is closed, despawn the panel and save it closed |
| Update, after `git/panel` | `git/panel/render` | Build the rows, again only when what they say changes. A run condition skips it while the panel is closed, and runs it on a new scroll area, the state, an ask or a reply, a flip ask, this world's status row, a pull ask or a portal lock changing |

Clicks are `On[Pointer[Click]]` observers on the rows' buttons. A picker's open state lives on its list (`Node.display`) and its arrow, so a click opens or closes it without a rebuild, and a rebuild reads the arrow back and keeps it as it was.

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ sidebar = {}, ["git/panel"] = {} })
```

## Notes

- Root answers each ask once. Signing in or out, in the Accounts panel or anywhere, changes the panel's sign-in reply; the panel then replaces each of its asks whose answer was given the other way, so a first sign-in fills the pickers.
- The asks outlive a reload of this mod, and a reload opens no second standing ask. A reload keeps the panel open with its choices, as `sidebar/profile` does; the button and the panel are this mod's spawns and come back. An open picker closes on a reload.
- The world's server, not the panel, checks a portal: its target's form, this world's own scope, and how many portals the player holds (`scope/portal`). The panel needs no parser.
- A pull's outcome is not shown: `git/world/head/pull` is answered only by the world's commit moving, and the server's pull reply reaches no client.
- The old panel's sessions list and its despawn button are not in this build. Their rows would go between the actions and the commits.
- Suite: `tests/test_panel.lua`, headless, posing as a client world (`world_id = 7`) on `github:zzpanel/world:main`, with root's replies and the flip ask's statuses stubbed, driven by real clicks. The wheel and the stop of its propagation need a window and are not checked.
