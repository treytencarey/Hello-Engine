---
depends_on: [ui/style]
conflicts_with: []
exposes: [sidebar/panel, sidebar/panel/header, sidebar/panel/title, sidebar/panel/scroll, sidebar/panel/loading]
---

# sidebar/panel

The base of every sidebar panel: a column with a header holding the title, and a scroll area below it for the panel's content. Until the panel has a title, the scroll area says "Loading...". Colors come from `ui/style`.

## Components

- `sidebar/panel = { title, width, scroll_speed }` on the panel entity, a UI node. Missing `width` (280) and `scroll_speed` (20 pixels per wheel step) get defaults when it is added. `title`:
  - missing: still loading; the header is hidden and the scroll area shows "Loading...";
  - `""`: no header;
  - text: the header shows it.
- `sidebar/panel/scroll = { offset, speed }`: marks the scroll area, a child of the panel. Put your content here. `offset` is how far it is scrolled.
- `sidebar/panel/header`, `sidebar/panel/title`, `sidebar/panel/loading`: mark the other parts. All parts are added and removed by this mod.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `sidebar/panel/build` | Style the panel and spawn its header, title, scroll area and loading text |
| First, after `sidebar/panel/build` | `sidebar/panel/title` | When the config changes, from the frame the panel is built: width, header shown for a non-empty title, title text, loading text gone once there is a title |
| First | `sidebar/panel/removed` | When `sidebar/panel` is removed from an entity that stays, remove its `Node` and style (its marked parts go by `mod_registry`, even when this mod stops with its last carrier) |

## Use

```lua
local panel = commands:spawn({ ["sidebar/panel"] = { width = 320 }, ChildOf = container }):id()

-- later, when the content is ready: fill the scroll area, then set the title. The scroll
-- area is found by its marker among the panel's descendants, through a declared
-- Query[{ with = { "sidebar/panel/scroll" } }]
for _, scroll in ipairs(scrolls:iter_many(scrolls:iter_descendants(panel))) do
    commands:spawn({ Text = { text = "hello" }, ["ui/style"] = { text = "text" }, ChildOf = scroll:id() })
end
commands:entity(panel):patch({ ["sidebar/panel"] = { title = "Files" } })
```

## Notes

- The wheel scrolls in a `Pointer<Scroll>` observer on the scroll area, keeping the offset between the top and the end of the content. A suite scrolls by triggering Bevy's event in a system with `Commands`: `commands:trigger(Pointer[Scroll], { entity = scroll:id(), pointer_location = { target = { None = { width = 0, height = 0 } } }, event = { unit = "Line", y = <steps>, hit = { camera = camera } } })`. The observer reads the scroll area from `event.entity` and the steps from `event.event.y`.
- When content shrinks, Bevy clamps what is drawn; the next wheel step clamps `offset` too.
- Find the parts by their markers among the panel's descendants (`parts:iter_many(parts:iter_descendants(panel))`), never by a stored id.
- Layout needs a window: a suite for a panel runs windowed.
