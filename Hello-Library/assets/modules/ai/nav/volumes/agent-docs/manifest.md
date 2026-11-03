---
depends_on: []
conflicts_with: []
exposes: [ai/nav/volumes, ai/nav/volume, ai/nav/volumes/due, ai/nav/volumes/job, ai/nav/volumes/region]
---

# ai/nav/volumes

Turns the `ai/nav/volume`s on an entity and below it into `ai/nav/region`s, children of that entity, which `ai/nav` reads. A volume is the area to consider: what is walkable inside it is sampled against the collision world, so an obstacle standing in it becomes a hole the route goes around. Attach a child mod, which brings this along: `ai/nav/volumes/box` or `ai/nav/volumes/scene`. Server only; nothing syncs.

## Components

- `ai/nav/volumes = { sample, cell, max_step, headroom, wall_height, cost, settle }`. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `sample` | `false` trusts the volumes as they are, for one you know is clear | `true` |
  | `cell` | metres between samples | 1 |
  | `max_step` | metres of height between neighbouring cells that is still walkable | 0.45 |
  | `wall_height` | metres above a floor at which something in its cell is in the way | 0.6 |
| `headroom` | metres a floor needs under the surface above it | 2 |
  | `cost` | the regions' cost | 1 |
  | `settle` | seconds without new geometry before it bakes | 0.35 |

- `ai/nav/volume = { hx, hy, hz }`, on the entity or anything below it, added by a child mod or by hand: half extents around that entity's world position. The lowest floor is at the bottom of the volume. To hold storeys, it must reach up past them: rays start 2 m above its top.
- `ai/nav/volumes/due = { at }`: on while a bake is owed, `at` being `Time`'s elapsed seconds when it may start.
- `ai/nav/volumes/job = { vols, vi, grid, ix, iz, y, inside, ceiling, rects }`: a sampling bake in progress, with how far down the current column it has got.
- `ai/nav/volumes/region`: marks a region it spawned. They go with this mod, by `mod_registry`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/nav/volumes/watch` | Runs only when an `ai/nav/volume` is added, changed or removed: every carrier owes a new bake, `settle` from now, its job dropped |
| First | `ai/nav/volumes/init` | On an added `ai/nav/volumes`, owe a bake |
| Observer | `On[SceneInstanceReady]` | A scene is ready, new or respawned after its file changed: the same |
| Update | `ai/nav/volumes/bake` | Polls while a bake is owed: gather the volumes, sample until `over_budget()`, then replace its regions |

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

- A bake stops when the system has spent its slice of the frame's budget, and carries on next frame, so it never makes a frame longer. A run works on one carrier while its slice lasts, and any new volume owes every carrier a bake. When the slice is already spent, a run takes two rays down, the first poll of a run answering false: a 100x100 volume at 1 m is 10 000 of those on one floor, so it can take 5000 frames, nearly a minute and a half at 60 frames a second, and the regions it replaces stay until it is done.
- A ray sees only fixed bodies, so something standing on the floor is neither floor nor a hole.
- Every floor in a column counts, the rays going on down past each. A column on one floor costs five rays, one down and four sideways, and each storey above that seven more: the hit and its four, one to learn it is inside the slab, one to leave it. A floor whose top is within `headroom` of the volume's bottom ends the column, as nothing under it in the volume could have the headroom.
- A floor is walkable when each neighbouring column that found a floor has one within `max_step` of it, and rectangles grow only through floors within `max_step` of the one they started from (`server/grid.lua`). So storeys carve apart, a ramp becomes a run of rectangles each a step high, and each rectangle records `min_y` and `max_y` with its average `y`.
- A floor with less than `headroom` under the surface above it is left out. Rays under a floor assume nothing about what is there: inside something solid they go on through it, and under a plate thinner than 1 cm they find what is below.
- Something standing in a cell above `wall_height`, seen sideways from the cell's centre, takes that floor out, and it stays a level to its neighbours, so a thin wall takes only the cells it passes through. Inside a mesh wall the same look takes the floor it would otherwise find there. A cuboid wall with a cell's centre inside it leaves that cell no floor at that level, so the cells beside it go too: a metre's cell can lose a narrow corridor to that, so use a smaller `cell` for narrow places.
- A mesh collider (`AsyncCollider`, `AsyncSceneCollider`, `Collider.from_bevy_mesh`) is only a surface: a ray inside it goes on to the next face, and it is hit from either side. So a closed mesh with a thin slab reads its underside as the ceiling it is, and bakes what cuboids bake, and a single-sided floor bakes the same. A closed mesh thicker than `headroom` reads its underside as a floor: its sides cut that floor off from outside, so nothing walks in, and asking for a place inside one answers `"unreachable"`. To have a solid thing bake as solid, build its collider as `"ConvexHull"` or `"ConvexDecomposition"`. The top of a ceiling, mesh or cuboid, is a floor like any other.
- A floor that comes later with no scene and no volume changing is not seen, as a plain collider arriving or going rebakes nothing. Add it before the bake, or touch the volume.
- Removing the last volume takes the regions. With no regions, `ai/nav` has no graph to route over.
- A reload reaps its regions and bakes them again.
- A ramp's bare side can block an agent, since paths hug rectangle borders: give a ramp walls or rails.
