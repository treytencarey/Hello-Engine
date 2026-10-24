-- Named timers on an entity. While a timer runs, the entity carries the component the timer
-- is named after; when it ends or is cancelled, both are removed.
--
-- cooldown = {
--     <component> = {
--         remaining = <seconds>,
--     },
-- }
--
-- cooldown/left = {
--     <component> = <seconds still to run>,
-- }

local Time = require("bevy::time::Time")

app:add_systems(First, {
    Query[{
        changed = { "cooldown" },
        optional = { "cooldown/left" },
    }],
    Commands,
}, function(timed, commands)
    for _, e in ipairs(timed:iter()) do
        local timers = e:get("cooldown") or {}
        local left = e:get("cooldown/left") or {}
        for name, timer in pairs(timers) do
            local secs = timer.remaining
            if secs and left[name] == nil then
                commands:entity(e:id()):patch({
                    [name] = {},
                    ["cooldown/left"] = { [name] = secs },
                })
            end
        end
    end
end):in_set("cooldown/start")

-- Timed work polls, but only entities with a timer running.
app:add_systems(First, {
    Res[Time],
    Query[{
        with = { "cooldown/left" },
        optional = { "cooldown" },
    }],
    Commands,
}, function(time, running_timers, commands)
    local dt = time:delta_secs()
    for _, e in ipairs(running_timers:iter()) do
        local running = e:get("cooldown") or {}
        local before = e:get("cooldown/left")
        local entity = commands:entity(e:id())
        -- Key by key: `cooldown/start` may add an entry this frame, which this run cannot see yet.
        local still = false
        for name, secs in pairs(before) do
            if running[name] == nil then
                entity:remove(name)
                entity:patch({ ["cooldown/left"] = { [name] = null } })
            elseif secs - dt > 0 then
                still = true
                entity:patch({ ["cooldown/left"] = { [name] = secs - dt } })
            else
                entity:remove(name)
                entity:patch({
                    cooldown = { [name] = null },
                    ["cooldown/left"] = { [name] = null },
                })
            end
        end
        for name in pairs(running) do
            if before[name] == nil then still = true end
        end
        if not still then
            entity:remove("cooldown/left")
        end
    end
end):in_set("cooldown/tick")
