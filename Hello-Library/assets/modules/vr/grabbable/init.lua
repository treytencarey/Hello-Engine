-- The grip grabs what the pointer's ray is on, on this client's own player in VR, and carries it
-- along the ray at the distance it was grabbed, turned to face the head if it asks to.
--
-- vr/grabbable = {}
--
-- vr/grabbable/target = {
--     face = <true to face the head while held>,
-- }: on what can be grabbed, by its maker
--
-- vr/grabbable/held = {
--     distance = <metres along the ray to the grabbed point>,
--     offset = { x, y, z } <from that point to the target's translation>,
-- }: on the target while held

local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "vr/grabbable", "input" },
        },
        with = { "vr/grabbable", "input" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        commands:entity(e:id()):entry("input/ui"):or_default():and_modify(function(ui)
            ui.vr_grabbable = {
                grab = { key = "KeyG" },
            }
        end)
    end
end):in_set("vr/grabbable/bind")

-- The edge also comes for a player that despawned. `and_modify` does nothing to an `input/ui` that
-- went with `input`, so it cannot bring the bindings back.
app:add_systems(First, {
    Query[{ removed = { "vr/grabbable" } }],
    Query[{ with = { "vr/grabbable/held" } }],
    Commands,
}, function(removed, held, commands)
    for _, e in ipairs(removed:iter()) do
        local player = commands:get_entity(e:id())
        if player ~= nil then
            player:entry("input/ui"):and_modify(function(ui)
                ui.vr_grabbable = nil
            end)
        end
        for _, h in ipairs(held:iter()) do
            commands:entity(h:id()):try_remove("vr/grabbable/held")
        end
    end
end):in_set("vr/grabbable/removed")

-- A target's translation is taken as its place in the world, so only a root moves as expected.
app:add_systems(Update, {
    MeshRayCast,
    Query[{
        added = { "input/ui/vr_grabbable/grab" },
        with = { "vr/grabbable", "vr/pointer/ray" },
    }],
    Query[{ with = { "vr/grabbable/target", "Transform" } }],
    Commands,
}, function(ray_cast, grabbing, targets, commands)
    for _, e in ipairs(grabbing:iter()) do
        local hit = ray_cast:cast_ray(e:get("vr/pointer/ray"), {
            filter = function(entity)
                return targets:contains(entity)
            end,
        })[1]
        if hit ~= nil then
            local at = targets:get(hit.entity):get("Transform").translation
            commands:entity(hit.entity):insert({
                ["vr/grabbable/held"] = {
                    distance = hit.ray_mesh_hit.distance,
                    offset = Vec3.sub(at, hit.ray_mesh_hit.point),
                },
            })
        end
    end
end):in_set("vr/grabbable/grab")

app:add_systems(Update, {
    Query[{
        removed = { "input/ui/vr_grabbable/grab" },
        with = { "vr/grabbable" },
    }],
    Query[{ with = { "vr/grabbable/held" } }],
    Commands,
}, function(released, held, commands)
    for _, _ in ipairs(released:iter()) do
        for _, h in ipairs(held:iter()) do
            commands:entity(h:id()):try_remove("vr/grabbable/held")
        end
    end
end):in_set("vr/grabbable/release")

-- Facing keeps the target upright: it turns about Y only, its front (+Z) to the head.
app:add_systems(Update, {
    Query[{
        changed = { "vr/pointer/ray" },
        with = { "vr/grabbable", "vr/input/pose" },
    }],
    Query[{ with = { "vr/grabbable/held", "vr/grabbable/target", Mut["Transform"] } }],
}, function(players, held)
    for _, e in ipairs(players:iter()) do
        local ray = e:get("vr/pointer/ray")
        local head = e:get("vr/input/pose").hmd_position
        for _, h in ipairs(held:iter_mut()) do
            local grab = h:get("vr/grabbable/held")
            local t = h:get_mut("Transform")
            t.translation = Vec3.add(Vec3.add(ray.origin, Vec3.mul(ray.direction, Vec3.splat(grab.distance))), grab.offset)
            local toward = Vec3.normalize_or_zero({ x = head.x - t.translation.x, y = 0, z = head.z - t.translation.z })
            if h:get("vr/grabbable/target").face and Vec3.length(toward) > 0 then
                t.rotation = Quat.from_rotation_arc({ x = 0, y = 0, z = 1 }, toward)
            end
        end
    end
end):in_set("vr/grabbable/move"):after("vr/grabbable/grab")

return {
    defaults = {
        ["vr/grabbable/target"] = { face = false },
    },
}
