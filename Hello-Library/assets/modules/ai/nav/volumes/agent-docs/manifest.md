---
depends_on: []
conflicts_with: []
exposes: [ai/nav/volumes, ai/nav/volume, ai/nav/volumes/due, ai/nav/volumes/job, ai/nav/volumes/region]
---

# ai/nav/volumes

Turns the `ai/nav/volume`s on an entity and below it into `ai/nav/region`s, children of that entity, which `ai/nav` reads. A volume is the area to consider: what is walkable inside it is sampled against the collision world, so an obstacle standing in it becomes a hole the route goes around. Attach a child mod, which brings this along: `ai/nav/volumes/box` or `ai/nav/volumes/scene`. Server only; nothing syncs.

## Components

- `ai/nav/volumes = { sample, cell, max_step, cost, settle, rays_per_frame }`. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `sample` | `false` trusts the volumes as they are, for one you know is clear | `true` |
  | `cell` | metres between samples | 1 |
  | `max_step` | metres of height between neighbouring cells that is still walkable | 0.45 |
  | `cost` | the regions' cost | 1 |
  | `settle` | seconds without new geometry before it bakes | 0.35 |
  | `rays_per_frame` | samples per frame; a 100x100 volume at 1 m is 10 000 | 400 |

- `ai/nav/volume = { hx, hy, hz }`, on the entity or anything below it, added by a child mod or by hand: half extents around that entity's world position. The floor is at the bottom of the volume, and agents walk there.
- `ai/nav/volumes/due = { at }`: on while a bake is owed, `at` being `Time`'s elapsed seconds when it may start.
- `ai/nav/volumes/job = { vols, vi, grid, i, rects }`: a sampling bake in progress.
- `ai/nav/volumes/region`: marks a region it spawned. They go with this mod, by `mod_registry`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/nav/volumes/watch` | When an `ai/nav/volume` is added, changed or removed, every carrier owes a new bake: `settle` from now, its job dropped |
| First | `ai/nav/volumes/init` | On an added `ai/nav/volumes`, fill in missing fields and owe a bake |
| Observer | `On[SceneInstanceReady]` | A scene is ready, new or respawned after its file changed: the same |
| Update | `ai/nav/volumes/bake` | Polls while a bake is owed: gather the volumes, sample `rays_per_frame` a frame, then replace its regions |

## Use

```lua
-- on the server: a child mod brings this along and configures nothing here unless asked to
commands:entity(map):patch({ ["ai/nav/volumes/box"] = { hx = 50, hz = 50 } })

-- by hand: any entity below the carrier with a volume of its own
commands:spawn({
    ["ai/nav/volume"] = { hx = 5, hy = 1, hz = 5 },
    Transform = { translation = { x = 10, y = 1, z = 0 } },
    ChildOf = map,
})
```

## Notes

- Each cell is one ray down. A ray that lands on a body that is not fixed looks past it once, so something standing on the floor is neither floor nor a hole; the upper of two stacked movers does read as floor. Cells within `max_step` of their neighbours are walkable, and they merge into as few rectangles as it can (`shared/grid.lua`).
- A floor that comes later with no scene and no volume changing is not seen, as a plain collider arriving or going rebakes nothing. Add it before the bake, or touch the volume.
- Removing the last volume takes the regions. With no regions, `ai/nav` has no graph to route over.
- A reload reaps its regions and bakes them again.
