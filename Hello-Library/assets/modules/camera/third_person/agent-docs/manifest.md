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

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `camera/third_person/bind` | On the local carrier, bind mouse look and zoom (again when `input` is added back) |
| First | `camera/third_person/unbind` | When `camera/third_person` is removed, unbind them |
| Update, before `camera/3d/aim` | `camera/third_person` | Turn yaw and pitch from mouse motion by `sensitivity`; pitch is clamped to `min_pitch`..`max_pitch` |
| Update | `camera/third_person/zoom` | Change `camera.distance` by scroll times `zoom_step`, clamped to `min_distance`..`max_distance` |
| Update, after `camera/third_person` and `camera/third_person/zoom`, before `camera/3d/aim` | `camera/third_person/aim` | Put the eye on the orbit through `camera/3d.offset` |

## Use

```lua
commands:entity(player):patch({ ["camera/third_person"] = {} })
commands:entity(player):patch({ camera = { distance = 12, offset = { x = 0.8, y = 0, z = 0 } } })   -- farther, over the right shoulder
```

## Notes

- The eye's rotation comes from `camera/3d` (yaw, then pitch), which looks straight at the orbit's centre; this mod only places it.
- Adding another `camera/3d` mod replaces this one, and the eye is kept.
- A suite run in a window gives its carrier `input = {}` (no mode): no binding is active (`input`), so a real mouse moved while the window has focus does not turn the camera. The suite writes the look itself; this mod binds into `input/game` whatever the mode.
