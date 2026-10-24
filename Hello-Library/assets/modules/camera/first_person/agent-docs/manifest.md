---
depends_on: [camera/3d, input]
conflicts_with: [camera/third_person, camera/2d, camera/vr]
exposes: [camera/first_person]
---

# camera/first_person

A first-person camera. Extends `camera/3d` (`base = "camera/3d"`), which owns the eye. Mouse motion turns the carrier's `camera` yaw and pitch, and the eye sits at the carrier's head, `camera.height` above it. Only the local player's carrier is bound to the mouse.

## Components

- `camera/first_person = { sensitivity = <radians per unit of mouse motion>, pitch_limit = <radians> }`: put on the entity the camera belongs to, usually the player. Missing fields get defaults when it is added (sensitivity 0.0025, pitch limit 1.4, about 80 degrees).
- It binds `input/game.first_person.look = { motion = true }` and reads `input/game/first_person/look`.
- It writes `camera/3d.offset`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `camera/first_person/init` | On an added `camera/first_person`, fill in missing config fields |
| First | `camera/first_person/bind` | On the local carrier, bind mouse look (again when `input` is added back) |
| First | `camera/first_person/unbind` | When `camera/first_person` is removed, unbind mouse look |
| Update, before `camera/3d/aim` | `camera/first_person` | Turn yaw and pitch from mouse motion by `sensitivity`; pitch is clamped to `pitch_limit` |
| Update, before `camera/3d/aim` | `camera/first_person/aim` | Put the eye at the head: `camera/3d.offset = { 0, camera.height, 0 }` |

## Use

```lua
commands:entity(player):patch({ ["camera/first_person"] = {} })

-- switch to third person: the same eye moves out to the orbit
commands:entity(player):patch({ ["camera/third_person"] = {} })   -- camera/first_person is removed for you
```

## Notes

- Adding another `camera/3d` mod replaces this one (both originate `camera/3d`), and the eye is kept.
- Removing it removes `camera/3d` with it, which despawns the eye.
- A suite run in a window gives its carrier `input = {}` (no mode): no binding is active (`input`), so a real mouse moved while the window has focus does not turn the camera. The suite writes the look itself; this mod binds into `input/game` whatever the mode.
