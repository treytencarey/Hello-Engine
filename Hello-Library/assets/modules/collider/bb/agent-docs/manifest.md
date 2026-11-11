---
depends_on: [collider]
conflicts_with: []
exposes: [collider/bb]
---

# collider/bb

A box collider per mesh primitive: every primitive at or below the carrier gets a child cuboid at its bounding box, which Bevy's glTF loader gives it in the mesh's own space (headless too). Rapier composes the primitive's rotation and scale through the hierarchy, so no transform math is in Lua. In Blender, give an object the custom property `collider/bb` (`{}`), export, and `gltf/mod_registry` puts this mod on its node. Or put `["collider/bb"] = {}` on an entity yourself, including one that carries a loaded `SceneRoot`, whose primitives then all get boxes.

Extends `collider`, and sets its `built`. Root `init.lua`: both sides. Declares no `core/net/sync`.

## Components

- `collider/bb = {}`, on the carrier.
- `collider/bb/shape`, the marker on each shape: `{ Transform = { translation = aabb.center }, Collider3d = Collider.cuboid(half.x, half.y, half.z), ChildOf = <primitive> }`. The registry despawns the shapes when `collider/bb` leaves.
- Writes `collider.built`: true once every primitive has its box.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `collider/bb/build` | On `collider/bb` or `collider` added or changed, with `collider` there: despawn the primitives' old boxes, box each `Mesh3d` + `Aabb` primitive over `prims:iter_many(prims:iter_descendants(carrier))` plus the carrier, and set `collider.built = true`. It stops when its slice of the frame's budget is spent; each carrier left writes `collider = { built = false }` through `Commands`, which runs it again next frame. `:before("collider/status")` |
| Observer | `On[SceneInstanceReady]` | A carrier holding the `SceneRoot` whose scene is ready: write `collider = { built = false }` through `Commands`, which runs the build |

## Notes

- One box per primitive: a multi-material object exports as several primitives and gets several boxes.
- **No RigidBody**: a body-less collider is static and Rapier re-places it whenever its `GlobalTransform` changes. A `Fixed` body has Rapier write its pose back through the parent's inverse, which drifted a box 3 m under a rotated, non-uniformly scaled node.
- **On a `SceneRoot` that is still loading** (no `Children` yet), it waits, unbuilt, and an observer on Bevy's `SceneInstanceReady` for that root runs the build once the scene has spawned, and again after a re-export.

## Tests

`collider/tests/test_bb.lua`, server side, on markers.glb (fx_box, a 2 x 0.5 x 1 m box at (2, 1, -3), turned 30 degrees and scaled 1.5 on X). B1 one box, a child of the primitive, built; B2 at the box's centre in world space; B3 a dropped ball lands on its top; B4 a changed config and a reload each build exactly once; B5 removing `collider/bb` takes the box and the base; B6 put on a loaded `SceneRoot`, it boxes every primitive.
