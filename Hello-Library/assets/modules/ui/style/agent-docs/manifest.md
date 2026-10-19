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
  - `hover`, `press`: the background role while the node is hovered or pressed. The node needs `Interaction`, which a `Button` has.
  - `alpha`: scales every color's alpha, 0 to 1 (fades).
- The colors come from `ui/theme`, filled by a theme mod (`ui/theme/dark`); without one, nothing is colored.

## Roles

`bg`, `header_bg`, `icon_bar_bg`, `icon_bg`, `icon_hover`, `icon_active`, `icon_active_hover`, `border`, `row_bg`, `row_alt`, `row_hover`, `row_selected`, `text`, `text_dim`, `text_warn`, `text_bad`, `text_good`, `accent`, `folder`, `file`, `context_bg`, `context_hover`, `danger`, `transparent`, `drop_zone`, `drop_highlight`. A theme may add more; a role the theme lacks leaves that color alone.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| PostUpdate | Style | Color each node whose style or interaction changed; every node when the theme changed |
| First | StyleRemoved | When `ui/style` is removed from a node that stays, remove its colors |

## Use

```lua
spawn({
    Node = { ... },
    ["ui/style"] = { background = "bg", border = "border" },
})

spawn({ Button = {}, Node = { ... }, ["ui/style"] = { background = "icon_bg", hover = "icon_hover" } })

icon:patch({ ["ui/style"] = { background = "icon_active" } })   -- now active
card:patch({ ["ui/style"] = { alpha = 0.4 } })                  -- fading

-- restyle every UI in the world
theme:patch({ ["ui/theme"] = { bg = { r = 0.1, g = 0.1, b = 0.2, a = 1 } } })
```

## Notes

- Colors are written in `PostUpdate`, so a style change made in `Update` shows the same frame.
- A theme change restyles every styled node, once; otherwise only nodes whose style or interaction changed are touched.
- The default roles are the old `sidebar/shared/colors.lua` names, so a mod moves from `Colors.text_dim` to `text = "text_dim"`.
