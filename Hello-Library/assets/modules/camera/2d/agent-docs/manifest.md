---
depends_on: [camera, input, transform/follow]
conflicts_with: [camera/first_person, camera/third_person, camera/vr]
exposes: [camera/2d, camera/2d/eye]
---

# camera/2d

A top-down 2D camera. Extends `camera` (`base = "camera"`). The local player's carrier gets an eye: a Camera2d child kept `z` above the carrier and scaled by the carrier's `camera.distance` (1 is 1:1), which the scroll wheel changes. The eye moves with the carrier but does not turn with it (`transform/follow`). Remote carriers get no eye.

## Components

- `camera/2d = { zoom_step, min_distance, max_distance, z }`: put on the entity the camera belongs to, usually the player. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `zoom_step` | distance per unit of scroll | 0.1 |
  | `min_distance`, `max_distance` | how close and how far the view can go | 0.25, 4 |
  | `z` | how far above the carrier the eye sits | 1000 |

- `camera/2d/eye = {}`: marks the eye, a child of the carrier. Added and despawned by this mod.
- It binds `input/game.camera_2d.zoom = { scroll = true }`, reads `input/game/camera_2d/zoom`, and writes `camera.distance`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `camera/2d/spawn` | On the local carrier, spawn the eye already placed and scaled, or turn the existing eye back on |
| First | `camera/2d/bind` | On the local carrier, bind the scroll wheel (again when `input` is added back) |
| First | `camera/2d/teardown` | When the player leaves for another world (`core/net/local` removed), turn the eye off |
| First | `camera/2d/remove` | When `camera/2d` is removed, unbind; the eye, marked `camera/2d/eye`, goes by `mod_registry` |
| Update | `camera/2d/zoom` | Change `camera.distance` by scroll times `zoom_step`, clamped to `min_distance`..`max_distance` |
| Update, after `camera/2d/zoom` | `camera/2d/aim` | When `camera` or `camera/2d` changes, set the eye's scale and height |

## Use

```lua
commands:spawn({ camera = { distance = 1 }, ["camera/2d"] = {} })   -- start at 1:1; camera's own default distance is 8
commands:entity(player):patch({ ["camera/2d"] = { z = 500, max_distance = 2 } })   -- lower, and at most 2x

-- switch to a 3D camera: camera/2d and its eye are removed for you
commands:entity(player):patch({ ["camera/third_person"] = {} })
```

## Notes

- Zoom is `camera.distance`, so it is kept between worlds with the rest of `camera`. Set the starting zoom with `camera.distance`; `camera` defaults it to 8, a 3D distance.
- The eye's scale is set on its own `Transform`; `transform/follow` sets only its position and rotation.
- The eye is a child, so it despawns with its carrier.
- A suite run in a window gives its carrier `input = {}` (no mode): no binding is active (`input`), so a real mouse scrolled while the window has focus does not zoom the camera. The suite writes the zoom itself; this mod binds into `input/game` whatever the mode.
