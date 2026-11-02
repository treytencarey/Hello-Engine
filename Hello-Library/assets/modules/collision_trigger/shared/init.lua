-- Makes an entity a trigger. When what overlaps it changes, collision_trigger says
-- who came and who went.
--
-- collision_trigger = {
--     entered = { <entity>, ... },
--     exited = { <entity>, ... },
--     inside = { <entity>, ... },
-- }
--
-- Writes are `try_` commands: they land after the system, and a synced copy may be despawned
-- by then (the server ended it).

-- Adds only what the entity lacks: a reload runs this again, and a fresh `CollidingEntities3d`
-- would read as everything having exited.
app:add_systems(First, {
    Query[{
        added = { "collision_trigger" },
        optional = { "Sensor3d", "CollidingEntities3d", "ActiveEvents3d" },
    }],
    Commands,
}, function(triggers, commands)
    for _, e in ipairs(triggers:iter()) do
        local entity = commands:entity(e:id())
        if not e:has("Sensor3d") then entity:try_insert({ Sensor3d = {} }) end
        if not e:has("CollidingEntities3d") then entity:try_insert({ CollidingEntities3d = {} }) end
        if not e:has("ActiveEvents3d") then entity:try_insert({ ActiveEvents3d = "COLLISION_EVENTS" }) end
    end
end):in_set("collision_trigger/init")

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
        local entered, exited = {}, {}
        for _, id in ipairs(inside) do
            local was = false
            for _, old in ipairs(before) do
                if old == id then
                    was = true
                    break
                end
            end
            if not was then
                entered[#entered + 1] = id
            end
        end
        for _, old in ipairs(before) do
            local stays = false
            for _, id in ipairs(inside) do
                if id == old then
                    stays = true
                    break
                end
            end
            if not stays then
                exited[#exited + 1] = old
            end
        end
        if #entered > 0 or #exited > 0 then
            commands:entity(e:id()):try_insert({
                collision_trigger = { entered = entered, exited = exited, inside = inside },
            })
        end
    end
end):in_set("collision_trigger")

return {
    defaults = {
        collision_trigger = {
            entered = {},
            exited = {},
            inside = {},
        },
    },
}
