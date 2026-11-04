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
- `sidebar/container`, `sidebar/bar`: the sidebar's own UI, one of each, found as the first row of a query for its marker (`containers:iter()[1]`). The container is a UI root; panels go inside it, beside the bar.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `sidebar/setup` | For the local player with `input`, bind Escape in `input/game` and `input/ui` (again when `input` is added back), and build the container and bar, hidden unless the sidebar is open already (a reload) |
| First | `sidebar/away` | When the player leaves for another world, close the sidebar |
| First | `sidebar/removed` | When `sidebar` is removed, despawn the container with everything in it, and unbind |
| Update | `sidebar/toggle` | Escape in game input opens the sidebar; in UI input it closes the newest open panel, or the sidebar |
| Update, after `sidebar/toggle` | `sidebar/show` | On opening: show the container, UI input with the cursor |
| Update, after `sidebar/toggle` | `sidebar/hide` | On closing: hide, game input, close every panel |
| Update | `sidebar/icons` | A new button becomes an icon: style, click observer, letter |
| Update | `sidebar/order` | When a button comes, put the bar's icons in `order` (`Children`) |
| Update | `sidebar/icon_open` | An icon is drawn active when its panel opens |
| Update, after `sidebar/toggle` and `sidebar/hide` | `sidebar/icon_closed` | An icon is drawn inactive again when its panel closes |

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):patch({ sidebar = {}, ["sidebar/profiler"] = {} })

-- a panel mod: its button in the bar, for a local player with the panel. Both edges: a new
-- bar (the sidebar built or reloaded), and the panel itself (added, or this mod reloaded)
Query[{ added = { "sidebar/bar" } }]
Query[{ added = { "sidebar/profiler" }, with = { "core/net/local" } }]
-- local bar = bars:iter()[1]   (bars: a declared Query[{ with = { "sidebar/bar" } }])
-- commands:spawn({
--     ["sidebar/button"] = { title = "Profiler", order = 1 },
--     ["sidebar/profiler/button"] = {},
--     ChildOf = bar:id(),
-- })

Query[{ added = { "sidebar/button/open" }, with = { "sidebar/profiler/button" } }]
-- local container = containers:iter()[1]   (containers: Query[{ with = { "sidebar/container" } }])
-- commands:spawn({ ["sidebar/panel"] = { width = 320 }, ["sidebar/profiler/view"] = {}, ChildOf = container:id() })
Query[{ removed = { "sidebar/button/open" }, with = { "sidebar/profiler/button" } }]
-- despawn the entity marked sidebar/profiler/view
```

A panel stays open through a hot reload if it keeps what it needs on the carrier, which a reload leaves alone: its button and panel are its own spawns, and they go.

```lua
-- on the carrier's added edge, if it has none
commands:entity(e:id()):insert({ ["sidebar/profiler/state"] = { open = false } })

-- a new button, once the sidebar has made it an icon (an icon drawn active needs its Node), opens
-- again by the path a click takes
Query[{ added = { "Node" }, with = { "sidebar/profiler/button" } }]
-- if state.open: insert { ["sidebar/button/open"] = { order = <one above the open buttons' highest> } }

-- added: save open = true. removed: the edge also comes for a button a reload despawned, so only a
-- button still here closing saves open = false
for _, _ in ipairs(buttons:iter_many(closed_ids)) do ... end
```

## Notes

- A click on an icon opens or closes its button's panel in the button's `Pointer<Click>` observer. A suite clicks by triggering Bevy's event in a system with `Commands`: `commands:trigger(Pointer[Click], { entity = button:id(), pointer_location = { target = { None = { width = 0, height = 0 } } }, event = { button = "Primary", hit = { camera = camera } } })`. The observer reads the clicked entity from `event.entity`.
- Opening a panel closes no other: several stay open side by side. A panel closes by a click on its icon, by Escape while it is the newest, or when the sidebar closes.
- A sub-component named under `sidebar/` on the player, a panel mod's included, goes when `sidebar` is taken off. The panel mod's own component stays.
- A key held through a mode switch waits for its release (`input`), so the Escape that opens the sidebar does not also close it.
- The container is a UI root of its own: a UI node under the player would not be laid out.
- Layout and clicks need a window: the suite runs windowed. It stands in for a world VM (an instance id), where spawns carry their mod's stamp, plays a panel mod that spawns two buttons into each new bar, and reloads the sidebar by rewriting its file with the same bytes.
