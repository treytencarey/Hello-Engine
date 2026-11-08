---
depends_on: [sidebar, sidebar/panel, ui/style, core/player/session, vault/github]
conflicts_with: []
exposes: [sidebar/profile, sidebar/profile/state, sidebar/profile/button, sidebar/profile/view, sidebar/profile/row]
---

# sidebar/profile

A sidebar panel, "Accounts", for the player's two sign-ins: Hello! (the Site) and GitHub. Root runs both sign-ins and keeps the tokens. The panel asks root and shows only what root answers: the name while signed in, with Sign out; the code and the address to enter it at while a sign-in waits for the player; otherwise Sign in, with the reason the last sign-in failed. GitHub's row shows only while root's Hello! reply names a `user`: a player not signed in to Hello! is offered only Hello!. A Hello! sign-out hides GitHub's row and asks root nothing about GitHub, so root keeps that session and the row comes back as it was on the next Hello! sign-in. It opens no browser: the player opens the address.

## Components

- `sidebar/profile = {}` on the local player, beside `sidebar`. `player/client` adds and removes it.
- `sidebar/profile/state = { open }` on the carrier, added by this mod when the carrier arrives, if it has none: whether the panel is open, kept through a reload. It goes with the carrier, and with `sidebar`, as a part of that name.
- `sidebar/profile/button`: marks this mod's `sidebar/button`, in the bar.
- `sidebar/profile/view`: on the panel, a plain `sidebar/panel` in the container, there only while the panel is open.
- `sidebar/profile/row`: marks each row in the panel's scroll area: a header, then one row per sign-in shown.

The asks are root's requests, children of the carrier, and carry nothing of this mod's:

- standing, one per sign-in, opened when the carrier arrives: `{ ["core/player/session/signin"] = {}, Request = {} }` and `{ ["vault/github/signin"] = {}, Request = {} }`. Root's replies change with the sessions.
- a click: `{ ["core/player/session/signin"] = { start = true }, Request = {} }`, or `{ sign_out = true }`, and the same for `vault/github/signin`. A click closes the last one it made for that sign-in first, so at most one is open per sign-in.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `sidebar/profile/init` | Give a new carrier its state, if it has none, and its standing asks, if it has none; give it a new state if `sidebar` going took it |
| First | `sidebar/profile/removed` | When `sidebar/profile` is removed from an entity that stays, close its asks |
| Update | `sidebar/profile/add_button` | On a new bar or a new local carrier, spawn the button in the bar, if there is none |
| Update | `sidebar/profile/restore` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update | `sidebar/profile/open` | When the button is opened, spawn the panel in the container and save it open |
| Update | `sidebar/profile/close` | When a button still here is closed, despawn the panel and save it closed |
| Update, after `sidebar/profile/close` | `sidebar/profile/render` | Build the rows from root's replies, again only when what they say changes. A run condition skips it while the panel is closed, and runs it on a reply or an ask changing, a new scroll area, and twice a second |

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ sidebar = {}, ["sidebar/profile"] = {} })
```

## Notes

- Tokens never reach the panel's world: root answers with public facts only (`user = { id, name }`, `login`, `pending`, `user_code`, `verification_uri`, `error`), and the panel writes only the texts it shows. Its suite stubs a reply that also carries a token, and finds it on no other component.
- A pending sign-in shows on the ask that started it; who is signed in shows on the standing ask, and on the starting ask once root has signed in.
- A reply crosses from root, and an edge that crosses from another VM can be missed, so while the panel is open it compares what it shows with the replies twice a second, and rebuilds only on a difference.
- The asks outlive a reload of this mod (`core/script/owner = false`), so a sign-in waiting for the player goes on; a reload opens no second standing ask. A reload keeps the panel open, as `sidebar/profiler` does.
- No address is opened for the player: there is no approved way for a world to open one yet.
- `test_profile.lua` runs headless at root with no session held, so the replies are the suite's: it drives the panel with real clicks on the sidebar's button and the rows' buttons.
