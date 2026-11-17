---
depends_on: [sidebar, sidebar/panel, ui/style]
conflicts_with: []
exposes: [sidebar/menu, sidebar/menu/state, sidebar/menu/button, sidebar/menu/view, sidebar/menu/list, sidebar/menu/item]
---

# sidebar/menu

A sidebar panel holding a list of items that other mods put in it: an action, such as Respawn, or a toggle, such as Flight. Each mod spawns its own items into the list when the list appears, and observes its own items' clicks; the menu names none of them. The menu gives each item its button and its label, and keeps the list in `order`.

## Components

- `sidebar/menu = {}` on the local player, beside `sidebar`. `player/client` adds and removes it.
- `sidebar/menu/state = { open }` on the carrier, added by this mod when the carrier arrives, if it has none: whether the panel is open, which a reload keeps. It goes with the carrier, and with `sidebar`, as a part of that name.
- `sidebar/menu/button`: marks this mod's `sidebar/button` (`icon = "icons/settings.png"`, `title = "Menu"`, `order = 5`), in the bar.
- `sidebar/menu/view`: on the panel, a plain `sidebar/panel` (`width = 240`, `title = "Menu"`) in the container, there only while the panel is open.
- `sidebar/menu/list`: the list, a column in the panel's `sidebar/panel/scroll`. A new one comes each time the panel opens, this mod reloads, or `sidebar/panel` builds its scroll area again.
- `sidebar/menu/item = { title, order, on }`: an item, spawned into the list by the mod that owns it, beside a marker of that mod's own. Missing `title` ("") and `order` (0) get defaults; `on` has none.
  - The menu gives it `Button`, `Node`, `ui/style` (`row_bg`, `row_hover` while hovered, text `text`), `Text` and `TextFont`: the item is its own label.
  - The label is `title`, and for a toggle (`on` is `true` or `false`) `<title>: On` or `<title>: Off`. The owner writes `on`; the menu rewrites the label on the item's `changed` edge.
  - Items go with the panel: closing it, or a reload of this mod, despawns them with the list. The state an item shows lives with its owner, so a new list gets fresh items.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `sidebar/menu` | Give a new carrier its state, if it has none, and give it a new one if `sidebar` going took it |
| Update | `sidebar/menu` | On a new bar or a new local carrier, spawn the button in the bar, if there is none. A run condition over those edges skips it otherwise |
| Update | `sidebar/menu` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update | `sidebar/menu` | When the button is opened, spawn the panel in the container and save it open |
| Update | `sidebar/menu` | When a button still here is closed, despawn the panel and save it closed |
| Update | `sidebar/menu` | On a new scroll area inside the panel, spawn the list in it |
| Update | `sidebar/menu` | On a changed item, `added` included: give a new one its button and label, rewrite a changed one's label, and put each list holding a changed item back in `order` (`Children`) |

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):insert_if_new({ sidebar = {}, ["sidebar/menu"] = {} })

-- an owning mod, for a local player with its own carrier: on a new list, and on its carrier
-- arriving, spawn its item into each list that holds none of its items, and observe the click
Query[{ added = { "sidebar/menu/list" } }]
-- commands:spawn({
--     ["sidebar/menu/item"] = { title = "Flight", order = 2, on = false },
--     ["<mod>/item"] = {},
--     ChildOf = list:id(),
-- }):observe(On[Pointer[Click]], { ... }, function(event, ...) ... end)

-- a toggle's state changed: write `on` on its own items, and the menu rewrites the label
Query[{ with = { "<mod>/item", Mut["sidebar/menu/item"] } }]
-- item:get_mut("sidebar/menu/item").on = state
```

## Notes

- A click on an item is its owner's, in the owner's `Pointer<Click>` observer on its own item. The menu reacts to no click on an item.
- An owner spawns into a list holding none of its items, on the list's `added` edge and on its own carrier's: a reload of the owner takes its items and spawns new ones in the open list.
- A reload keeps the panel. A reload of this mod takes everything it spawned, the button with its `sidebar/button/open`, the panel and the list with the items in it, and the state on the carrier stays: the new button opens again by the path a click takes, and the owners fill the new list.
- Only a button still here closing saves `open = false`: someone closed it, by a click, by Escape or by closing the sidebar. A reload's despawn brings the same `removed` edge, and saves nothing.
- Suites: `test_menu.lua` runs windowed (layout and Interaction need a window), with a stand-in mod that spawns two items into each new list and observes its toggle's click. `player/respawn` and `movement/fly` click their items headless in their own suites.
