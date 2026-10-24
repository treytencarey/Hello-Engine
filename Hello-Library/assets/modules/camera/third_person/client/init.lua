-- A third-person orbit camera: mouse motion turns the carrier's `camera` yaw and pitch, the
-- scroll wheel changes its distance, and the eye (`camera/3d`) orbits the carrier at
-- `camera.distance`, `camera.height` above it and `camera.offset` to the side, looking at
-- the carrier. `camera/3d` spawns, turns and removes the eye.
--
-- camera/third_person = {
--     sensitivity = <radians turned per unit of mouse motion>,
--     min_pitch = <radians, the lowest look>,
--     max_pitch = <radians, the highest look>,
--     zoom_step = <metres per unit of scroll>,
--     min_distance = <metres>,
--     max_distance = <metres>,
-- }

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

app:add_systems(First, {
    Query[{ added = { Mut["camera/third_person"] } }],
}, function(added)
    for _, e in ipairs(added:iter_mut()) do
        local tp = e:get("camera/third_person")
        e:patch({
            ["camera/third_person"] = {
                sensitivity = tp.sensitivity or 0.003,
                min_pitch = tp.min_pitch or -1.2,
                max_pitch = tp.max_pitch or 0.2,
                zoom_step = tp.zoom_step or 0.5,
                min_distance = tp.min_distance or 2,
                max_distance = tp.max_distance or 20,
            },
        })
    end
end):in_set("camera/third_person/init")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/third_person", "core/net/local", "input" },
        },
        with = { "camera/third_person", "core/net/local" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        commands:entity(e:id()):patch({
            ["input/game"] = {
                third_person = {
                    look = { motion = true },
                    zoom = { scroll = true },
                },
            },
        })
    end
end):in_set("camera/third_person/bind")

app:add_systems(First, {
    Query[{
        removed = { "camera/third_person" },
        with = { "input/game" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        -- `removed` also fires on despawn, and a patch to an entity that is gone fails.
        local carrier = commands:get_entity(e:id())
        if carrier ~= nil then
            carrier:patch({ ["input/game"] = { third_person = null } })
        end
    end
end):in_set("camera/third_person/unbind")

-- Look and zoom patch different fields of `camera`, so a look and a zoom in one frame both land.
app:add_systems(Update, {
    Query[{
        changed = { "input/game/third_person/look" },
        with = { Mut["camera"], "camera/third_person" },
    }],
}, function(carriers)
    for _, e in ipairs(carriers:iter_mut()) do
        local cam = e:get("camera")
        local tp = e:get("camera/third_person")
        local look = e:get("input/game/third_person/look")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.pitch ~= nil then
            local pitch = cam.pitch - look.dy * tp.sensitivity
            e:patch({
                camera = {
                    yaw = cam.yaw - look.dx * tp.sensitivity,
                    pitch = math.max(tp.min_pitch, math.min(tp.max_pitch, pitch)),
                },
            })
        end
    end
end):in_set("camera/third_person"):before("camera/3d/aim")

app:add_systems(Update, {
    Query[{
        changed = { "input/game/third_person/zoom" },
        with = { Mut["camera"], "camera/third_person" },
    }],
}, function(carriers)
    for _, e in ipairs(carriers:iter_mut()) do
        local cam = e:get("camera")
        local tp = e:get("camera/third_person")
        local zoom = e:get("input/game/third_person/zoom")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.distance ~= nil then
            local distance = cam.distance - zoom.dy * tp.zoom_step
            e:patch({
                camera = {
                    distance = math.max(tp.min_distance, math.min(tp.max_distance, distance)),
                },
            })
        end
    end
end):in_set("camera/third_person/zoom")

-- The eye orbits the carrier: `distance` back along the pitched look, then `height` up and
-- `offset` to the side, all turned by the yaw. Written only once `camera/3d` exists: writing it earlier would put
-- the base on the entity directly, and it would not leave with this mod.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            changed = { "camera" },
            added = { "camera/third_person", "camera/3d" },
        },
        with = { "camera", Mut["camera/3d"], "camera/third_person" },
    }],
}, function(carriers)
    for _, e in ipairs(carriers:iter_mut()) do
        local cam = e:get("camera")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.distance ~= nil then
            local back = Quat.mul_vec3(Quat.from_rotation_x(cam.pitch),
                { x = 0, y = 0, z = cam.distance })
            e:patch({
                ["camera/3d"] = {
                    offset = Quat.mul_vec3(Quat.from_rotation_y(cam.yaw),
                        Vec3.add(Vec3.add(back, cam.offset),
                            { x = 0, y = cam.height, z = 0 })),
                },
            })
        end
    end
end):in_set("camera/third_person/aim")
    :after("camera/third_person")
    :after("camera/third_person/zoom")
    :before("camera/3d/aim")

return { base = "camera/3d" }
