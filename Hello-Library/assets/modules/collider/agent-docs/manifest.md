---
depends_on: [core/mod_registry]
conflicts_with: []
exposes: [collider, collider/status]
---

# collider

The base of the collider mods, `collider/mesh` and `collider/bb`. Never put on an entity by hand: a collider mod returns `{ base = "collider" }`, the registry adds `collider` beside it, and removes it with that mod. The mod sets `collider.built` once the carrier's shapes are built.

The base keeps the books for each scene, and names none of its children: on the nearest `SceneRoot` above its carriers (or the carrier itself, if it holds one) it keeps `collider/status`, which says whether the scene's colliders are still building. That is how "the map has loaded" is read.

Root `init.lua`: both sides, as each side builds its own colliders from its own copy of the scene. Declares no `core/net/sync`.

## Components

- `collider = { built }`, on each carrier. `built` (default `false`) is written by the child mod: true once every primitive of the carrier has its shape, false while it is rebuilding.
- `collider/status = { state }`, on a scene root that holds carriers. `state` is `"building"` while any carrier under the root has `built ~= true`, and `"done"` when none has. It is added with the root's first carrier, written only when the state changes, and removed with the root's last carrier. A carrier with no `SceneRoot` above it counts toward no status.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `collider/status` | On `collider` added or changed, the touched carriers' roots; on `collider` removed (a despawned carrier's root can't be read), every root that has a status. Each root's carriers are `carriers:iter_many(carriers:iter_descendants(root))` plus the root: none, `try_remove("collider/status")`; else insert it, or `set_if_neq` the state |

The children order their builds `:before("collider/status")`, so a frame's builds are counted in that frame.

## Use

Read it on its edges, never per frame. The status is the one on the nearest `SceneRoot` above the point you care about:

```lua
Query[{
    ["or"] = {
        added = { "collider/status" },
        changed = { "collider/status" },
    },
}]
Query[{ removed = { "collider/status" } }]
```

## Notes

- **Edges a consumer sees.** A scene that builds in one frame (a small map, every carrier built in the frame it gets the base) shows one `added` edge with `"done"`, and no `"building"`. A big one (a 36 MB map with 249 carriers) builds over several frames under the frame budget: `added` with `"building"`, then a `changed` edge to `"done"`.
- **Re-export.** Bevy despawns the scene's nodes and spawns new ones, whose carriers get the base frames later. Measured on markers.glb: `"done"`, then the status removed (a frame with no carrier), then added again as `"done"`. That 36 MB map: removed, then added as `"building"`, then `"done"`; one write of its file can do this twice. Either way, a consumer treats `removed` like `"building"`.
- **What it can't see.** It counts only carriers that already have the base. Measured: every carrier of one `gltf/mod_registry` pass gets the base in the same frame, even when `collider/mesh` was loaded and `collider/bb` loads with the scene.
- The registry removes the status with the mod when the mod unloads, with its last carrier.

## Tests

`tests/test_status.lua`, server side. K1 five carriers built a few a frame: `"building"`, then `"done"` after the last, never early, one change; K2 markers.glb's two kinds: `"done"` once both are built; K3 a re-export leaves `"done"` and comes back to it; K4 the status goes with the last carrier and another scene's is untouched; K5 one pass's carriers get the base in the same frame, and the status is never `"done"` early; K6 `collider/mesh` on a `SceneRoot` whose file is not there yet stays `"building"` until the scene has spawned and every primitive has its shape; K7 a reload of this mod: every root is `"done"` again, with one shape a carrier. `test_mesh.lua` and `test_bb.lua` run the children.
