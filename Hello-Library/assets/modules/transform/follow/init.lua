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

local Quat = require("bevy::math::Quat")

register_system("PostUpdate", function(world)
    for _, e in ipairs(world:query({
        with = { "transform/follow", "ChildOf", "Transform" },
    })) do
        local follow = e:get("transform/follow")
        local parent_id = e:get("ChildOf")
        local rotation = follow.rotation or { x = 0, y = 0, z = 0, w = 1 }
        local offset = follow.offset or { x = 0, y = 0, z = 0 }
        -- `entities` also matches descendants, so keep only the parent itself.
        for _, parent in ipairs(world:query({
            entities = { parent_id },
            with = { "Transform" },
        })) do
            if parent:id() ~= parent_id then goto next_row end
            local parent_transform = parent:get("Transform")
            local undo = Quat.inverse(parent_transform.rotation)
            e:patch({
                Transform = {
                    rotation = Quat.mul_quat(undo, rotation),
                    translation = Quat.mul_vec3(undo, offset),
                },
            })
            ::next_row::
        end
    end
end, { label = "TransformFollow", before = { "TransformSystems::Propagate" } })
