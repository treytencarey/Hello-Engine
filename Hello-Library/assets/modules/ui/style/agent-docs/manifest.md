---
depends_on: [ui/theme]
conflicts_with: []
exposes: [ui/style]
---

# ui/style

UI colors by role. A UI node says what it is, and `ui/style` alone writes its `BackgroundColor`, `TextColor` and `BorderColor` from the world's theme. Mods never read or write colors themselves; a game restyles every UI at once, live, by patching `ui/theme`.

## Components

- `ui/style = { background, text, border, border_left, hover, press, alpha }` on a UI node; every field is optional:
  - `background`, `text`, `border` (all four sides), `border_left` (the left side only): a role name.
  - `hover`: the background role while the node is hovered. The style puts Bevy's `Hovered` (false) on a node with a hover role, as Bevy's picking keeps it only on the entities that carry it; picking sets it true while the pointer is on the node or any of its descendants (a button's label included). It stays when `ui/style` goes, as another mod may read it.
  - `press`: the background role while the node is pressed, which wins over `hover`. The style sets and clears Bevy's `Pressed` marker on a node with a press role, so other mods can read it: added on the pointer's `Press` on the node or any of its descendants (the event goes up from the node it hit), taken off on its `Release` there, on the `DragEnd` of a press whose release was off the node (a release reaches only what is under the pointer then), on its `Cancel`, and when `ui/style` goes.
  - Neither reads `Interaction`: bevy_ui updates it only for cameras drawing to a window, and a world draws to a texture.
  - `alpha`: scales every color's alpha, 0 to 1 (fades).
- The colors come from `ui/theme`, filled by a theme mod (`ui/theme/dark`); without one, nothing is colored.

## Roles

`bg`, `header_bg`, `icon_bar_bg`, `icon_bg`, `icon_hover`, `icon_active`, `icon_active_hover`, `border`, `row_bg`, `row_alt`, `row_hover`, `row_selected`, `text`, `text_dim`, `text_warn`, `text_bad`, `text_good`, `accent`, `folder`, `file`, `context_bg`, `context_hover`, `danger`, `transparent`, `drop_zone`, `drop_highlight`. A theme may add more; a role the theme lacks leaves that color alone.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ui/style/init` | On a style's `changed` edge (`added` included), give a node with a hover role `Hovered`, if it has none |
| PostUpdate | `ui/style` | Color each node whose style or `Hovered` changed, or that gained or lost `Pressed`; every node when the theme changed |
| First | `ui/style/removed` | When `ui/style` is removed from a node that stays, remove its colors and `Pressed` |

| Observer | Purpose |
|----------|---------|
| `Pointer<Press>` | On each node the press reaches, one with a press role gets `Pressed` |
| `Pointer<Release>`, `Pointer<DragEnd>`, `Pointer<Cancel>` | On each node the event reaches, a styled one loses `Pressed` |

## Use

```lua
commands:spawn({
    Node = { ... },
    ["ui/style"] = { background = "bg", border = "border" },
})

commands:spawn({ Node = { ... }, ["ui/style"] = { background = "icon_bg", hover = "icon_hover", press = "icon_active" } })

commands:entity(icon):patch({ ["ui/style"] = { background = "icon_active" } })   -- now active
commands:entity(card):patch({ ["ui/style"] = { alpha = 0.4 } })                  -- fading

-- restyle every UI in the world
commands:entity(theme):patch({ ["ui/theme"] = { bg = { r = 0.1, g = 0.1, b = 0.2, a = 1 } } })
```

## Notes

- Colors are written in `PostUpdate`, so a style change made in `Update` shows the same frame.
- A theme change restyles every styled node, once; otherwise only nodes whose style, hover or press changed are touched.
- A pointer event goes up from the node it hit only where Bevy knows the `Window` component: its traversal reads `Option<&Window>`, and with no `Window` registered it stops at the first node. A world VM registers it (bevy_ui's focus system queries it); a headless suite does not, so `test_style` spawns and despawns one before it presses a label.
- `Hovered` itself is picking's; a headless suite has no picking, so `test_style` inserts it as picking does. That a label keeps its button hovered is Bevy's rule (picking walks up from the node under the pointer), seen only in a window.
- A role is a colour's name in the theme: `text = "text_dim"`.
