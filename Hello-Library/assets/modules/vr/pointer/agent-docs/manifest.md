---
depends_on: [input, vr/input]
conflicts_with: []
exposes: [vr/pointer, vr/pointer/ray, vr/pointer/press, vr/pointer/target, vr/pointer/hovered, vr/pointer/laser]
---

# vr/pointer

The right hand as a pointer, on this client's own player in VR. When the first thing a ray from the controller meets is a pointer target, Bevy's picking hears it as the mouse pointer on that target's image: moves, scrolls, presses, and a long press as a right click. A laser shows the ray while it is on a target. `player/vr` adds it on the owning client while the player is in VR, and it never crosses.

## Components

- `vr/pointer = { pitch, yaw, long_press, long_press_tolerance, length, radius }`, on the player:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `pitch` | degrees the ray tilts down from the controller's forward, in the controller's own frame | -60 |
  | `yaw` | degrees it turns about the controller's up | -10 |
  | `long_press` | seconds a press is held still to be a right click | 0.5 |
  | `long_press_tolerance` | pixels it may move and still count as still | 15 |
  | `length` | metres of laser | 2 |
  | `radius` | metres | 0.002 |

- `vr/pointer/ray = { origin, direction }`, on the player: the ray in world space, from `vr/input/pose`, replaced with each pose. Other mods read it (`vr/grabbable`).
- `vr/pointer/press = { at, x, y, long }`, on the player while a press that began on a target is held: when it was pressed (`at`, absent once it moved too far for a long press), where on the target, and whether the long press was sent.
- `vr/pointer/target = { image, width, height }`: on a mesh showing a render-target image, added and removed by the mod that makes the mesh (`vr/ui_panels`). Only these answer the ray.
- `vr/pointer/hovered = { x, y }`: on the target the ray is on, in its image's pixels. Exists while hovered.
- `vr/pointer/laser = {}`: the laser, a child of the player.

Bindings: `input/ui.vr_pointer = { press = { button = "Left" }, scroll = { scroll = true } }`, so the pointer acts while UI input is on (an open sidebar). `vr/input` maps the right trigger to the left mouse button and the right stick's up and down to the wheel.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `vr/pointer/bind` | On `vr/pointer` or `input` arriving, bind `input/ui.vr_pointer` |
| First | `vr/pointer/init` | On an added `vr/pointer`, spawn the laser as the player's child, hidden |
| First | `vr/pointer/removed` | When `vr/pointer` goes, unbind and take `vr/pointer/hovered` off the target |
| PreUpdate | `vr/pointer/ray` | On a changed `vr/input/pose` or `vr/pointer`, write `vr/pointer/ray` |
| Update | `vr/pointer/cast` | On a changed ray, cast it with `MeshRayCast`, past the player and its descendants; if the first hit is a target, move `vr/pointer/hovered`; write `PointerInput` Move, and Scroll while the scroll action is there |
| Update, after `vr/pointer/cast` | `vr/pointer/press` | On the press action's edges, `PointerInput` Press and Release Primary on the hovered target |
| Update, after `vr/pointer/press` | `vr/pointer/long_press` | Polls `Time` while pressed: held still for `long_press`, Press and Release Secondary |
| Update, after `vr/pointer/cast` | `vr/pointer/laser` | On a changed ray, the laser along it in the player's frame, shown only while a target is hovered |

## Use

```lua
-- make a mesh a pointer target: it shows `image`, `width` x `height` pixels
commands:spawn({
    Mesh3d = mesh,
    ["MeshMaterial3d<StandardMaterial>"] = materials:add({ base_color_texture = image, unlit = true }),
    ["vr/pointer/target"] = { image = image, width = 512, height = 256 },
})
```

## Notes

- The cast uses Bevy's default visibility: a mesh counts only while a view sees it, so a hidden panel takes no pointer. Its `filter` skips the player and everything under it (the laser, its body): a player is a root, so they share its root. Anything else, a wall included, stands in front of a target behind it.
- A mesh the ray can meet needs an `Aabb`. Bevy computes one only for a mesh with none and without `NoFrustumCulling`, so a target with `NoFrustumCulling` is never met, and a target whose mesh changes takes its `Aabb` off for Bevy to compute again.
- The mouse pointer is reused, as Lua cannot build `PointerId::Custom`. Bevy's picking skips a move with no delta, so a ray held still sends none, and the first move on a target carries a tiny one.
- A release after a long press sends no primary release, so the press does not also click.
- Suites: `vr/pointer/tests/test_vr_pointer.lua` (headless: bindings, the ray, the laser, reload, removal) and `vr/ui_panels/tests/test_vr_ui_panels_windowed.lua` (the cast, hover, clicks, the laser in view). No headset is involved.
