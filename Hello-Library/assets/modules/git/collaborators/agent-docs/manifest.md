---
depends_on: [sidebar, sidebar/panel, ui/style, vault/github, core/registry, core/world]
conflicts_with: []
exposes: [git/collaborators, git/collaborators/state, git/collaborators/button, git/collaborators/view, git/collaborators/row]
---

# git/collaborators

A sidebar panel, "Collaborators", listing one repository's collaborators from GitHub, with an Invite button on each row that invites that person into this world. Root holds the GitHub and Hello! sessions and makes every call: the panel asks root and shows only what it answers. The repository is the one `git/panel` has chosen, else this world's own. Local UI: never synced.

`git/collaborators/authorize`, the write policy of a served world, is a sub-mod of its own in this folder and loads by its own component; nothing here touches it.

## Components

- `git/collaborators = {}` on the local player. The player's client half adds and removes it.
- `git/collaborators/state = { open }` on the carrier, added by this mod when the carrier arrives, if it has none: whether the panel is open, kept through a reload.
- `git/collaborators/button`: marks this mod's `sidebar/button` (`title = "Collaborators"`, `order = 4`), in the bar.
- `git/collaborators/view`: on the panel, a `sidebar/panel` (280 px) in the container, there only while the panel is open.
- `git/collaborators/row`: marks each row in the panel's scroll area.

The asks are root's requests and carry nothing of this mod's:
- the panel's, children of the view, so they close with it: `{ ["vault/github/signin"] = {}, Request = {} }` for the player's own `login`; `{ ["core/registry/invites"] = {}, Request = {} }` for whether the website answers; `{ ["vault/github/repos"] = { owner, name }, Request = {} }` for the listed repository, replaced when that repository changes. They are not the carrier's, because the player's other panels hold asks of the same shape there.
- a send, a child of the carrier, `core/script/owner = false`: `{ ["core/registry/invites/send"] = { scope = <this world's scope_key>, invitee = <login> }, Request = {} }`, replied `{ status = "requested" | "ok" | "refused", reason }`. A click closes the open send for that login first, so at most one is open per login.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `git/collaborators` | Give a new carrier its state, if it has none |
| First | `git/collaborators` | When `git/collaborators` is removed from an entity that stays, close its sends |
| Update | `git/collaborators` | On a new bar or a new local carrier, spawn the button in the bar, if there is none |
| Update | `git/collaborators` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update | `git/collaborators` | When the button is opened, spawn the panel in the container with its sign-in and invite-list asks, and save it open |
| Update | `git/collaborators` | When a button still here is closed, despawn the panel and save it closed |
| Update | `git/collaborators` | Keep the panel's repository ask on the listed repository: on the panel added, `git/panel/state` changed or removed, and this world's row changed |
| Update, after `git/collaborators` | `git/collaborators/render` | Rebuild the rows from the replies, on their edges (a reply, an ask, a send, `sidebar/invites/state`, `git/panel/state`, this world's row, a new scroll area), while the panel is open |

## What the panel shows

- **The repository:** `git/panel/state.repo { owner, name }` on the carrier when it has both, else this world's row's `scope_root`, `github:<owner>/<name>` (`core/world/status` without `WorldMirror`). With neither: "No repository selected." It is this world's own when owner and name match the row's, ignoring case.
- Signed out of GitHub (root's sign-in reply has no `login`): "Sign in to GitHub in Accounts". No reply yet: "Loading collaborators...". An `error`: "Error: <error>". None: "No collaborators found."
- Otherwise "COLLABORATORS (<n>)", then the status lines, then a row per collaborator:
  - a 28 px round avatar (`icon_active`) holding the login's first letter, upper case; an image would go inside it;
  - the login (12, `text`) and the role badge below it (9): `role`, or "collaborator", in `accent` for "admin", else `text_dim`;
  - rows alternate `row_bg` and `row_alt`, 40 px high;
  - an Invite button (58 x 24) after them, only on a list of this world's own repository, never on the player's own row (logins compared without case or a leading "@") or a row with no `github_id`. The row has room for more buttons after it.
- **Status lines,** each a row:
  - the website, from the invite list's reply: none yet, "Checking website..."; `error = "sign-in-required"`, "Sign in on the Profile panel to send invites"; any other `error`, "Website offline - invites unavailable"; no `error`, nothing;
  - with no `error`, the newest send's result (the last send among the carrier's children): "Inviting <login>..." until root answers `ok` or `refused`; "Invited <login>"; for `not-a-collaborator`, "Only collaborators of this world can invite"; for `sign-in-required`, "Sign in on the Profile panel to send invites"; otherwise "Invite failed: <reason>";
  - `sidebar/invites/state.feedback`, when the carrier has one: `accent` for `ok`, `text_bad` for `error`, else `text_dim`.
- An Invite button is enabled only with no `error` on the invite list and no open send for its login still waiting: otherwise it is dimmed (`row_alt`, `text_dim`) and does nothing.

## Debug invites

A file-local `DEBUG_INVITES` (off when committed) gives the player's own row a "Debug" button, enabled whatever the website says. Its click spawns a local invite card for `sidebar/invites` to answer, to a branch of this world's repository that doesn't exist yet: `{ ["sidebar/invites/notification"] = { invite_id = "debug-<n>", sender_login = "you (debug)", scope_key = "<scope_root>:debug-hub-<n>", message = "Debug invite to a fresh hub world" }, notification = {} }`, `<n>` the elapsed milliseconds. A self-invite can't be real: the Site refuses one.

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ ["git/collaborators"] = {} })
```

## Notes

- Root takes a send only into the asker's own repository, so a list of another repository has no Invite buttons.
- No token reaches the panel: root answers with public facts only. Its suite stubs a sign-in reply that carries a token and finds it on no other component.
- A reload keeps the panel open, as `sidebar/profile` does, and asks root again under the new panel; the sends outlive it.
- Not yet: avatar images (a world has no network of its own) and voice controls on the rows.
- `test_collaborators.lua` runs headless with `world_id` set off root's, so root's mods answer nothing and the suite writes every reply itself, with real clicks on the sidebar's button and the rows' buttons.
