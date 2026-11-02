---
depends_on: [ai/nav/volumes]
conflicts_with: [ai/nav/volumes/scene]
exposes: [ai/nav/volumes/box, ai/nav/volumes/box/volume]
---

# ai/nav/volumes/box

One walkable box from numbers, for a map with no authored node to mark: a child entity with an `ai/nav/volume`, which its base `ai/nav/volumes` bakes. Give it the numbers the map builds its collider from, so the two agree. Server only; nothing syncs.

## Components

- `ai/nav/volumes/box = { hx, hz, hy, x, y, z }`. Without `hx` and `hz` there is no child. Missing others get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `hx`, `hz` | half extents | required |
  | `hy` | half height: the floor is at `y - hy` | 0 |
  | `x`, `y`, `z` | centre, relative to the entity | 0 |

- `ai/nav/volumes/box/volume`: marks its child, which also holds the `ai/nav/volume` and a `Transform`. It goes with this mod, by `mod_registry`, and `ai/nav/volumes` goes with it when this mod brought it.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/nav/volumes/box/spawn` | On a changed one (also on add), spawn its child, or write the one it has |

## Use

```lua
-- on the server, on a map's entity
commands:entity(map):patch({ ["ai/nav/volumes/box"] = { hx = 50, hz = 50 } })
```

## Notes

- It extends `ai/nav/volumes`, which has one child per entity: this or `ai/nav/volumes/scene`.
- The entity needs a `Transform` for its child to have a world position.
