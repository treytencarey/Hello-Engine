---
depends_on: [pointer, input, camera]
conflicts_with: []
exposes: [pointer/view]
---

# pointer/view

The desktop's ray cast for `pointer`. It uses `pointer` as its base, and is only the desktop's ray source, the way `vr/pointer` is the VR controller's: what the ray does on a screen is `pointer`'s.

## Components

- `pointer/view = {}`, on this client's own player, never synced. `player`'s client half adds it to the local player and takes it off with `player`. `player/vr` takes it off while the player is in VR, where `vr/pointer` is the source, and gives it back when VR ends.

It writes `pointer/ray` from the player's eye (`camera/3d/eye`): along the view's centre while the cursor is hidden (game input), and through the cursor while `input/mode.show_cursor` is on.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Update, before `pointer/cast` | `pointer/view` | Polls this client's own players with it: the eye's ray, as above, into `pointer/ray` |
| First | `pointer/view/removed` | When it goes, take `pointer/ray` off |

## Notes

- In game input the cursor is hidden and confined, not centred: it keeps a place of its own and drifts with the mouse, so it is not aimed through.
- In a world VM the camera draws into an image the size of the window's physical pixels, so the cursor is read in those. `viewport_to_world` fails while the camera has no target size, and the view's centre is used then.
- Suites: `vr/pointer/tests/test_vr_pointer.lua` (the base it brings, and its ray along the eye with the cursor hidden); `scope/portal/console/tests/test_console_windowed.lua` (the eye's ray working a console's screen in a window).
