---
depends_on: [sidebar, sidebar/panel, ui/style, player]
conflicts_with: []
exposes: [sidebar/people, sidebar/people/state, sidebar/people/button, sidebar/people/view, sidebar/people/row, sidebar/people/row/player, sidebar/people/row/players, sidebar/people/row/item]
---

# sidebar/people

A sidebar panel, "People", listing who is online in this world: one row per player replicated here. Other mods add items to a row, a button or a text, and observe their own buttons' clicks; the panel lays them out and never learns what one does. Local UI: never synced.

## Components

- `sidebar/people = {}` on the local player, beside `sidebar`. The player's client half adds and removes it.
- `sidebar/people/state = { open }` on the carrier, added by this mod when the carrier arrives, if it has none: whether the panel is open, which a reload keeps. It goes with the carrier, and with `sidebar`, as a part of that name.
- `sidebar/people/button`: marks this mod's `sidebar/button` (`icon = "icons/friends.png"`, `title = "People"`, `order = 6`), in the bar.
- `sidebar/people/view`: on the panel, a `sidebar/panel` (`width = 280`, `title = "People"`) in the container, there only while the panel is open.
- `sidebar/people/row`: a row in the panel's scroll area, one per player in this world (`player` or `player/2d`, neither a `WorldMirror` nor a peer mirror, `core/net/peer/mirror`). Built while the panel is open: a new scroll area gets a row for every player, and a player arriving gets one. It shows the player's `name`, else its `user_id`, else `Player <client_id>` (an anonymous join), and follows them on the player's `changed` edge.
- `sidebar/people/row/player = { entity }`: on each row, a relationship to its player's replica, declared in this mod's return value: `relationships = { ["sidebar/people/row/player"] = { target = "sidebar/people/row/players", linked_spawn = true } }`. A player that despawns takes its rows.
- `sidebar/people/row/players`: on a player, its rows, kept by the engine. Mods read it and never write it.
- `sidebar/people/row/item = { order, label, button, enabled }`: an item, spawned as a child of a row by the mod that owns it, beside a marker of that mod's own. Defaults: `order = 0`, `label = ""`, `button = false`, `enabled = true`.
  - The panel lays items out after the row's name, in `order`, again whenever an item changes.
  - A `button` item gets `Button`, `Node`, `BorderRadius`, `ui/style` (`icon_bg`, `hover = "icon_hover"`, `press = "icon_active"`, text `text`), `Text` and `TextFont`: the item is its own label. With `enabled = false` it is dimmed (`row_alt`, text `text_dim`, no hover or press).
  - Any other item gets `Node`, `ui/style` (text `text`, or `text_dim` with `enabled = false`), `Text` and `TextFont`.
  - The owner writes `label` and `enabled`; the panel redraws the item on its `changed` edge. `button` is read when the item is first drawn.
  - Taken off an entity that stays, the panel takes off what it added.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `sidebar/people` | Give a new carrier its state, if it has none, and give it a new one if `sidebar` going took it |
| Update | `sidebar/people` | On a new bar or a new local carrier, spawn the button in the bar, if there is none |
| Update | `sidebar/people` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update | `sidebar/people` | When the button is opened, spawn the panel in the container and save it open |
| Update | `sidebar/people` | When a button still here is closed, despawn the panel, with its rows and their items, and save it closed |
| Update | `sidebar/people` | While the panel is open, on a new scroll area inside it, spawn a row for every player; on a player arriving, spawn its row. A player with a row already gets none |
| Update | `sidebar/people` | On a changed `player` or `player/2d` with rows, rewrite their names |
| Update | `sidebar/people` | When `player` or `player/2d` is taken off an entity that stays, despawn its rows |
| Update | `sidebar/people` | On a changed item, `added` included: draw a new one, redraw a changed one, and put each row holding a changed item back in order |
| Update | `sidebar/people` | When `sidebar/people/row/item` is taken off an entity that stays, take off what the panel added |

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ sidebar = {}, ["sidebar/people"] = {} })

-- a contributing mod: on a new row, find its player and add items
Query[{ added = { "sidebar/people/row" }, with = { "sidebar/people/row/player" } }]
-- local link = row:get("sidebar/people/row/player")
-- local player = participants:get(link.entity)      (a declared query of the mod's own)
-- commands:spawn({
--     ["sidebar/people/row/item"] = { order = 1, label = "Mute", button = true },
--     ["<mod>/item"] = {},
--     ChildOf = row:id(),
-- }):observe(On[Pointer[Click]], { ... }, function(event, ...) ... end)

-- its own state changed: write `label` or `enabled` on its own items
Query[{ with = { "<mod>/item", Mut["sidebar/people/row/item"] } }]
-- item:get_mut("sidebar/people/row/item").label = "Unmute"

-- or, from a player, its rows
Query[{ with = { "sidebar/people/row/players" } }]
```

## Notes

- A click on an item is its owner's, in the owner's `Pointer<Click>` observer on its own item. The panel reacts to no click on an item, and a dimmed button still reaches its owner's observer: the owner reads its own state, as it wrote `enabled` from it.
- Rows go when the panel closes or rebuilds (a reload of this mod, or `sidebar/panel` building its scroll area again), and their items go with them. A new row is a new `added` edge, so an owner adds its items again; the state an item shows lives with its owner.
- A reload keeps the panel open: it takes the button, the panel and the rows, the state on the carrier stays, and the new button opens again by the path a click takes.
- The local player's own row targets the local player, so `sidebar/people/row/players` can sit on the carrier. Taking `sidebar/people` or `sidebar` off it then logs one warning: the registry tries to remove that target, which only the engine writes, and is refused.
- Who a player is reaches a client on the replica: `player.name` and `player.user_id`, which the server copies from `core/player/attest` (`player/2d.user_id` for a 2D player, which has no `name`).
- Suites: `test_people.lua` runs headless, with stand-in players and a stand-in contributor that adds a text and two buttons to each new row and observes its button's click.
