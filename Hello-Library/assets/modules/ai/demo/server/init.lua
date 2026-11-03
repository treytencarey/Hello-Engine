-- A scene that proves the agents work, on `map/default`: a spawner of wanderers, and if asked, a ring
-- of regions around an unwalkable centre, so a working path has to go around, and a decoy circling
-- for them to chase. The ring describes `map/default`'s ground and nothing else, so it is for that
-- map alone.
--
-- ai/demo = {
--     count = <wanderers>,
--     radius = <metres from the centre they start>,
--     regions = <true for the ring>,
--     decoy = <true for the decoy>,
--     decoy_radius = <metres from the centre it circles>,
--     decoy_speed = <metres per second>,
--     debug = <true to draw what the wanderers think, and the ring>,
-- }
--
-- ai/demo/region: marks a region of the ring, a child
-- ai/demo/spawner = { debug = <ai/demo's> }: on the spawner, a child
-- ai/demo/decoy = { entity = <its demo>, angle, radius, speed }: on the decoy
-- ai/demo/decoys: a demo's decoys, kept by the engine

local Time = require("bevy::time::Time")

-- A reload re-fires `added` and what this built is still there.
app:add_systems(First, {
    Query[{
        added = { "ai/demo" },
        optional = { "Children" },
    }],
    Query[{ with = { "ai/demo/spawner" } }],
    Commands,
}, function(added, spawners, commands)
    for _, e in ipairs(added:iter()) do
        if spawners:iter_many(e:get("Children") or {})[1] == nil then
            local d = e:get("ai/demo")
            commands:spawn({
                ["ai/spawner"] = { count = d.count, radius = d.radius },
                ["ai/archetype/backrooms_wanderer/spawner"] = {},
                ["ai/demo/spawner"] = { debug = d.debug },
                ChildOf = e:id(),
                ["core/net/sync"] = false,
                ["core/script/owner"] = false,
            })
            if d.regions then
                for _, box in ipairs({
                    { min_x = -24, max_x = -8, min_z = -24, max_z = 24 },
                    { min_x = -8, max_x = 8, min_z = 8, max_z = 24 },
                    { min_x = 8, max_x = 24, min_z = -24, max_z = 24 },
                    { min_x = -8, max_x = 8, min_z = -24, max_z = -8 },
                }) do
                    commands:spawn({
                        ["ai/demo/region"] = {},
                        ["ai/nav/region"] = { min_x = box.min_x, max_x = box.max_x, min_z = box.min_z, max_z = box.max_z, y = 0.1, cost = 1 },
                        ChildOf = e:id(),
                        ["core/net/sync"] = false,
                        ["core/script/owner"] = false,
                    })
                end
            end
            -- A body would be pushed around: this is only somewhere to look, and something to hear.
            if d.decoy then
                commands:spawn({
                    ["ai/demo/decoy"] = { entity = e:id(), angle = 0, radius = d.decoy_radius, speed = d.decoy_speed },
                    ["ai/perception/target"] = {},
                    ["ai/noisemaker"] = { interval = 0.5, loudness = 1, kind = "footstep" },
                    Transform = { translation = { x = d.decoy_radius, y = 1, z = 0 } },
                    Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
                    ["core/net/sync"] = false,
                    ["core/script/owner"] = false,
                })
            end
            if d.debug then
                commands:entity(e:id()):patch({ ["ai/debug/world"] = {} })
            end
        end
    end
end):in_set("ai/demo/build")

-- The decoy's speed is what `ai/noisemaker` hears, so it writes a velocity it does not otherwise need.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { Mut["ai/demo/decoy"], Mut["Transform"], Mut["Velocity3d"] } }],
}, function(time, decoys)
    local dt = time:delta_secs()
    for _, e in ipairs(decoys:iter_mut()) do
        local d = e:get("ai/demo/decoy")
        local at = e:get("Transform").translation
        local angle = d.angle + d.speed / d.radius * dt
        local x, z = math.cos(angle) * d.radius, math.sin(angle) * d.radius
        e:patch({
            ["ai/demo/decoy"] = { angle = angle },
            Transform = { translation = { x = x, z = z } },
            Velocity3d = { linvel = { x = (x - at.x) / math.max(dt, 1e-4), y = 0, z = (z - at.z) / math.max(dt, 1e-4) } },
        })
    end
end):in_set("ai/demo/decoy")

-- A wanderer of its spawner is drawn, if the demo said so.
app:add_systems(First, {
    Query[{ added = { "ai/spawner/agent" } }],
    Query[{ with = { "ai/demo/spawner" } }],
    Commands,
}, function(bodies, spawners, commands)
    for _, body in ipairs(bodies:iter()) do
        local spawner = spawners:get(body:get("ai/spawner/agent").entity)
        if spawner ~= nil and spawner:get("ai/demo/spawner").debug then
            commands:entity(body:id()):patch({ ["ai/debug"] = {} })
        end
    end
end):in_set("ai/demo/debug")

-- `ai/demo` was taken off an entity that stays: its decoys and its drawing go. Its marked children go
-- by `mod_registry`, and the spawner takes its wanderers.
app:add_systems(First, {
    Query[{
        removed = { "ai/demo" },
        optional = { "ai/demo/decoys" },
    }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        for _, decoy in ipairs(e:get("ai/demo/decoys") or {}) do
            commands:entity(decoy):try_despawn()
        end
        commands:entity(e:id()):try_remove("ai/debug/world")
    end
end):in_set("ai/demo/removed")

return {
    defaults = {
        ["ai/demo"] = {
            count = 2,
            radius = 16,
            regions = false,
            decoy = false,
            decoy_radius = 12,
            decoy_speed = 3.5,
            debug = false,
        },
    },
    relationships = {
        ["ai/demo/decoy"] = { target = "ai/demo/decoys", linked_spawn = true },
    },
}
