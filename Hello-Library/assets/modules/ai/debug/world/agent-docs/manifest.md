---
depends_on: []
conflicts_with: []
exposes: [ai/debug/world, ai/debug/world/slab, ai/debug/world/slabs]
---

# ai/debug/world

Draws the walkable ground. The server half publishes what the `ai/nav/volume`, `ai/nav/region` and `ai/nav/link` entities say in the mod's own component, as a client has none of them, and it reads nothing of `ai/nav`'s. A volume with no region under it, or a region that does not match its volume, shows.

## Components

- `ai/debug/world = { volumes, regions, links }`, on any entity that crosses to clients. Put it on as `{}`, and the server writes the rest. `volumes` are `{ min_x, max_x, min_y, max_y, min_z, max_z }`, `regions` are `{ min_x, max_x, min_z, max_z, y }`, `links` are `{ from, to, x, y, z }`, and each `_count` says how many of that list count.
- `ai/debug/world/slab = { entity = <its carrier> }`, on a slab, on the client: a relationship with target `ai/debug/world/slabs`, `linked_spawn = true`.
- `ai/debug/world/slabs`: a carrier's slabs, kept by the engine.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Last (server) | `ai/debug/world/publish` | Runs only when a volume, region or link is added, changed or removed, or a carrier arrives: publish |
| First (client) | `ai/debug/world/fill` | On a changed `ai/debug/world`, one translucent slab for each region |
| Update (client) | `ai/debug/world/draw` | Each frame, gizmos: volumes, regions, and links with where they cross |
| First (client) | `ai/debug/world/removed` | When it is removed from an entity that stays, its slabs go |

## Use

```lua
commands:spawn({ ["ai/debug/world"] = {} })
```

## Notes

- Regions that touch join with nothing to draw, so only links are drawn between them.
- It writes only when one of those entities changes, so a level that stands still costs one message.
- Removing it on the server leaves it on the clients' copies. The slabs go when the carrier does.
- A headless run has no gizmos, so `ai/debug/world/draw` reports an error there each frame.
- It publishes in `Last`, as a new volume has no place of its own until `PostUpdate` has worked it out.
