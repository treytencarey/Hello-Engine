-- Makes an entity a trigger. When what overlaps it changes, collision_trigger says
-- who came and who went.
--
-- collision_trigger = {
--     entered = { <id>, ... },
--     exited = { <id>, ... },
--     inside = { <id>, ... },
-- }

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "collision_trigger" } })) do
        e:patch({
            collision_trigger = {
                entered = {},
                exited = {},
                inside = {},
            },
            Sensor3d = {},
            CollidingEntities3d = {},
            ActiveEvents3d = "COLLISION_EVENTS",
        })
    end
end, { label = "CollisionTriggerSetup" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "collision_trigger" },
        with = { "Sensor3d" },
    })) do
        e:patch({
            Sensor3d = null,
            CollidingEntities3d = null,
            ActiveEvents3d = null,
        })
    end
end, { label = "CollisionTriggerRemoved" })

register_system("First", function(world)
    for _, e in ipairs(world:query({
        changed = { "CollidingEntities3d" },
        with = { "collision_trigger" },
    })) do
        local before = e:get("collision_trigger").inside or {}
        local inside = e:get("CollidingEntities3d")
        local was, now = {}, {}
        local entered, exited = {}, {}
        for _, id in ipairs(before) do
            was[id] = true
        end
        for _, id in ipairs(inside) do
            now[id] = true
            if not was[id] then
                entered[#entered + 1] = id
            end
        end
        for id in pairs(was) do
            if not now[id] then
                exited[#exited + 1] = id
            end
        end
        if #entered > 0 or #exited > 0 then
            e:set({ collision_trigger = { entered = entered, exited = exited, inside = inside } })
        end
    end
end, { label = "CollisionTrigger" })
