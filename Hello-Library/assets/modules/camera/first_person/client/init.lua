-- A first-person camera: mouse motion turns the carrier's `camera` yaw and pitch, and the
-- eye (`camera/3d`) sits at the carrier's head. `camera/3d` spawns, turns and removes the eye.
--
-- camera/first_person = {
--     sensitivity = <radians turned per unit of mouse motion>,
--     pitch_limit = <radians up or down from level>,
-- }

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "camera/first_person" } })) do
        local fp = e:get("camera/first_person")
        e:patch({
            ["camera/first_person"] = {
                sensitivity = fp.sensitivity or 0.0025,
                pitch_limit = fp.pitch_limit or 1.4,
            },
        })
    end
end, { label = "CameraFirstPersonInit" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "camera/first_person", "core/net/local", "input" },
        },
        with = { "camera/first_person", "core/net/local" },
    })) do
        e:patch({
            ["input/game"] = {
                first_person = {
                    look = { motion = true },
                },
            },
        })
    end
end, { label = "CameraFirstPersonBind" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "camera/first_person" },
    })) do
        e:patch({ ["input/game"] = { first_person = null } })
    end
end, { label = "CameraFirstPersonUnbind" })

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        changed = { "input/game/first_person/look" },
        with = { "camera", "camera/first_person" },
    })) do
        local cam = e:get("camera")
        local fp = e:get("camera/first_person")
        local look = e:get("input/game/first_person/look")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.pitch ~= nil then
            local pitch = cam.pitch - look.dy * fp.sensitivity
            e:patch({
                camera = {
                    yaw = cam.yaw - look.dx * fp.sensitivity,
                    pitch = math.max(-fp.pitch_limit, math.min(fp.pitch_limit, pitch)),
                },
            })
        end
    end
end, { label = "Camera" })

-- The eye sits at the head. Written only once `camera/3d` exists: writing it earlier would
-- put the base on the entity directly, and it would not leave with this mod.
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            changed = { "camera" },
            added = { "camera/first_person", "camera/3d" },
        },
        with = { "camera", "camera/3d", "camera/first_person" },
    })) do
        local cam = e:get("camera")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.height ~= nil then
            e:patch({ ["camera/3d"] = { offset = { x = 0, y = cam.height, z = 0 } } })
        end
    end
end, { label = "CameraAim" })

return { base = "camera/3d" }
