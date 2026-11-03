-- A slow wanderer that goes to look at noises and chases what it can see. Put on a body, it makes an
-- agent of it: its base is `ai/agent`, and it declares navigation, steering, perception and its
-- behaviours with how this creature wants each. It is entirely configuration, and it takes off what it
-- added when it goes.
--
-- ai/archetype/backrooms_wanderer = {}: its whole definition is here, on the mods it declares

app:add_systems(First, {
    Query[{ added = { "ai/archetype/backrooms_wanderer" } }],
    Commands,
}, function(wanderers, commands)
    for _, e in ipairs(wanderers:iter()) do
        commands:entity(e:id()):patch({
            ["ai/agent"] = { think_hz = 6 },
            ["ai/nav"] = { capabilities = { walk = true } },
            ["ai/steering"] = {
                speed = 1.8,
                arrive_radius = 0.9,
                separation_radius = 1.6,
                turn_speed = 6,
            },
            ["ai/perception"] = {
                vision_range = 20,
                vision_fov_deg = 110,
                awareness_range = 3,
                eye_height = 1.1,
                hearing_range = 26,
            },
            -- A player runs at 6 m/s, so this is outrun in a straight line, but never stops coming.
            ["ai/behavior/chase"] = { speed = 5.2, repath_distance = 2 },
            ["ai/behavior/investigate"] = { speed = 3.4, look_time = 2.5 },
            ["ai/behavior/patrol"] = { speed = 1.8, radius = 14, pause_min = 1.5, pause_max = 4 },
        })
    end
end):in_set("ai/archetype/backrooms_wanderer/init")

-- It was taken off a body that stays: what it declared goes. `ai/agent` goes with it, as its base.
app:add_systems(First, {
    Query[{ removed = { "ai/archetype/backrooms_wanderer" } }],
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
end):in_set("ai/archetype/backrooms_wanderer/removed")

return { base = "ai/agent" }
