---
depends_on: []
conflicts_with: []
exposes: [ui/theme]
---

# ui/theme

The colors UI roles stand for, one theme per world. A theme mod extends it with `base = "ui/theme"` and writes its colors when `ui/theme` arrives; `ui/style` paints styled nodes from it and restyles them all when it changes. Without a theme mod, nothing is colored.

## Components

- `ui/theme = { <role> = { r, g, b, a } }`: written by the theme mod. The roles `ui/style` users rely on are listed in the `ui/style` manifest; a theme may add more.

## Use

```lua
spawn({ ["ui/theme/dark"] = {} })                                       -- give this world the dark theme
theme:patch({ ["ui/theme"] = { accent = { r = 1, g = 0.5, b = 0, a = 1 } } })   -- adjust it live
```

## Notes

- This mod has no systems: it names the component theme mods fill and `ui/style` reads.
