-- A spawner of wanderers: `ai/spawner`, as its base, makes the plain bodies, and each that a spawner
-- carrying this links to becomes an `ai/archetype/wanderer`.
--
-- ai/archetype/wanderer/spawner = {}: configure the bodies on `ai/spawner`

app:add_systems(First, {
    Query[{ added = { "ai/spawner/agent" } }],
    Query[{ with = { "ai/archetype/wanderer/spawner" } }],
    Commands,
}, function(bodies, spawners, commands)
    for _, body in ipairs(bodies:iter()) do
        if spawners:contains(body:get("ai/spawner/agent").entity) then
            commands:entity(body:id()):insert_if_new({ ["ai/archetype/wanderer"] = {} })
        end
    end
end):in_set("ai/archetype/wanderer/spawner/become")

return { base = "ai/spawner" }
