---
depends_on: [camera, transform/follow]
conflicts_with: []
exposes: [camera/3d, camera/3d/eye]
---

# camera/3d

The eye of a 3D camera. Extends `camera` (`base = "camera"`). The local player's carrier gets an eye: a Camera3d child turned to the carrier's `camera` yaw and pitch and placed at `camera/3d.offset` from the carrier. The eye moves with the carrier but does not turn with it (`transform/follow`). Remote carriers get no eye.

Camera mods that look through a 3D eye (`camera/first_person`, `camera/third_person`) extend this one with `base = "camera/3d"` and write only the offset; they never touch the eye. Switching between them keeps the same eye.

## Components

- `camera/3d = { offset = { x, y, z } }`: where the eye sits relative to the carrier, in world space. The camera mod extending this one writes it. Missing when added, it defaults to the carrier's origin.
- `camera/3d/eye = {}`: marks the eye, a child of the carrier. Added and despawned by this mod.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First | Camera3dInit | On an added `camera/3d`, fill in a missing offset |
| First | CameraSpawn | On the local carrier, spawn the eye already aimed, or turn the existing eye back on |
| First | CameraTeardown | When the player leaves for another world (`core/net/local` removed), turn the eye off |
| Update, after `Camera` and `CameraAim` | Camera3dAim | When `camera` or `camera/3d` changes, set the eye's `transform/follow` rotation (yaw, then pitch) and offset |

## Use

```lua
-- in a camera mod's client half: place the eye, after your own system that turns `camera`
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        ["or"] = { changed = { "camera" }, added = { "my/camera", "camera/3d" } },
        with = { "camera", "camera/3d", "my/camera" },
    })) do
        local cam = e:get("camera")
        e:patch({ ["camera/3d"] = { offset = { x = 0, y = cam.height, z = 0 } } })
    end
end, { label = "CameraAim", after = { "Camera" } })

return { base = "camera/3d" }

-- find a player's eye: `entities` also matches descendants
world:query({ entities = { player:id() }, with = { "camera/3d/eye" } })
```

## Notes

- Write `camera/3d` only once it exists (`with = { "camera/3d" }`). Writing it first puts it on the entity directly, and it then stays when your mod is removed.
- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can be a frame after `camera/3d`. A new eye starts level and is turned when the defaults arrive. A mod reading `camera` fields must allow for them being missing until then.
- Label your offset writer `CameraAim`; `Camera3dAim` runs after it, so the eye moves in the frame the look changes.
- The server half only chains the base to `camera`. The eye and offset are the client's view and are not synced.
- The eye is a child, so it despawns with its carrier.
