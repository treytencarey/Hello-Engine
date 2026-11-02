-- Makes noise when its entity moves: a sound event each time it may, for whatever listens
-- (AI hearing). Moving slower than `quiet_speed` is silent. Missing fields get defaults when
-- it is added.
--
-- ai/noisemaker = {
--     interval = <seconds between sounds>,
--     loudness = <how loud at `run_speed` or faster>,
--     kind = <what the sound is, for whoever hears it>,
--     quiet_speed = <metres per second below which it is silent>,
--     run_speed = <metres per second at which it is loudest and repeats faster>,
--     min_loudness = <the share of `loudness` it never drops below>,
--     run_interval = <the share of `interval` it waits at `run_speed` or faster>,
-- }
--
-- ai/noisemaker/state = {
--     next_at = <Time's elapsed seconds at which it may sound again>,
-- }
--
-- The event ai/noisemaker/sound = { entity, x, y, z, loudness, kind }.

local Time = require("bevy::time::Time")
local Vec3 = require("bevy::math::Vec3")

-- Only when it has none: a reload runs this again, and the timer carries on.
app:add_systems(First, {
    Query[{
        added = { "ai/noisemaker" },
        without = { "ai/noisemaker/state" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        commands:entity(e:id()):insert({ ["ai/noisemaker/state"] = { next_at = 0 } })
    end
end):in_set("ai/noisemaker/init")

-- Walkers write `Velocity3d` in Update and physics after it, so this reads it in PostUpdate.
-- Only a change runs it: something standing still costs nothing.
app:add_systems(PostUpdate, {
    Res[Time],
    Query[{
        changed = { "Velocity3d" },
        with = { "ai/noisemaker", "ai/noisemaker/state", "Transform" },
    }],
    Commands,
}, function(time, moved, commands)
    local now = time:elapsed_secs()
    for _, e in ipairs(moved:iter()) do
        local n = e:get("ai/noisemaker")
        local linvel = e:get("Velocity3d").linvel
        local next_at = e:get("ai/noisemaker/state").next_at
        local speed = Vec3.length({ x = linvel.x, y = 0, z = linvel.z })
        if speed >= n.quiet_speed and now >= next_at then
            local at = e:get("Transform").translation
            commands:trigger("ai/noisemaker/sound", {
                entity = e:id(),
                x = at.x,
                y = at.y,
                z = at.z,
                loudness = n.loudness * math.max(n.min_loudness, math.min(1, speed / n.run_speed)),
                kind = n.kind,
            })
            commands:entity(e:id()):patch({
                ["ai/noisemaker/state"] = {
                    next_at = now + n.interval * (speed >= n.run_speed and n.run_interval or 1),
                },
            })
        end
    end
end):in_set("ai/noisemaker/sound")

return {
    defaults = {
        ["ai/noisemaker"] = {
            interval = 0.5,
            loudness = 1,
            kind = "footstep",
            quiet_speed = 2.5,
            run_speed = 5,
            min_loudness = 0.3,
            run_interval = 0.7,
        },
    },
}
