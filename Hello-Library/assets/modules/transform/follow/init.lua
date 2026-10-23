-- A child that follows its parent's position but keeps its own world rotation. Every
-- frame, just before Bevy computes world transforms, the child's local transform is set
-- so that it sits `offset` (in world space) from its parent with world rotation
-- `rotation`. The parent's rotation is read from its own Transform: exact when the
-- parent is a root entity, a frame late when the parent is itself a child.
--
-- transform/follow = {
--     rotation = { x = <number>, y = <number>, z = <number>, w = <number> },
--     offset = { x = <metres>, y = <metres>, z = <metres> },
-- }

local app = ...
local Quat = require("bevy::math::Quat")
local TransformSystems = require("bevy::transform::TransformSystems")

app:add_systems(PostUpdate, {
    Query[{
        with = { "transform/follow", "ChildOf", Mut["Transform"] },
    }],
    Query[{ with = { "Transform" } }],
}, function(followers, parents)
    for _, e in ipairs(followers:iter_mut()) do
        local follow = e:get("transform/follow")
        local rotation = follow.rotation or { x = 0, y = 0, z = 0, w = 1 }
        local offset = follow.offset or { x = 0, y = 0, z = 0 }
        local parent = parents:get(e:get("ChildOf"))
        if parent ~= nil then
            local undo = Quat.inverse(parent:get("Transform").rotation)
            e:patch({
                Transform = {
                    rotation = Quat.mul_quat(undo, rotation),
                    translation = Quat.mul_vec3(undo, offset),
                },
            })
        end
    end
end):in_set("transform/follow"):before(TransformSystems.Propagate)
