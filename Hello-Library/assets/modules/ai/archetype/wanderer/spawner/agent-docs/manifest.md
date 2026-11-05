---
depends_on: [ai/spawner, ai/archetype/wanderer]
conflicts_with: []
exposes: [ai/archetype/wanderer/spawner]
---

# ai/archetype/wanderer/spawner

A spawner of wanderers: `ai/spawner`, as its `base`, makes the plain bodies, and each that a spawner carrying this links to becomes an `ai/archetype/wanderer`. No component's name comes from data. Server only.

## Components

- `ai/archetype/wanderer/spawner = {}`, beside `ai/spawner`. It has no fields of its own: configure the bodies on `ai/spawner`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/archetype/wanderer/spawner/become` | On an added `ai/spawner/agent` whose spawner carries this, adds the archetype to the body |

## Use

```lua
commands:spawn({
    ["ai/spawner"] = { count = 3, radius = 12 },
    ["ai/archetype/wanderer/spawner"] = {},
    ["core/net/sync"] = false,
})
```

## Notes

- This is the form of a subclass: another creature's spawner is the same few lines with its own archetype.
