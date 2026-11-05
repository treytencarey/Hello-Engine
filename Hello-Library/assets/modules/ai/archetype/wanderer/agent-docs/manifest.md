---
depends_on: [ai/agent, ai/nav, ai/steering, ai/perception, ai/behavior/chase, ai/behavior/investigate, ai/behavior/patrol]
conflicts_with: []
exposes: [ai/archetype/wanderer]
---

# ai/archetype/wanderer

A wanderer that goes to look at noises and chases what it can see. Put on a body, it makes an agent of it: its `base` is `ai/agent`, and it declares navigation, steering, perception and its behaviours, each with its own mod's defaults. Server only.

## Components

- `ai/archetype/wanderer = {}`, on a body. It has no fields of its own.

It adds these to the body, each only if the body lacks it:

| Component | Value |
|-----------|-------|
| `ai/nav` | `capabilities = { walk = true }` |
| `ai/steering` | `{}` |
| `ai/perception` | `{}` |
| `ai/behavior/chase` | `{}` |
| `ai/behavior/investigate` | `{}` |
| `ai/behavior/patrol` | `{}` |

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/archetype/wanderer/init` | On an added wanderer, adds the components above that the body lacks |
| First | `ai/archetype/wanderer/removed` | When it is removed from a body that stays, what it added goes; `ai/agent` goes with it as its base |

## Use

```lua
commands:entity(body):insert({ ["ai/archetype/wanderer"] = {} })

-- a creature of its own, built on it: its numbers as carrier defaults
-- my/creature/server/init.lua
return {
    base = "ai/archetype/wanderer",
    defaults = {
        ["ai/steering"] = { speed = 1.8 },
        ["ai/perception"] = { vision_range = 20 },
    },
}
```

## Notes

- A value the body was given at its spawn stays, and so does a component it already had.
- Carrier defaults apply only to the creature's own carriers; every other wanderer keeps each mod's default.
- A creature needs its own spawner to be spawned by `ai/spawner`: `ai/archetype/wanderer/spawner` with its own archetype.
