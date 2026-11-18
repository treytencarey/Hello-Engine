---
depends_on: [pointer, vr/input]
conflicts_with: []
exposes: [vr/pointer, vr/pointer/laser]
---

# vr/pointer

The VR controller's ray cast for `pointer`. It uses `pointer` as its base and is only the VR controller's ray source, plus a laser showing the ray, the way `pointer/view` is the desktop's: what the ray does on a screen (moves, presses, the long press, scroll) is `pointer`'s. `player/vr` adds it on the owning client while the player is in VR, in place of `pointer/view`, and it never crosses.

## Components

- `vr/pointer = { pitch, yaw, length, radius }`, on the player:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `pitch` | degrees the ray tilts down from the controller's forward, in the controller's own frame | -60 |
  | `yaw` | degrees it turns about the controller's up | -10 |
  | `length` | metres of laser | 2 |
  | `radius` | metres | 0.002 |

  The long press's settings are `pointer`'s.
- `vr/pointer/laser = {}`: the laser, a child of the player.

It writes `pointer/ray` from the right hand (`vr/input/pose`) and takes it off when it goes. `vr/input` maps the right trigger to the left mouse button and the right stick's up and down to the wheel, which `pointer`'s bindings read.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `vr/pointer/init` | On an added `vr/pointer`, spawn the laser as the player's child, hidden |
| First | `vr/pointer/removed` | When `vr/pointer` goes, take `pointer/ray` off |
| PreUpdate | `vr/pointer/ray` | On a changed `vr/input/pose` or `vr/pointer`, write `pointer/ray`, turned in the controller's own frame |
| Update, after `pointer/cast` | `vr/pointer/laser` | On a changed ray, the laser along it in the player's frame, shown only while a target is hovered (`pointer/hovered`) |

## Notes

- The cast uses Bevy's default visibility: a mesh counts only while a view sees it, so a hidden panel takes no pointer. It skips the player and everything under it (the laser, its body).
- A mesh the ray can meet needs an `Aabb`. Bevy computes one only for a mesh with none and without `NoFrustumCulling`, so a target with `NoFrustumCulling` is never met, and a target whose mesh changes takes its `Aabb` off for Bevy to compute again.
- Suites: `vr/pointer/tests/test_vr_pointer.lua` (headless: the base it brings and its bindings, the ray, the laser, reload, removal) and `vr/ui_panels/tests/test_vr_ui_panels_windowed.lua` (the cast, hover, clicks, the laser in view). No headset is involved.
