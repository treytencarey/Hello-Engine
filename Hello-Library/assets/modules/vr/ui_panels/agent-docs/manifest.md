---
depends_on: [sidebar, vr/input, ui/screen, vr/grabbable]
conflicts_with: []
exposes: [vr/ui_panels, vr/ui_panels/panel, vr/ui_panels/panels]
---

# vr/ui_panels

The sidebar as a panel in the world, for this client's own player in VR. The panel is a mesh carrying `ui/screen`, which draws UI into an image on it and makes it a pointer target; the sidebar's container is pointed at the screen's camera, and the screen's own root is left empty. The grip can carry it. Each time the sidebar opens, the panel is placed in front of the right hand again, facing the head. `player/vr` adds it on the owning client while the player is in VR, and it never crosses.

## Components

- `vr/ui_panels = { pixels_to_meters, distance, min_distance, z_index_scale }`, on the player:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `pixels_to_meters` | metres per pixel of the panel | 0.0008 |
  | `distance` | metres in front of the hand | 0.6 |
  | `min_distance` | the least it comes to | 0.35 |
  | `z_index_scale` | metres nearer for each step of the container's `GlobalZIndex` | 0.0003 |

- `vr/ui_panels/panel = { entity, width, height }`: on the panel's mesh, a world root. A relationship to its container (`entity`), with `linked_spawn`: the panel goes with the container.
- `vr/ui_panels/panels`: on the container, its panels, kept by the engine.
The mesh also carries `ui/screen = { width, height }`, the container's size, and `vr/grabbable/target = { face = true }`; `ui/screen` gives it the image, `pointer/target` and the `ui/screen/camera` child. The container gets `UiTargetCamera` naming that camera, and loses it when `vr/ui_panels` goes.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `vr/ui_panels/build` | On an added container, a changed `ComputedNode` or the player's first pose: build the panel once the container has a size, or swap in a new mesh and the screen's new size when the size changed, taking the old `Aabb` off |
| First | `vr/ui_panels/target` | On an added `ui/screen/camera` under a panel: point the panel's container at it |
| First, after `vr/ui_panels/build` | `vr/ui_panels/show` | On a changed `Node`: closed, the panel hides and its camera stops; opened, it is placed in front of the hand, shows, and its camera runs |
| First | `vr/ui_panels/removed` | When `vr/ui_panels` goes, despawn the panels and take `UiTargetCamera` off the containers |

## Use

A world does not add it: `player/vr` does, on this client's player in VR. Opening the sidebar shows the panel.

## Notes

- The container is pointed at the screen's camera a frame after the panel is built, when `ui/screen` has made it. Until then it is laid out against the window, and against the image after, so the panel may resize once after it is built.
- The screen's own root shares the camera with the container. The container's `GlobalZIndex` draws it above the root, which neither blocks nor hovers either, so the pointer reaches the container.
- After a reload the container still names the old, despawned camera. A UI root targeting no camera is not laid out again, so a container with no panel loses it and goes back to the window's camera.
- The panel has no `NoFrustumCulling`: Bevy gives no `Aabb` to a mesh with it, and the ray cast meets no mesh without one. Bevy computes an `Aabb` only for a mesh with none, so a resize takes it off. That a headset's eyes cull the panel correctly is not checked.
- The panel is drawn from the front only (the material's default culling); the ray cannot meet its back either.
- Taking the mod off logs one warning: the registry tries to remove `vr/ui_panels/panels`, a relationship target only the engine writes, and is refused.
- Suites: `vr/ui_panels/tests/test_vr_ui_panels.lua` (headless, with the container's `ComputedNode` written in the layout's place: build, placement, resize, hide and reopen, reload, removal) and `test_vr_ui_panels_windowed.lua` (the real sidebar drawn and picked, with the pointer and the grip). A panel showing in a headset is not checked.
