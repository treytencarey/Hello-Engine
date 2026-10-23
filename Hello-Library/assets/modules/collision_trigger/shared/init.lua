-- Makes an entity a trigger. When what overlaps it changes, collision_trigger says
-- who came and who went.
--
-- collision_trigger = {
--     entered = { <id>, ... },
--     exited = { <id>, ... },
--     inside = { <id>, ... },
-- }
--
-- Writes are `try_` commands: they land after the system, and a synced copy may be despawned
-- by then (the server ended it).

local app = ...

app:add_systems(First, {
    Query[{ added = { "collision_trigger" } }],
    Commands,
}, function(triggers, commands)
    for _, e in ipairs(triggers:iter()) do
        commands:entity(e:id()):try_insert({
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
end):in_set("collision_trigger/setup")

app:add_systems(First, {
    Query[{
        removed = { "collision_trigger" },
        with = { "Sensor3d" },
    }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("Sensor3d", "CollidingEntities3d", "ActiveEvents3d")
    end
end):in_set("collision_trigger/removed")

-- The lists are replaced whole: a patch would merge the new lists into the old ones.
app:add_systems(First, {
    Query[{
        changed = { "CollidingEntities3d" },
        with = { "collision_trigger" },
    }],
    Commands,
}, function(triggers, commands)
    for _, e in ipairs(triggers:iter()) do
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
            commands:entity(e:id()):try_insert({
                collision_trigger = { entered = entered, exited = exited, inside = inside },
            })
        end
    end
end):in_set("collision_trigger")
