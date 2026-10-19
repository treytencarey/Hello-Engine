---
depends_on: [camera/3d, input]
conflicts_with: [camera/first_person, camera/2d, camera/vr]
exposes: [camera/third_person]
---

# camera/third_person

A third-person orbit camera. Extends `camera/3d` (`base = "camera/3d"`), which owns the eye. Mouse motion turns the carrier's `camera` yaw and pitch, the scroll wheel changes `camera.distance`, and the eye orbits the carrier looking at it: `distance` back along the look, `height` up, and `camera.offset` to the side, turned with the yaw. Only the local player's carrier is bound to the mouse.

## Components

- `camera/third_person = { sensitivity, min_pitch, max_pitch, zoom_step, min_distance, max_distance }`: put on the entity the camera belongs to, usually the player. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `sensitivity` | radians turned per unit of mouse motion | 0.003 |
  | `min_pitch`, `max_pitch` | how far the look can go down and up, radians | -1.2, 0.2 |
  | `zoom_step` | metres per unit of scroll | 0.5 |
  | `min_distance`, `max_distance` | how close and how far the eye can be, metres | 2, 20 |

- It binds `input/game.third_person = { look = { motion = true }, zoom = { scroll = true } }` and reads `input/game/third_person/look` and `input/game/third_person/zoom`.
- It writes `camera/3d.offset`.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First | CameraThirdPersonInit | On an added `camera/third_person`, fill in missing config fields |
| First | CameraThirdPersonBind | On the local carrier, bind mouse look and zoom (again when `input` is added back) |
| First | CameraThirdPersonUnbind | When `camera/third_person` is removed, unbind them |
| Update | Camera | Turn yaw and pitch from mouse motion by `sensitivity`; pitch is clamped to `min_pitch`..`max_pitch` |
| Update | CameraZoom | Change `camera.distance` by scroll times `zoom_step`, clamped to `min_distance`..`max_distance` |
| Update, after `Camera` and `CameraZoom` | CameraAim | Put the eye on the orbit through `camera/3d.offset` |

## Use

```lua
player:patch({ ["camera/third_person"] = {} })
player:patch({ camera = { distance = 12, offset = { x = 0.8, y = 0, z = 0 } } })   -- farther, over the right shoulder
```

## Notes

- The eye's rotation comes from `camera/3d` (yaw, then pitch), which looks straight at the orbit's centre; this mod only places it.
- Adding another `camera/3d` mod replaces this one, and the eye is kept.
