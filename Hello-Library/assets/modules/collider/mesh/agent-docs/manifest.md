---
depends_on: [collider]
conflicts_with: []
exposes: [collider/mesh]
---

# collider/mesh

A static trimesh collider from the carrier's own geometry: every mesh primitive at or below the carrier gets a child shape built from its mesh. In Blender, give an object the custom property `collider/mesh` (`{}`), export, and `gltf/mod_registry` puts this mod on its node. Or put `["collider/mesh"] = {}` on an entity yourself, once its meshes are there.

Extends `collider`, and sets its `built`. Root `init.lua`: both sides. Declares no `core/net/sync`.

## Components

- `collider/mesh = {}`, on the carrier.
- `collider/mesh/shape`, the marker on each shape: `{ Transform = {}, Collider3d = Collider.from_bevy_mesh(mesh, "TriMesh"), ChildOf = <primitive> }`. The registry despawns the shapes when `collider/mesh` leaves.
- Writes `collider.built`: true once every primitive has been built.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `collider/mesh/build` | On `collider/mesh` or `collider` added or changed, with `collider` there: despawn the primitives' old shapes, build one per primitive over `prims:iter_many(prims:iter_descendants(carrier))` plus the carrier, and set `collider.built = true`. It stops when its slice of the frame's budget is spent (`Res[LuaFrameBudget]`); each carrier left writes `collider = { built = false }` through `Commands`, which runs it again next frame. `:before("collider/status")` |
| Observer | `On[SceneInstanceReady]` | A carrier holding the `SceneRoot` whose scene is ready: write `collider = { built = false }` through `Commands`, which runs the build |

## Notes

- **The budget.** A map's 249 carriers built in about 17 frames on their own; with other Lua work taking the frame's slice it builds two a frame. A suite that reads `Collider3d` rows every frame serializes every trimesh and slows each frame down by seconds; count `collider/mesh/shape` instead.
- **A changed config, a hot reload of this file, and a re-export** each build exactly once: one shape per primitive. A reload's reap takes the shapes, and the first run after it builds them again.
- **No RigidBody**: a body-less collider is static, and Rapier re-places it whenever its `GlobalTransform` changes. A `Fixed` body has Rapier write its pose back through the parent's inverse, which drifts under a scaled, rotated node.
- **A mesh Rapier refuses** (or one not loaded yet) gets no shape and a printed warning, and the carrier still counts as built, so a bad mesh never holds the map at `"building"`. A GLB's meshes load with its scene.
- **On a `SceneRoot` that is still loading** (the carrier holds a `SceneRoot` and has no `Children` yet), it waits: the carrier stays unbuilt, so the root reads `"building"`. An observer on Bevy's `SceneInstanceReady` for that root writes `collider = { built = false }`, which runs the build once the scene has spawned, and again after a re-export respawns it.

## Tests

`collider/tests/test_mesh.lua`, server side, on a copy of markers.glb (fx_floor, a 4 x 4 x 0.2 m slab). M1 one shape under the slab, a child of its primitive, built; M2 a dropped ball rests on it; M3 a changed config and a reload each build exactly once; M4 a re-export builds the new slab; M5 removing `collider/mesh` takes the shape and the base, the ball falls through, the mesh stays.
