-- A top-down 2D camera: an eye, a Camera2d child of the carrier, kept `z` above it and
-- scaled by the carrier's `camera.distance` (1 is 1:1), which the scroll wheel changes. The eye follows
-- the carrier but not its rotation (`transform/follow`). Only the local player's carrier gets
-- an eye. It turns off while the player is in another world, goes with the carrier when it
-- despawns, and is despawned when `camera/2d` is removed.
--
-- camera/2d = {
--     zoom_step = <distance per unit of scroll>,
--     min_distance = <the closest view>,
--     max_distance = <the farthest view>,
--     z = <how far above the carrier the eye sits>,
-- }
--
-- camera/2d/eye = {}

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "camera/2d" } })) do
        local c2d = e:get("camera/2d")
        e:patch({
            ["camera/2d"] = {
                zoom_step = c2d.zoom_step or 0.1,
                min_distance = c2d.min_distance or 0.25,
                max_distance = c2d.max_distance or 4,
                z = c2d.z or 1000,
            },
        })
    end
end, { label = "Camera2dInit" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "camera/2d", "camera", "core/net/local" },
        },
        with = { "camera/2d", "camera", "core/net/local" },
    })) do
        local cam = e:get("camera")
        local c2d = e:get("camera/2d")
        local eyes = world:query({
            entities = { e:id() },
            with = { "camera/2d/eye", "Camera" },
        })
        for _, eye in ipairs(eyes) do
            eye:patch({ Camera = { is_active = true } })
        end
        if #eyes == 0 then
            -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which
            -- can be a frame later; the eye starts 1:1 and is scaled when they arrive.
            local scale = cam.distance or 1
            spawn({
                Camera2d = {},
                Camera = { order = 0, is_active = true },
                Transform = { scale = { x = scale, y = scale, z = 1 } },
                IsDefaultUiCamera = true,
                ["transform/follow"] = {
                    rotation = { x = 0, y = 0, z = 0, w = 1 },
                    offset = { x = 0, y = 0, z = c2d.z },
                },
                ["camera/2d/eye"] = {},
            }):with_parent(e:id())
        end
    end
end, { label = "CameraSpawn" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "camera/2d", "core/net/local", "input" },
        },
        with = { "camera/2d", "core/net/local" },
    })) do
        e:patch({
            ["input/game"] = {
                camera_2d = {
                    zoom = { scroll = true },
                },
            },
        })
    end
end, { label = "Camera2dBind" })

-- The player left for another world: its eye stops rendering this one.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "core/net/local" },
        with = { "camera/2d" },
    })) do
        for _, eye in ipairs(world:query({
            entities = { e:id() },
            with = { "camera/2d/eye", "Camera" },
        })) do
            eye:patch({ Camera = { is_active = false } })
        end
    end
end, { label = "CameraTeardown" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "camera/2d" },
    })) do
        e:patch({ ["input/game"] = { camera_2d = null } })
    end
end, { label = "CameraRemove" })

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        changed = { "input/game/camera_2d/zoom" },
        with = { "camera", "camera/2d" },
    })) do
        local cam = e:get("camera")
        local c2d = e:get("camera/2d")
        local zoom = e:get("input/game/camera_2d/zoom")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.distance ~= nil then
            local distance = cam.distance - zoom.dy * c2d.zoom_step
            e:patch({
                camera = {
                    distance = math.max(c2d.min_distance, math.min(c2d.max_distance, distance)),
                },
            })
        end
    end
end, { label = "CameraZoom" })

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            changed = { "camera", "camera/2d" },
        },
        with = { "camera", "camera/2d" },
    })) do
        local cam = e:get("camera")
        local c2d = e:get("camera/2d")
        if cam.distance ~= nil then
            for _, eye in ipairs(world:query({
                entities = { e:id() },
                with = { "camera/2d/eye" },
            })) do
                eye:patch({
                    Transform = { scale = { x = cam.distance, y = cam.distance, z = 1 } },
                    ["transform/follow"] = {
                        rotation = { x = 0, y = 0, z = 0, w = 1 },
                        offset = { x = 0, y = 0, z = c2d.z },
                    },
                })
            end
        end
    end
end, { label = "CameraAim", after = { "CameraZoom" } })

return { base = "camera" }
