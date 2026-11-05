-- A wanderer that goes to look at noises and chases what it can see. Put on a body, it makes an
-- agent of it: its base is `ai/agent`, and it declares navigation, steering, perception and its
-- behaviours, each with its own mod's defaults. A creature built on it sets its own numbers with
-- carrier defaults (`base = "ai/archetype/wanderer"`, `defaults = { ["ai/steering"] = { ... } }`).
--
-- ai/archetype/wanderer = {}

-- What a body was given at its spawn stays.
app:add_systems(First, {
    Query[{ added = { "ai/archetype/wanderer" } }],
    Commands,
}, function(wanderers, commands)
    for _, e in ipairs(wanderers:iter()) do
        commands:entity(e:id()):insert_if_new({
            ["ai/nav"] = { capabilities = { walk = true } },
            ["ai/steering"] = {},
            ["ai/perception"] = {},
            ["ai/behavior/chase"] = {},
            ["ai/behavior/investigate"] = {},
            ["ai/behavior/patrol"] = {},
        })
    end
end):in_set("ai/archetype/wanderer/init")

app:add_systems(First, {
    Query[{ removed = { "ai/archetype/wanderer" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove(
            "ai/nav",
            "ai/steering",
            "ai/perception",
            "ai/behavior/chase",
            "ai/behavior/investigate",
            "ai/behavior/patrol")
    end
end):in_set("ai/archetype/wanderer/removed")

return { base = "ai/agent" }
