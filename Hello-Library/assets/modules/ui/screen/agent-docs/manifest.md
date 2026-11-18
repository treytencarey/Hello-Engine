---
depends_on: [pointer]
conflicts_with: []
exposes: [ui/screen, ui/screen/camera, ui/screen/root]
---

# ui/screen

UI drawn on a mesh. `ui/screen` gives a mesh an image of its size, a camera of its own drawing UI into that image, a UI root on the camera, the image unlit on the mesh, and `pointer/target`, so a pointer's ray works the UI the way the mouse works the window's. A mod puts its UI under the screen's root, or points a root of its own at the screen's camera.

## Components

- `ui/screen = { width, height }`: on a mesh, the image's size in pixels. Added and removed by the mod that makes the mesh. A changed size builds a new image for the same camera and root.
- `ui/screen/camera = {}`: the `Camera2d` drawing the screen, a child of the mesh, order -200 (before the window's).
- `ui/screen/root = {}`: the screen's UI root, a `Node` of the image's size, with `UiTargetCamera` naming the screen's camera. A root of its own, not a child of the mesh: a UI node under a scene entity is not laid out. Its `Pickable` neither blocks nor hovers, so it never stands between the pointer and the UI on it, nor between the pointer and another root drawn by the same camera.

The mesh also gets `MeshMaterial3d<StandardMaterial>` (the image, unlit) and `pointer/target = { image, width, height }`. Taking `ui/screen` off takes those off and despawns the camera and the root; despawning the mesh takes the camera with it, and the root follows.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ui/screen/build` | On an added or changed `ui/screen` whose size differs from its `pointer/target`: a new image; the camera and root spawned the first time, retargeted and resized after; the material and `pointer/target` |
| First | `ui/screen/target_back` | On a removed `pointer/target` while `ui/screen` stays: build again |
| First | `ui/screen/taken_off` | On a removed `ui/screen` on a mesh that stays: take the material and `pointer/target` off, despawn the camera |
| First, after `ui/screen/taken_off` | `ui/screen/removed` | On a removed camera: despawn the roots naming no camera |

## Use

```lua
-- a 600 x 400 pixel screen on a mesh
commands:spawn({ Mesh3d = mesh, Transform = t, ["ui/screen"] = { width = 600, height = 400 } })

-- the UI goes under its root, found from the mesh's camera child:
-- the root is the `ui/screen/root` whose `UiTargetCamera` is that camera
commands:spawn({ Node = {...}, ChildOf = root })
```

## Notes

- `pointer/target` is a part of `pointer`: when the pointer's last source goes (the player gone), the registry takes it off every entity, and the screen builds again to have it back, with a new image.
- The camera and root come a frame after `ui/screen` is added. A mod pointing its own root at the camera reacts to the camera's added edge.
- The image's pixels are the pointer's: picking on the screen shares one pixel space with every root its camera draws.
- Suites: `vr/ui_panels/tests/test_vr_ui_panels.lua` (headless: the camera, the root empty and passing the pointer through, the size, the target given back, removal) and `vr/ui_panels/tests/test_vr_ui_panels_windowed.lua` (drawn and picked through a root of another mod).
