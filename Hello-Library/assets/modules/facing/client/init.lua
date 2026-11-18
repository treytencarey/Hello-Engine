-- Which way a character's body points: this mod is the one writer of its rotation. A variant
-- (`facing/velocity`, `facing/camera`) decides where to face and writes `facing.target`; this turns
-- the body toward it. Attach a variant, never this directly: its base brings this one.
--
-- facing = {
--     target = <the rotation to turn toward; absent, the body holds still>,
--     turn_rate = <radians per second>,
-- }
--
-- The owner's client turns its own characters (those in its own nets' `core/net/owns`), as it
-- moves them; their Transform reaches everyone else through its sync.

local Quat = require("bevy::math::Quat")
local Time = require("bevy::time::Time")

-- Turning, so it polls this client's own characters. `rotate_towards` limits the angle a frame, so
-- a turn takes a predictable time and lands on its target.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "facing", Mut["Transform"] } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
}, function(time, bodies, own)
    local dt = time:delta_secs()
    for _, n in ipairs(own:iter()) do
        for _, e in ipairs(bodies:iter_many_mut(n:get("core/net/owns"))) do
            local f = e:get("facing")
            local rotation = e:get("Transform").rotation
            if f.target ~= nil and Quat.angle_between(rotation, f.target) > 1e-4 then
                e:get_mut("Transform").rotation = Quat.rotate_towards(rotation, f.target, f.turn_rate * dt)
            end
        end
    end
end):in_set("facing"):after("facing/velocity"):after("facing/camera")

return {
    defaults = {
        facing = {
            turn_rate = 10,
        },
    },
}
