---
depends_on: [ui/theme]
conflicts_with: []
exposes: [ui/theme/dark]
---

# ui/theme/dark

A dark theme: dark panels, light text, blue accents. Extends `ui/theme`.

## Components

- `ui/theme/dark = {}`: put on any one entity of the world, usually at world start. `ui/theme` arrives with it, and this mod fills every role.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First | ThemeDark | When `ui/theme` arrives on its entity, write the dark colors |

## Use

```lua
spawn({ ["ui/theme/dark"] = {} })
```
