---
depends_on: [camera, input, transform/follow]
conflicts_with: [camera/third_person, camera/first_person, camera/2d]
exposes: [camera/vr]
---

# camera/vr

The camera of this client's player in VR. Extends `camera` (`base = "camera"`). The headset's two eyes belong to the engine, which places them from `VmXrRig` on the player. This mod writes the rig from the player's position and the right stick's turn, and writes `camera.yaw`, which is where the player walks. The window gets a camera of its own at the headset's pose. `player/vr` adds it on the server while the player is in VR, so it reaches every client; it acts only on this client's own player.

## Components

- `camera/vr = { height, turn_speed, movement_direction }`, synced from the server. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `height` | metres the tracking space sits above the player's origin | -0.5 |
  | `turn_speed` | radians per second at full stick | 2 |
  | `movement_direction` | `"head"`: `camera.yaw` is where the head looks; `"body"`: only the stick's turn | `"head"` |

- `VmXrRig = { translation, yaw }`: the engine's component, on the player. Added here and removed when `camera/vr` goes or the player stops being this client's.
- `camera/vr/mirror = {}`: marks the window's camera, a child of the player that follows it without its rotation (`transform/follow`). It goes with `camera/vr`.
- It binds `input/game.camera_vr = { turn_left = { key = "ArrowLeft" }, turn_right = { key = "ArrowRight" } }` and reads their action components for strength. `vr/input` presses those keys from the right stick.
- It reads `vr/input/pose` when it is there, and writes `camera.yaw`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `camera/vr/bind` | On the local carrier, bind the turn keys (again when `input` is added back) |
| First | `camera/vr/spawn` | On the local carrier, spawn its mirror, or turn it back on |
| First | `camera/vr/teardown` | The player stopped being this client's: turn the mirror off and remove the rig |
| First | `camera/vr/removed` | When `camera/vr` goes from an entity that stays: remove the rig and unbind |
| Update, before `movement/walk` | `camera/vr/rig` | Polls: turn by the stick, write the rig only when it differs, write `camera.yaw` by `movement_direction` |
| Update | `camera/vr/mirror` | On a changed `vr/input/pose`: put the mirror at the headset's pose |

## Use

```lua
-- on the server: walk where the stick has turned, whatever the head does
commands:entity(player):insert({ ["camera/vr"] = { movement_direction = "body" } })
```

## Notes

- It extends `camera`, and `camera/third_person` extends `camera/3d`, which extends `camera`: adding either replaces the other, and the third-person eye goes or comes with `camera/3d`. `camera` stays.
- It does not spawn the eyes, and has no way of seeing them. What a headset shows, and whether the rig's numbers suit one (`height`, the direction of the turn), has not been checked on a headset.
- A mod that holds the rig on something else (a fixed viewpoint) takes `camera/vr` off first: its removal takes the rig.
- Suite: `camera/vr/tests/test_camera_vr.lua`, headless, with the messages the engine's VR plugin writes.
