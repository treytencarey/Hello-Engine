---
depends_on: [ai/spawner, ai/archetype/backrooms_wanderer]
conflicts_with: []
exposes: [ai/archetype/backrooms_wanderer/spawner]
---

# ai/archetype/backrooms_wanderer/spawner

A spawner of wanderers: `ai/spawner`, as its `base`, makes the plain bodies, and each that a spawner carrying this links to becomes an `ai/archetype/backrooms_wanderer`. No component's name comes from data. Server only.

## Components

- `ai/archetype/backrooms_wanderer/spawner = {}`, beside `ai/spawner`. It has no fields of its own: configure the bodies on `ai/spawner`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/archetype/backrooms_wanderer/spawner/become` | On an added `ai/spawner/agent` whose spawner carries this, patches the archetype onto the body |

## Use

```lua
commands:spawn({
    ["ai/spawner"] = { count = 3, radius = 12 },
    ["ai/archetype/backrooms_wanderer/spawner"] = {},
    ["core/net/sync"] = false,
})
```

## Notes

- This is the form of a subclass: another creature's spawner is the same few lines with its own archetype.
