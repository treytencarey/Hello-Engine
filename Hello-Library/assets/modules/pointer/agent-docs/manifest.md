---
depends_on: [input]
conflicts_with: []
exposes: [pointer, pointer/ray, pointer/target, pointer/hovered, pointer/press]
---

# pointer

A ray turned into Bevy's picking on a screen, for this client's own player. When the first thing the player's `pointer/ray` meets is a pointer target, Bevy's picking hears it as the mouse pointer on that target's image: it moves there, scrolls, presses, and a long press is a right click. While the ray is on a target the wheel is the screen's, and the camera does not zoom.

`pointer` is the base of the ray sources, and decides nothing about where the ray comes from. A source writes `pointer/ray` and has `pointer` as its base: `pointer/view` is the desktop's ray cast, from the view's centre or through the cursor; `vr/pointer` is only the VR controller's ray cast, plus its laser. Attach a source, never `pointer` itself: the source's base brings it.

## Components

- `pointer = { long_press, long_press_tolerance }`, on the player, added by a source's base:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `long_press` | seconds a press is held still to be a right click | 0.5 |
  | `long_press_tolerance` | pixels it may move and still count as still | 15 |

- `pointer/ray = { origin, direction }`, on the player: the ray in world space, written by its source and taken off by it. Other mods read it (`vr/grabbable`, `placement`).
- `pointer/target = { image, width, height }`: on a mesh showing a render-target image, added and removed by the mod that makes the mesh, usually `ui/screen`. Only these answer the ray. Being a part of `pointer`, it is taken off every entity when the last source goes; `ui/screen` gives its own back.
- `pointer/hovered = { x, y }`: on the target the ray is on, in its image's pixels. Exists while hovered.
- `pointer/press = { at, x, y, long }`, on the player while a press that began on a target is held: when it was pressed (`at`, absent once it moved too far for a long press), where on the target, and whether the long press was sent.

Bindings, in `input/game` and `input/ui`: `pointer = { press = { button = "Left" }, scroll = { scroll = true } }`. While a target is hovered the scroll binding is `{ scroll = true, take = true }`, which takes the wheel from the mode's other scroll bindings (`input`'s take), and it goes back when the ray leaves. `vr/input` maps the VR controller's trigger and stick to the same button and wheel.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `pointer/bind` | On `pointer` or `input` arriving, bind the `pointer` group in both modes |
| First | `pointer/removed` | When `pointer` goes, unbind, take `pointer/ray` and `pointer/press` off, and `pointer/hovered` off the target |
| Update | `pointer/cast` | On a changed ray, cast it with `MeshRayCast`, past the player and its descendants. A target hit: `pointer/hovered` moves, and `PointerInput` Move, and Scroll while a scroll action is there. The ray leaving a target: a Move off its image, so Bevy's hover goes, and the wheel is given back |
| Update, after the cast | `pointer/press` | On the press action's edges, `PointerInput` Press and Release Primary on the hovered target |
| Update, after the press | `pointer/long_press` | Polls `Time` while pressed: held still for `long_press`, Press and Release Secondary |

## Use

```lua
-- make a mesh a pointer target: it shows `image`, `width` x `height` pixels
commands:spawn({ Mesh3d = mesh, ["pointer/target"] = { image = image, width = w, height = h } })

-- a ray source of a new kind: write the ray on this client's own player; its file returns
-- { base = "pointer" }
commands:entity(player):insert({ ["pointer/ray"] = { origin = o, direction = d } })
```

## Notes

- The mouse pointer is reused: a pointer of its own would be `PointerId::Custom`, which Lua cannot build. Bevy's picking presses what a pointer hovers, and only a move moves it; in game input the hidden cursor sends no move, so without the move off the image the mouse's next click would land where the ray last was.
- Bevy's picking skips a move with no delta, so a ray held still sends none.
- A press, release and long press act on the hovered target; a release after a long press sends no primary release, so it does not also click.
- Suites: `vr/pointer/tests/test_vr_pointer.lua` (headless: the base and its bindings, both sources' rays, removal); `vr/ui_panels/tests/test_vr_ui_panels_windowed.lua` (a ray meets only what a view sees: hover, the wheel taken while on a panel and given back, the mouse's own click after the ray left clicking nothing, press, long press).
