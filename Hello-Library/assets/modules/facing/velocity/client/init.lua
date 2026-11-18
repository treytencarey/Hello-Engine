-- Face where the character walks: the direction its own walking drives, `Velocity3d` as
-- `movement/walk` writes it from the held keys and the camera's yaw, read only while one of those
-- keys is held. A push, with no key held, does not turn it; opposite keys, which cancel, hold it.
-- Letting go leaves the last target, so a turn under way finishes.
--
-- facing/velocity = {}

local Quat = require("bevy::math::Quat")

app:add_systems(Update, {
    Query[{
        any_of = {
            "input/game/movement/forward",
            "input/game/movement/backward",
            "input/game/movement/left",
            "input/game/movement/right",
        },
        with = { "facing/velocity", Mut["facing"], "Velocity3d" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
}, function(walkers, own)
    for _, n in ipairs(own:iter()) do
        for _, e in ipairs(walkers:iter_many_mut(n:get("core/net/owns"))) do
            local v = e:get("Velocity3d").linvel
            local f = e:get("facing")
            local target = nil
            if v.x * v.x + v.z * v.z > 1e-4 then target = Quat.from_rotation_y(math.atan2(v.x, v.z)) end
            if target == nil and f.target ~= nil then
                e:get_mut("facing").target = nil
            elseif target ~= nil and (f.target == nil or not Quat.abs_diff_eq(f.target, target, 1e-4)) then
                e:get_mut("facing").target = target
            end
        end
    end
end):in_set("facing/velocity"):after("movement/walk")

return {
    base = "facing",
}
