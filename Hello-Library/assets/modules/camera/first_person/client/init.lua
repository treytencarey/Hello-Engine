-- A first-person camera: mouse motion turns the carrier's `camera` yaw and pitch, and the
-- eye (`camera/3d`) sits at the carrier's head. `camera/3d` spawns, turns and removes the eye.
--
-- camera/first_person = {
--     sensitivity = <radians turned per unit of mouse motion>,
--     pitch_limit = <radians up or down from level>,
-- }

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/first_person", "core/net/local", "input" },
        },
        with = { "camera/first_person", "core/net/local" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        commands:entity(e:id()):patch({
            ["input/game"] = {
                first_person = {
                    look = { motion = true },
                },
            },
        })
    end
end):in_set("camera/first_person/bind")

app:add_systems(First, {
    Query[{
        removed = { "camera/first_person" },
        with = { "input/game" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        -- `removed` also fires on despawn, and a patch to an entity that is gone fails.
        local carrier = commands:get_entity(e:id())
        if carrier ~= nil then
            carrier:patch({ ["input/game"] = { first_person = null } })
        end
    end
end):in_set("camera/first_person/unbind")

-- Before `camera/3d` aims, so the eye turns in the frame the look arrives.
app:add_systems(Update, {
    Query[{
        changed = { "input/game/first_person/look" },
        with = { Mut["camera"], "camera/first_person" },
    }],
}, function(carriers)
    for _, e in ipairs(carriers:iter_mut()) do
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
end):in_set("camera/first_person"):before("camera/3d/aim")

-- The eye sits at the head. Written only once `camera/3d` exists: writing it earlier would
-- put the base on the entity directly, and it would not leave with this mod.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            changed = { "camera" },
            added = { "camera/first_person", "camera/3d" },
        },
        with = { "camera", Mut["camera/3d"], "camera/first_person" },
    }],
}, function(carriers)
    for _, e in ipairs(carriers:iter_mut()) do
        local cam = e:get("camera")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.height ~= nil then
            e:patch({ ["camera/3d"] = { offset = { x = 0, y = cam.height, z = 0 } } })
        end
    end
end):in_set("camera/first_person/aim"):before("camera/3d/aim")

return {
    base = "camera/3d",
    defaults = {
        ["camera/first_person"] = {
            sensitivity = 0.0025,
            pitch_limit = 1.4,
        },
    },
}
