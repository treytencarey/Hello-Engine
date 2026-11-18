-- The VR controller's ray source for `pointer`, on this client's own player in VR: the right hand's
-- ray, written as `pointer/ray`, and a laser showing it while it is on a target. It has `pointer` as
-- its base, as `pointer/view` does for the desktop; what the ray does on a screen is `pointer`'s.
--
-- vr/pointer = {
--     pitch = <degrees the ray tilts down from the controller's forward>,
--     yaw = <degrees it turns left>,
--     length = <metres of laser>,
--     radius = <metres>,
-- }
--
-- vr/pointer/laser = {}: the laser, a child of the player

local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Cylinder = require("bevy::math::primitives::Cylinder")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

-- A unit cylinder along Y, so `length` and `radius` are its scale and apply as they change.
app:add_systems(First, {
    Query[{
        added = { "vr/pointer" },
        optional = { "Children" },
    }],
    Query[{ with = { "vr/pointer/laser" } }],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(players, lasers, meshes, materials, commands)
    for _, e in ipairs(players:iter()) do
        if #lasers:iter_many(e:get("Children") or {}) == 0 then
            commands:entity(e:id()):add_child(commands:spawn({
                ["vr/pointer/laser"] = {},
                Mesh3d = meshes:add(Cylinder.new(1, 1)),
                ["MeshMaterial3d<StandardMaterial>"] = materials:add({
                    base_color = { Srgba = { red = 1, green = 0.2, blue = 0.2, alpha = 0.8 } },
                    unlit = true,
                    alpha_mode = "Blend",
                }),
                Transform = {},
                Visibility = "Hidden",
                Pickable = { should_block_lower = false, is_hoverable = false },
            }):id())
        end
    end
end):in_set("vr/pointer/init")

-- What it wrote goes with it. The edge also comes for a player that despawned.
app:add_systems(First, {
    Query[{ removed = { "vr/pointer" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        local player = commands:get_entity(e:id())
        if player ~= nil then player:try_remove("pointer/ray") end
    end
end):in_set("vr/pointer/removed")

-- The aim is turned in the controller's own frame, so it stays fixed to the hand.
app:add_systems(PreUpdate, {
    Query[{
        ["or"] = {
            changed = { "vr/input/pose", "vr/pointer" },
        },
        with = { "vr/pointer", "vr/input/pose" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        local p = e:get("vr/pointer")
        local pose = e:get("vr/input/pose")
        local tilt = Quat.mul_quat(Quat.from_rotation_y(math.rad(p.yaw)), Quat.from_rotation_x(math.rad(p.pitch)))
        commands:entity(e:id()):insert({
            ["pointer/ray"] = {
                origin = pose.right_position,
                direction = Quat.mul_vec3(Quat.mul_quat(pose.right_rotation, tilt), { x = 0, y = 0, z = -1 }),
            },
        })
    end
end):in_set("vr/pointer/ray")

-- The ray is in world space and the laser is the player's child, so it is brought into the
-- player's frame. `GlobalTransform` is last frame's, as the ray's pose is.
app:add_systems(Update, {
    Query[{
        changed = { "pointer/ray" },
        with = { "vr/pointer", "GlobalTransform" },
        optional = { "Children" },
    }],
    Query[{ with = { "vr/pointer/laser", Mut["Transform"], Mut["Visibility"] } }],
    Query[{ with = { "pointer/hovered" } }],
}, function(players, lasers, hovered)
    for _, e in ipairs(players:iter()) do
        for _, laser in ipairs(lasers:iter_many_mut(e:get("Children") or {})) do
            if hovered:is_empty() then
                laser:get_mut("Visibility"):set_if_neq("Hidden")
            else
                local p = e:get("vr/pointer")
                local ray = e:get("pointer/ray")
                local player = e.GlobalTransform:compute_transform()
                local back = Quat.inverse(player.rotation)
                local origin = Quat.mul_vec3(back, Vec3.sub(ray.origin, player.translation))
                local direction = Quat.mul_vec3(back, ray.direction)
                local t = laser:get_mut("Transform")
                t.translation = Vec3.add(origin, Vec3.mul(direction, Vec3.splat(p.length / 2)))
                t.rotation = Quat.from_rotation_arc({ x = 0, y = 1, z = 0 }, direction)
                t.scale = { x = p.radius, y = p.length, z = p.radius }
                laser:get_mut("Visibility"):set_if_neq("Visible")
            end
        end
    end
end):in_set("vr/pointer/laser"):after("pointer/cast")

return {
    base = "pointer",
    defaults = {
        ["vr/pointer"] = {
            pitch = -60,
            yaw = -10,
            length = 2,
            radius = 0.002,
        },
    },
}
