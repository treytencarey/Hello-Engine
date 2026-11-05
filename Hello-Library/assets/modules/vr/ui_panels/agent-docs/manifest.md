---
depends_on: [sidebar, vr/input, vr/pointer, vr/grabbable]
conflicts_with: []
exposes: [vr/ui_panels, vr/ui_panels/panel, vr/ui_panels/panels, vr/ui_panels/camera]
---

# vr/ui_panels

The sidebar as a panel in the world, for this client's own player in VR. The sidebar's container is drawn into an image by a camera of its own, and the image is shown on a mesh the pointer can point at and the grip can carry. Each time the sidebar opens, the panel is placed in front of the right hand again, facing the head. `player/vr` adds it on the owning client while the player is in VR, and it never crosses.

## Components

- `vr/ui_panels = { pixels_to_meters, distance, min_distance, z_index_scale, camera_order }`, on the player:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `pixels_to_meters` | metres per pixel of the panel | 0.0008 |
  | `distance` | metres in front of the hand | 0.6 |
  | `min_distance` | the least it comes to | 0.35 |
  | `z_index_scale` | metres nearer for each step of the container's `GlobalZIndex` | 0.0003 |
  | `camera_order` | the panel camera's order | -200 |

- `vr/ui_panels/panel = { entity, width, height, image }`: on the panel's mesh, a world root. A relationship to its container (`entity`), with `linked_spawn`: the panel goes with the container.
- `vr/ui_panels/panels`: on the container, its panels, kept by the engine.
- `vr/ui_panels/camera = {}`: the `Camera2d` drawing the container into the image, a child of the mesh.

The mesh also carries `vr/pointer/target` (the image and its size) and `vr/grabbable/target = { face = true }`. The container gets `UiTargetCamera` naming the panel's camera, and loses it when `vr/ui_panels` goes.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `vr/ui_panels/build` | On an added container, a changed `ComputedNode` or the player's first pose: build the panel once the container has a size, or swap in a new image, mesh and material when the size changed, taking the old `Aabb` off |
| First, after `vr/ui_panels/build` | `vr/ui_panels/show` | On a changed `Node`: closed, the panel hides and its camera stops; opened, it is placed in front of the hand, shows, and its camera runs |
| First | `vr/ui_panels/removed` | When `vr/ui_panels` goes, despawn the panels and take `UiTargetCamera` off the containers |

## Use

A world does not add it: `player/vr` does, on this client's player in VR. Opening the sidebar shows the panel.

## Notes

- The container is laid out against the window first, and against the image once it targets the panel's camera, so the panel may resize once after it is built.
- After a reload the container still names the old, despawned camera. A UI root targeting no camera is not laid out again, so a container with no panel loses it and goes back to the window's camera.
- The panel has no `NoFrustumCulling`: Bevy gives no `Aabb` to a mesh with it, and the ray cast meets no mesh without one. Bevy computes an `Aabb` only for a mesh with none, so a resize takes it off. That a headset's eyes cull the panel correctly is not checked.
- The panel is drawn from the front only (the material's default culling); the ray cannot meet its back either.
- Taking the mod off logs one warning: the registry tries to remove `vr/ui_panels/panels`, a relationship target only the engine writes, and is refused.
- Suites: `vr/ui_panels/tests/test_vr_ui_panels.lua` (headless, with the container's `ComputedNode` written in the layout's place: build, placement, resize, hide and reopen, reload, removal) and `test_vr_ui_panels_windowed.lua` (the real sidebar drawn and picked, with the pointer and the grip). A panel showing in a headset is not checked.
