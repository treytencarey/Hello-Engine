---
depends_on: []
conflicts_with: []
exposes: [camera]
---

# camera

A camera's view state on an entity. Camera mods extend it and drive it: `camera/3d` (`base = "camera"`) owns a Camera3d eye for `camera/first_person` and `camera/third_person` (`base = "camera/3d"`); `camera/2d` and `camera/vr` extend `camera` and handle their own camera. The client owns it: the owner's client writes it, and only that client receives it.

## Components

- `camera = { yaw = <radians>, pitch = <radians>, distance = <metres from the target>, height = <metres above the target>, offset = { x, y, z } }`. Fields missing when it is added get defaults (yaw 0, pitch -0.3, distance 8, height 1.5, offset { x = 1, y = 0, z = 0 }). State carried from another world is kept.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First (client) | CameraInit | On an added `camera`, fill in missing fields |

## Use

```lua
player:patch({ camera = { distance = 12 } })   -- the rest get defaults

-- a camera mod that orders itself after the defaults
register_system("First", function(world)
    -- read `camera`, move your Camera3d
end, { after = { "CameraInit" } })
```

## Notes

- The server half only declares sync (client authority, sent to the owner); it sets no defaults.
