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

| Schedule | Set | Purpose |
|----------|-------|---------|

## Use

```lua
commands:entity(player):patch({ camera = { distance = 12 } })   -- the rest get defaults

-- a camera mod: every field is there once this mod has loaded
app:add_systems(First, {
    Query[{ changed = { "camera" } }],
}, function(cameras)
    for _, e in ipairs(cameras:iter()) do
        -- read `camera`, move your Camera3d
    end
end):in_set("my/camera")
```

## Notes

- The server half only declares sync (client authority, sent to the owner); it declares no defaults.
- A player handed over through a portal to another world's server keeps its `yaw`, `pitch` and `distance`: `player/spawner` sends them in the switch, and the target's spawner spawns the player with them and with this component's sync, so they reach the owner in the spawn, before the client's own defaults would. `height` and `offset` are the new world's.
