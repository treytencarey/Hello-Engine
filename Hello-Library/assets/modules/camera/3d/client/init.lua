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
local app = ...
local Quat = require("bevy::math::Quat")

local function follow(cam, c3d)
    local yaw = Quat.from_rotation_y(cam.yaw or 0)
    local pitch = Quat.from_rotation_x(cam.pitch or 0)
    return {
        rotation = Quat.mul_quat(yaw, pitch),
        offset = c3d.offset,
    }
end

app:add_systems(First, {
    Query[{ added = { Mut["camera/3d"] } }],
}, function(added)
    for _, e in ipairs(added:iter_mut()) do
        local c3d = e:get("camera/3d")
        e:patch({
            ["camera/3d"] = {
                offset = c3d.offset or { x = 0, y = 0, z = 0 },
            },
        })
    end
end):in_set("camera/3d/init")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/3d", "camera", "core/net/local" },
        },
        with = { "camera/3d", "camera", "core/net/local" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/3d/eye", Mut["Camera"] },
    }],
    Commands,
}, function(carriers, all_eyes, commands)
    for _, e in ipairs(carriers:iter()) do
        local cam = e:get("camera")
        local c3d = e:get("camera/3d")
        local eyes = all_eyes:iter_many_mut(e:get("Children") or {})
        for _, eye in ipairs(eyes) do
            eye:patch({ Camera = { is_active = true } })
        end
        if #eyes == 0 then
            local eye = commands:spawn({
                Camera3d = {},
                Camera = { order = 0, is_active = true },
                Transform = {},
                IsDefaultUiCamera = true,
                ["transform/follow"] = follow(cam, c3d),
                ["camera/3d/eye"] = {},
            }):id()
            commands:entity(e:id()):add_child(eye)
        end
    end
end):in_set("camera/3d/spawn")

-- The player left for another world: its eye stops rendering this one.
app:add_systems(First, {
    Query[{
        removed = { "core/net/local" },
        with = { "camera/3d" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/3d/eye", Mut["Camera"] },
    }],
}, function(carriers, all_eyes)
    for _, e in ipairs(carriers:iter()) do
        for _, eye in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
            eye:patch({ Camera = { is_active = false } })
        end
    end
end):in_set("camera/3d/teardown")

-- The camera mods extending this one order their writes of `camera` and `camera/3d` before
-- this system, so the eye turns and moves in the frame they change.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            changed = { "camera", "camera/3d" },
        },
        with = { "camera", "camera/3d" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/3d/eye", Mut["transform/follow"] },
    }],
}, function(carriers, all_eyes)
    for _, e in ipairs(carriers:iter()) do
        local cam = e:get("camera")
        local c3d = e:get("camera/3d")
        for _, eye in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
            eye:patch({ ["transform/follow"] = follow(cam, c3d) })
        end
    end
end):in_set("camera/3d/aim")

return { base = "camera" }
