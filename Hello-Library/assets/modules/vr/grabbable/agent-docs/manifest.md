---
depends_on: [input, vr/input, vr/pointer]
conflicts_with: []
exposes: [vr/grabbable, vr/grabbable/target, vr/grabbable/held]
---

# vr/grabbable

The grip grabs what the pointer's ray is on, on this client's own player in VR, and carries it along the ray at the distance it was grabbed. `player/vr` adds it on the owning client while the player is in VR, and it never crosses.

## Components

- `vr/grabbable = {}`, on the player.
- `vr/grabbable/target = { face }`: on what can be grabbed, added and removed by the mod that makes it (`vr/ui_panels`). `face = true` turns it about Y while held so its front (+Z) faces the head. Default `face = false`.
- `vr/grabbable/held = { distance, offset }`: on the target while held: metres along the ray to the grabbed point, and from that point to the target's translation.

Binding: `input/ui.vr_grabbable = { grab = { key = "KeyG" } }`, which `vr/input` maps to the right grip, so grabbing works while UI input is on (an open sidebar).

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `vr/grabbable/bind` | On `vr/grabbable` or `input` arriving, bind `input/ui.vr_grabbable` |
| First | `vr/grabbable/removed` | When `vr/grabbable` goes, unbind and drop what is held |
| Update | `vr/grabbable/grab` | On the grab action's `added` edge, cast `vr/pointer/ray` with `MeshRayCast`, meeting only targets; the nearest gets `vr/grabbable/held` |
| Update | `vr/grabbable/release` | On the action's `removed` edge, drop what is held |
| Update, after `vr/grabbable/grab` | `vr/grabbable/move` | On a changed ray, the held target along it, facing the head if it asks to |

## Use

```lua
commands:spawn({ Mesh3d = mesh, Transform = {}, ["vr/grabbable/target"] = { face = true } })
```

## Notes

- A target's `Transform` is taken as its place in the world, so only a root target moves as expected.
- Facing uses `Quat.from_rotation_arc` between level directions: exactly opposite ones may turn about another axis.
- Suites: the grab and its move are in `vr/ui_panels/tests/test_vr_ui_panels_windowed.lua`, as a ray meets only what a view sees; the bindings are in `vr/pointer/tests/test_vr_pointer.lua`.
