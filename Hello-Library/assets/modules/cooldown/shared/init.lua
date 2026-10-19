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

register_system("First", function(world)
    for _, e in ipairs(world:query({
        changed = { "cooldown" },
        optional = { "cooldown/left" },
    })) do
        local timers = e:get("cooldown") or {}
        local left = e:get("cooldown/left") or {}
        for name, timer in pairs(timers) do
            local secs = timer.remaining
            if secs and left[name] == nil then
                e:patch({
                    [name] = {},
                    ["cooldown/left"] = { [name] = secs },
                })
            end
        end
    end
end, { label = "CooldownStart" })

-- Timed work polls, but only entities with a timer running.
register_system("First", function(world)
    local dt = world:delta_time() or 0
    for _, e in ipairs(world:query({
        with = { "cooldown/left" },
        optional = { "cooldown" },
    })) do
        local running = e:get("cooldown") or {}
        local before = e:get("cooldown/left")
        local left = {}
        for name, secs in pairs(before) do
            if running[name] == nil then
                e:patch({ [name] = null })
            elseif secs - dt > 0 then
                left[name] = secs - dt
            else
                e:patch({
                    [name] = null,
                    cooldown = { [name] = null },
                })
            end
        end
        if next(left) then
            e:set({ ["cooldown/left"] = left })
        else
            e:patch({ ["cooldown/left"] = null })
        end
    end
end, { label = "CooldownTick" })
