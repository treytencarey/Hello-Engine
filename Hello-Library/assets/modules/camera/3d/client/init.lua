-- The eye of a 3D camera: a Camera3d child of the carrier, turned to the carrier's
-- `camera` yaw and pitch and placed at `camera/3d.offset` from it. The eye follows the
-- carrier but not its rotation (`transform/follow`). The camera mod extending this one
-- (first_person, third_person) writes the offset. Only the local player's carrier gets
-- an eye. It turns off while the player is in another world, goes with the carrier when
-- it despawns, and is despawned when `camera/3d` is removed.
--
-- camera/3d = {
--     offset = { x = <metres>, y = <metres>, z = <metres> },  -- from the carrier, world space
-- }
--
-- camera/3d/eye = {}

-- `camera` arrives as `{}` and its own mod may load a frame later, so a new eye can be
-- spawned before `camera` has its defaults. It starts level; filling them is a change to
-- `camera`, and Camera3dAim turns the eye then.
local function follow(world, cam, c3d)
    local yaw = world:call_static_method("Quat", "from_rotation_y", cam.yaw or 0)
    local pitch = world:call_static_method("Quat", "from_rotation_x", cam.pitch or 0)
    return {
        rotation = world:call_static_method("Quat", "mul_quat", yaw, pitch),
        offset = c3d.offset,
    }
end

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "camera/3d" } })) do
        local c3d = e:get("camera/3d")
        e:patch({
            ["camera/3d"] = {
                offset = c3d.offset or { x = 0, y = 0, z = 0 },
            },
        })
    end
end, { label = "Camera3dInit" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "camera/3d", "camera", "core/net/local" },
        },
        with = { "camera/3d", "camera", "core/net/local" },
    })) do
        local cam = e:get("camera")
        local c3d = e:get("camera/3d")
        local eyes = world:query({
            entities = { e:id() },
            with = { "camera/3d/eye", "Camera" },
        })
        for _, eye in ipairs(eyes) do
            eye:patch({ Camera = { is_active = true } })
        end
        if #eyes == 0 then
            spawn({
                Camera3d = {},
                Camera = { order = 0, is_active = true },
                Transform = {},
                IsDefaultUiCamera = true,
                ["transform/follow"] = follow(world, cam, c3d),
                ["camera/3d/eye"] = {},
            }):with_parent(e:id())
        end
    end
end, { label = "CameraSpawn" })

-- The player left for another world: its eye stops rendering this one.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "core/net/local" },
        with = { "camera/3d" },
    })) do
        for _, eye in ipairs(world:query({
            entities = { e:id() },
            with = { "camera/3d/eye", "Camera" },
        })) do
            eye:patch({ Camera = { is_active = false } })
        end
    end
end, { label = "CameraTeardown" })

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            changed = { "camera", "camera/3d" },
        },
        with = { "camera", "camera/3d" },
    })) do
        local cam = e:get("camera")
        local c3d = e:get("camera/3d")
        for _, eye in ipairs(world:query({
            entities = { e:id() },
            with = { "camera/3d/eye" },
        })) do
            eye:patch({ ["transform/follow"] = follow(world, cam, c3d) })
        end
    end
end, { label = "Camera3dAim", after = { "Camera", "CameraAim" } })

return { base = "camera" }
