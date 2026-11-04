-- The camera of this client's player in VR. The headset's two eyes belong to the engine, and it
-- places them from `VmXrRig` on the player, the rig being where this player's tracking space is.
-- This mod writes it from the player's position and the right stick's turn. The window gets its
-- own camera at the headset's pose, as the eyes never draw there. `camera.yaw` is where the player
-- walks: where the head looks, or only the stick's turn.
--
-- camera/vr = {
--     height = <metres the tracking space sits above the player's origin>,
--     turn_speed = <radians per second at full stick>,
--     movement_direction = "head" or "body",
-- }
--
-- camera/vr/mirror = {}

local Quat = require("bevy::math::Quat")
local Time = require("bevy::time::Time")
local Vec3 = require("bevy::math::Vec3")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/vr", "core/net/local", "input" },
        },
        with = { "camera/vr", "core/net/local", "input" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        commands:entity(e:id()):patch({
            ["input/game"] = {
                camera_vr = {
                    turn_left = { key = "ArrowLeft" },
                    turn_right = { key = "ArrowRight" },
                },
            },
        })
    end
end):in_set("camera/vr/bind")

-- One mirror for each player, on again when the player is this client's again.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/vr", "core/net/local" },
        },
        with = { "camera/vr", "core/net/local" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/vr/mirror", Mut["Camera"] },
    }],
    Commands,
}, function(carriers, all_mirrors, commands)
    for _, e in ipairs(carriers:iter()) do
        local mirrors = all_mirrors:iter_many_mut(e:get("Children") or {})
        for _, mirror in ipairs(mirrors) do
            mirror:patch({ Camera = { is_active = true } })
        end
        if #mirrors == 0 then
            local mirror = commands:spawn({
                Camera3d = {},
                Camera = { order = 0, is_active = true },
                Transform = {},
                IsDefaultUiCamera = true,
                ["transform/follow"] = {},
                ["camera/vr/mirror"] = {},
            }):id()
            commands:entity(e:id()):add_child(mirror)
        end
    end
end):in_set("camera/vr/spawn")

-- The player left for another world: its window camera stops, and the eyes have no rig to draw from.
app:add_systems(First, {
    Query[{
        removed = { "core/net/local" },
        with = { "camera/vr" },
        optional = { "Children", "VmXrRig" },
    }],
    Query[{
        with = { "camera/vr/mirror", Mut["Camera"] },
    }],
    Commands,
}, function(carriers, all_mirrors, commands)
    for _, e in ipairs(carriers:iter()) do
        for _, mirror in ipairs(all_mirrors:iter_many_mut(e:get("Children") or {})) do
            mirror:patch({ Camera = { is_active = false } })
        end
        if e:has("VmXrRig") then
            commands:entity(e:id()):remove("VmXrRig")
        end
    end
end):in_set("camera/vr/teardown")

-- Follows, so it polls. It runs before walking, which reads `camera.yaw` in this frame. The rig's
-- own yaw holds the stick's turn so far.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "camera/vr", "core/net/local", "Transform", Mut["camera"] },
        optional = {
            "VmXrRig",
            "vr/input/pose",
            "input/game/camera_vr/turn_left",
            "input/game/camera_vr/turn_right",
        },
    }],
    Commands,
}, function(time, carriers, commands)
    local dt = time:delta_secs()
    for _, e in ipairs(carriers:iter_mut()) do
        local vr = e:get("camera/vr")
        local rig = e:get("VmXrRig")
        local left = e:get("input/game/camera_vr/turn_left")
        local right = e:get("input/game/camera_vr/turn_right")
        local stick = (right and right.value or 0) - (left and left.value or 0)
        local yaw = (rig and rig.yaw or 0) - stick * vr.turn_speed * dt
        local at = Vec3.add(e:get("Transform").translation, { x = 0, y = vr.height, z = 0 })
        if rig == nil or rig.yaw ~= yaw or rig.translation.x ~= at.x or rig.translation.y ~= at.y or rig.translation.z ~= at.z then
            commands:entity(e:id()):patch({ VmXrRig = { translation = at, yaw = yaw } })
        end

        local look = yaw
        local pose = e:get("vr/input/pose")
        if vr.movement_direction == "head" and pose ~= nil then
            look = Quat.to_euler(pose.hmd_rotation, "YXZ")[1]
        end
        if e:get("camera").yaw ~= look then
            e:patch({ camera = { yaw = look } })
        end
    end
end):in_set("camera/vr/rig"):before("movement/walk")

-- The window sees what the headset sees, from where the pose says it is.
app:add_systems(Update, {
    Query[{
        changed = { "vr/input/pose" },
        with = { "camera/vr", "core/net/local", "Transform" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/vr/mirror", Mut["transform/follow"] },
    }],
}, function(carriers, all_mirrors)
    for _, e in ipairs(carriers:iter()) do
        local pose = e:get("vr/input/pose")
        local at = e:get("Transform").translation
        for _, mirror in ipairs(all_mirrors:iter_many_mut(e:get("Children") or {})) do
            mirror:patch({
                ["transform/follow"] = {
                    rotation = pose.hmd_rotation,
                    offset = Vec3.sub(pose.hmd_position, at),
                },
            })
        end
    end
end):in_set("camera/vr/mirror")

-- `camera/vr` was taken off an entity that stays: unbind unless `input` went too, as its bindings
-- go with it and a patch landing after that would bring them back. `removed` also fires on despawn.
-- The mirror goes by `mod_registry`.
app:add_systems(First, {
    Query[{
        removed = { "camera/vr" },
        optional = { "input", "input/game", "VmXrRig" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        local carrier = commands:get_entity(e:id())
        if carrier ~= nil then
            if e:has("VmXrRig") then
                carrier:remove("VmXrRig")
            end
            if e:has("input") and e:has("input/game") then
                carrier:patch({ ["input/game"] = { camera_vr = null } })
            end
        end
    end
end):in_set("camera/vr/removed")

return {
    base = "camera",
}
