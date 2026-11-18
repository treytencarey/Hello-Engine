-- Face where the camera looks, while the character moves: strafing. Standing, it holds still, so a
-- swinging camera does not slide its feet. A body's front is +Z and a look's is -Z, hence the half
-- turn.
--
-- facing/camera = {}

local Quat = require("bevy::math::Quat")

app:add_systems(Update, {
    Query[{ with = { "facing/camera", Mut["facing"], "Velocity3d", "camera" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
}, function(bodies, own)
    for _, n in ipairs(own:iter()) do
        for _, e in ipairs(bodies:iter_many_mut(n:get("core/net/owns"))) do
            local v = e:get("Velocity3d").linvel
            local f = e:get("facing")
            local target = nil
            if v.x * v.x + v.z * v.z > 1e-4 then target = Quat.from_rotation_y((e:get("camera").yaw or 0) + math.pi) end
            if target == nil and f.target ~= nil then
                e:get_mut("facing").target = nil
            elseif target ~= nil and (f.target == nil or not Quat.abs_diff_eq(f.target, target, 1e-4)) then
                e:get_mut("facing").target = target
            end
        end
    end
end):in_set("facing/camera"):after("movement/walk")

return {
    base = "facing",
}
