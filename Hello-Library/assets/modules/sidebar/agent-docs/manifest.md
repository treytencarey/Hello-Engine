---
depends_on: [input, ui/style]
conflicts_with: []
exposes: [sidebar, sidebar/open, sidebar/button, sidebar/button/open, sidebar/container, sidebar/bar]
---

# sidebar

An icon bar at the left edge of the screen, one icon per `sidebar/button`, and the panels those buttons open beside it. Escape opens it; while it is open, Escape closes the newest open panel, or the sidebar itself when none is open. Opening gives the player the cursor and UI input; closing gives game input back and closes every panel. Only the local player's sidebar is drawn.

Panel mods extend it without the sidebar naming them: the client adds the panels its player has (`["sidebar/profiler"] = {}` beside `sidebar = {}`; a panel with server work is added and synced by the server, to its owner only), each panel mod spawns its own button into the bar, and the sidebar makes it an icon. The panel mod opens its panel while the button carries `sidebar/button/open`. Everything in the container goes with it: a reload of `sidebar`, or removing it, takes the buttons and panels, and a new bar gets new buttons.

## Components

- `sidebar = {}` on the local player, added by the client itself (the player's client half). Never synced: the sidebar is local UI.
- `sidebar/open = {}` on the player while the sidebar is open. Added and removed by `sidebar`.
- `sidebar/button = { icon, title, order }`: a button, spawned by a panel mod into the bar. The sidebar gives it `Node`, `Button`, `BorderRadius` and `ui/style` and keeps the bar in `order`; until icons draw images, the icon shows the title's first letter.
- `sidebar/button/open = { order }` on a button while its panel is open; `order` is one above the highest among the open buttons when it opened, so Escape closes the newest. Added and removed by `sidebar` (a click, Escape, closing the sidebar). A panel mod reacts to its `added` and `removed` edges on its own button.
- `sidebar/container`, `sidebar/bar`: the sidebar's own UI, one of each, found with `limit = 1`. The container is a UI root; panels go inside it, beside the bar.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First | SidebarSetup | For the local player, bind Escape in `input/game` and `input/ui` (again when `input` is added back), and build the container and bar, hidden unless the sidebar is open already (a reload) |
| First | SidebarAway | When the player leaves for another world, close the sidebar |
| First | SidebarRemoved | When `sidebar` is removed, despawn the container with everything in it, and unbind |
| Update | SidebarToggle | Escape in game input opens the sidebar; in UI input it closes the newest open panel, or the sidebar |
| Update, after `SidebarToggle` | SidebarShow | On opening: show the container, UI input with the cursor |
| Update, after `SidebarToggle` | SidebarHide | On closing: hide, game input, close every panel |
| Update | SidebarIcons | A new button becomes an icon: style, click observer, letter |
| Update | SidebarOrder | When a button comes, put the bar's icons in `order` (`Children`) |
| Update | SidebarIconOpen, SidebarIconClosed | An icon is drawn active while its panel is open |

## Use

```lua
-- the player's client half, for its local player
player:patch({ sidebar = {}, ["sidebar/profiler"] = {} })

-- a panel mod: its button in the bar, for a local player with the panel. Both edges: a new
-- bar (the sidebar built or reloaded), and the panel itself (added, or this mod reloaded)
world:query({ added = { "sidebar/bar" } })
world:query({ added = { "sidebar/profiler" }, with = { "core/net/local" } })
-- local bar = world:query({ with = { "sidebar/bar" }, limit = 1 })[1]
-- spawn({ ["sidebar/button"] = { title = "Profiler", order = 1 }, ["sidebar/profiler/button"] = {} })
--     :with_parent(bar:id())

world:query({ added = { "sidebar/button/open" }, with = { "sidebar/profiler/button" } })
-- local container = world:query({ with = { "sidebar/container" }, limit = 1 })[1]
-- spawn({ ["sidebar/panel"] = { width = 320 }, ["sidebar/profiler/view"] = {} }):with_parent(container:id())
world:query({ removed = { "sidebar/button/open" }, with = { "sidebar/profiler/button" } })
-- despawn the entity marked sidebar/profiler/view
```

## Notes

- A click on an icon opens or closes its button's panel in the button's `Pointer<Click>` observer. A suite clicks with `button:invoke_observer("Pointer<Click>", {})`.
- A key held through a mode switch waits for its release (`input`), so the Escape that opens the sidebar does not also close it.
- The container is a UI root of its own: a UI node under the player would not be laid out.
- Layout and clicks need a window: the suite runs windowed. It stands in for a world VM (an instance id), where spawns carry their mod's stamp, plays a panel mod that spawns two buttons into each new bar, and reloads the sidebar by rewriting its file with the same bytes.
