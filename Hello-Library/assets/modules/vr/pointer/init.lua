-- The right hand as a pointer on this client's own player in VR. When the first thing a ray from
-- the controller meets is a pointer target, Bevy's picking hears it as the mouse pointer on that
-- target's image: moves, scrolls, presses, and a long press as a right click. A laser shows the ray while
-- it is on a target.
--
-- vr/pointer = {
--     pitch = <degrees the ray tilts down from the controller's forward>,
--     yaw = <degrees it turns left>,
--     long_press = <seconds held still for a right click>,
--     long_press_tolerance = <pixels the press may move and still count as still>,
--     length = <metres of laser>,
--     radius = <metres>,
-- }
--
-- vr/pointer/ray = { origin = { x, y, z }, direction = { x, y, z } }: in world space
--
-- vr/pointer/press = {
--     at = <elapsed seconds when pressed; absent once it moved too far for a long press>,
--     x, y = <pixels on the target where it was pressed>,
--     long = <true once the long press was sent>,
-- }
--
-- vr/pointer/target = { image = <render target handle>, width, height }: on a mesh, by its maker
--
-- vr/pointer/hovered = { x, y }: on the target the ray is on, in its image's pixels
--
-- vr/pointer/laser = {}: the laser, a child of the player

local bevy = require("bevy::prelude")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Cylinder = require("bevy::math::primitives::Cylinder")
local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local PointerInput = require("bevy::picking::pointer::PointerInput")
local Quat = require("bevy::math::Quat")
local Time = require("bevy::time::Time")
local Vec3 = require("bevy::math::Vec3")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "vr/pointer", "input" },
        },
        with = { "vr/pointer", "input" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        commands:entity(e:id()):entry("input/ui"):or_default():and_modify(function(ui)
            ui.vr_pointer = {
                press = { button = "Left" },
                scroll = { scroll = true },
            }
        end)
    end
end):in_set("vr/pointer/bind")

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

-- The edge also comes for a player that despawned. `and_modify` does nothing to an `input/ui` that
-- went with `input`, so it cannot bring the bindings back.
app:add_systems(First, {
    Query[{ removed = { "vr/pointer" } }],
    Query[{ with = { "vr/pointer/hovered" } }],
    Commands,
}, function(removed, hovered, commands)
    for _, e in ipairs(removed:iter()) do
        local player = commands:get_entity(e:id())
        if player ~= nil then
            player:entry("input/ui"):and_modify(function(ui)
                ui.vr_pointer = nil
            end)
        end
        for _, h in ipairs(hovered:iter()) do
            commands:entity(h:id()):try_remove("vr/pointer/hovered")
        end
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
            ["vr/pointer/ray"] = {
                origin = pose.right_position,
                direction = Quat.mul_vec3(Quat.mul_quat(pose.right_rotation, tilt), { x = 0, y = 0, z = -1 }),
            },
        })
    end
end):in_set("vr/pointer/ray")

-- The player and what hangs under it (the laser, its body) never stand in the way; anything else
-- does, and only a target answers. A player is a root, so its descendants share its root. Bevy's
-- picking skips a move with no delta, so a ray held still sends none. The mouse pointer is reused:
-- a pointer of its own would be `PointerId::Custom`, which Lua cannot build.
app:add_systems(Update, {
    MeshRayCast,
    Query[{
        changed = { "vr/pointer/ray" },
        with = { "vr/pointer" },
        optional = { "input/ui/vr_pointer/scroll" },
    }],
    Query[{ with = { "vr/pointer/target" } }],
    Query[{ with = { "vr/pointer/hovered", "vr/pointer/target" } }],
    bevy.MessageWriter[PointerInput],
    Commands,
}, function(ray_cast, players, targets, hovered, pointer, commands)
    for _, e in ipairs(players:iter()) do
        local me = e:id()
        local hit = ray_cast:cast_ray(e:get("vr/pointer/ray"), {
            filter = function(entity)
                return players:root_ancestor(entity) ~= me
            end,
        })[1]
        if hit ~= nil and not targets:contains(hit.entity) then
            hit = nil
        end
        local was = hovered:iter()[1]
        if was ~= nil and (hit == nil or was:id() ~= hit.entity) then
            commands:entity(was:id()):try_remove("vr/pointer/hovered")
        end
        local uv = hit and hit.ray_mesh_hit.uv
        if uv ~= nil then
            local target = targets:get(hit.entity):get("vr/pointer/target")
            local x, y = uv.x * target.width, uv.y * target.height
            local before = was ~= nil and was:id() == hit.entity and was:get("vr/pointer/hovered") or nil
            local location = { target = { Image = target.image }, position = { x = x, y = y } }
            if before == nil or before.x ~= x or before.y ~= y then
                pointer:write({
                    pointer_id = "Mouse",
                    location = location,
                    action = { Move = { delta = before and { x = x - before.x, y = y - before.y } or { x = 0.001, y = 0.001 } } },
                })
                commands:entity(hit.entity):insert({ ["vr/pointer/hovered"] = { x = x, y = y } })
            end
            local scroll = e:get("input/ui/vr_pointer/scroll")
            if scroll ~= nil then
                pointer:write({
                    pointer_id = "Mouse",
                    location = location,
                    action = { Scroll = { unit = "Line", x = scroll.dx, y = scroll.dy } },
                })
            end
        end
    end
end):in_set("vr/pointer/cast")

-- A release after a long press sends no primary release, so the press does not also click.
app:add_systems(Update, {
    Res[Time],
    Query[{
        added = { "input/ui/vr_pointer/press" },
        with = { "vr/pointer" },
    }],
    Query[{
        removed = { "input/ui/vr_pointer/press" },
        with = { "vr/pointer/press" },
    }],
    Query[{ with = { "vr/pointer/hovered", "vr/pointer/target" } }],
    bevy.MessageWriter[PointerInput],
    Commands,
}, function(time, pressed, released, hovered, pointer, commands)
    local on = hovered:iter()[1]
    local location = nil
    if on ~= nil then
        local at = on:get("vr/pointer/hovered")
        location = { target = { Image = on:get("vr/pointer/target").image }, position = { x = at.x, y = at.y } }
    end
    for _, e in ipairs(pressed:iter()) do
        if location ~= nil then
            pointer:write({ pointer_id = "Mouse", location = location, action = { Press = "Primary" } })
            commands:entity(e:id()):insert({
                ["vr/pointer/press"] = {
                    at = time:elapsed_secs(),
                    x = location.position.x,
                    y = location.position.y,
                    long = false,
                },
            })
        end
    end
    for _, e in ipairs(released:iter()) do
        if location ~= nil and not e:get("vr/pointer/press").long then
            pointer:write({ pointer_id = "Mouse", location = location, action = { Release = "Primary" } })
        end
        commands:entity(e:id()):try_remove("vr/pointer/press")
    end
end):in_set("vr/pointer/press"):after("vr/pointer/cast")

-- Timed, so it polls while a press is held.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "vr/pointer", Mut["vr/pointer/press"] } }],
    Query[{ with = { "vr/pointer/hovered", "vr/pointer/target" } }],
    bevy.MessageWriter[PointerInput],
}, function(time, holding, hovered, pointer)
    local on = hovered:iter()[1]
    for _, e in ipairs(holding:iter_mut()) do
        local p = e:get("vr/pointer")
        local press = e:get_mut("vr/pointer/press")
        if on ~= nil and press.at ~= nil and not press.long then
            local at = on:get("vr/pointer/hovered")
            if math.sqrt((at.x - press.x) ^ 2 + (at.y - press.y) ^ 2) > p.long_press_tolerance then
                press.at = nil
            elseif time:elapsed_secs() - press.at >= p.long_press then
                local location = { target = { Image = on:get("vr/pointer/target").image }, position = { x = at.x, y = at.y } }
                pointer:write({ pointer_id = "Mouse", location = location, action = { Press = "Secondary" } })
                pointer:write({ pointer_id = "Mouse", location = location, action = { Release = "Secondary" } })
                press.long = true
            end
        end
    end
end):in_set("vr/pointer/long_press"):after("vr/pointer/press")

-- The ray is in world space and the laser is the player's child, so it is brought into the
-- player's frame. `GlobalTransform` is last frame's, as the ray's pose is.
app:add_systems(Update, {
    Query[{
        changed = { "vr/pointer/ray" },
        with = { "vr/pointer", "GlobalTransform" },
        optional = { "Children" },
    }],
    Query[{ with = { "vr/pointer/laser", Mut["Transform"], Mut["Visibility"] } }],
    Query[{ with = { "vr/pointer/hovered" } }],
}, function(players, lasers, hovered)
    for _, e in ipairs(players:iter()) do
        for _, laser in ipairs(lasers:iter_many_mut(e:get("Children") or {})) do
            if hovered:is_empty() then
                laser:get_mut("Visibility"):set_if_neq("Hidden")
            else
                local p = e:get("vr/pointer")
                local ray = e:get("vr/pointer/ray")
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
end):in_set("vr/pointer/laser"):after("vr/pointer/cast")

return {
    defaults = {
        ["vr/pointer"] = {
            pitch = -60,
            yaw = -10,
            long_press = 0.5,
            long_press_tolerance = 15,
            length = 2,
            radius = 0.002,
        },
    },
}
