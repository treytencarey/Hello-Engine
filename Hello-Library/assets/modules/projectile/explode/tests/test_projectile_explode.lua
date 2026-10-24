-- --host
-- `projectile/explode` on the server, headless, with physics.
--
--   E1 it makes the projectile a sensor (no bounce)
--   E2 it flies on while it touches nothing
--   E3 the first other thing it enters ends it, with an explosion of its fields where it was
--   E4 taken off an entity that stays: it is no longer a sensor
--   E7 its explosion is local: it carries no sync
--   E5 it flies through its caster (`projectile/caster`) and ends on the next thing
--   E6 the caster lists it in `projectile/casts` while it flies, and not once it is gone
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ProjectileExplodeSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/ball" },
        optional = { "projectile", "collision_trigger", "Sensor3d" },
    })) do
        if e:get("zz/ball").name == name then return e end
    end
end

local phase, clock = "spawn", 0
local ts_flying = nil


app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        -- A wall 6 m along +X.
        commands:spawn({
            Transform = { translation = { x = 6, y = 50, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 0.5, hy = 5, hz = 5 } },
            ["core/net/sync"] = false,
        })
        commands:spawn({
            ["zz/ball"] = { name = "fired" },
            projectile = { from = { x = 0, y = 50, z = 0 }, velocity = { x = 4, y = 0, z = 0 },
                           gravity = 0, lifetime = 30, radius = 0.2 },
            ["projectile/explode"] = { radius = 2.5, duration = 3, color = { r = 0, g = 0, b = 1 } },
        })
        commands:spawn({
            ["zz/ball"] = { name = "kept" },
            Transform = { translation = { x = -50, y = 50, z = 0 } },
            projectile = { from = { x = -50, y = 50, z = 0 }, gravity = 0, lifetime = 30 },
            ["projectile/explode"] = {},
        })
        -- E5's lane, 20 m up: a caster 2 m along +X, in the way, and a wall behind it.
        commands:spawn({
            ["zz/caster"] = {},
            Transform = { translation = { x = 2, y = 70, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 0.5, hy = 1, hz = 1 } },
            ["core/net/sync"] = false,
        })
        commands:spawn({
            Transform = { translation = { x = 6, y = 70, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 0.5, hy = 5, hz = 5 } },
            ["core/net/sync"] = false,
        })
        step("inside")

    elseif phase == "inside" then
        local fired = named(world, "fired")
        -- The sensor lands a frame or two after the spawn, which the first, long frames stretch:
        -- wait for it, while the ball is still in open air (the wall is 1.4 s away).
        if clock < 0.3 or (clock < 1.0 and not (fired and fired:has("Sensor3d"))) then return end
        suite.assert_test("E1_it_makes_the_projectile_a_sensor",
            fired ~= nil and fired:has("collision_trigger") and fired:has("Sensor3d"), "")
        -- About 1.2 m out, in open air.
        suite.assert_test("E2_it_flies_on_while_it_touches_nothing",
            fired ~= nil and #world:query({ with = { "explosion" } }) == 0, "")
        step("hit")

    elseif phase == "hit" then
        local blasts = world:query({ with = { "explosion" } })
        -- The server's despawn of the ball lands a frame or so after its explosion shows.
        if (#blasts == 0 or named(world, "fired") ~= nil) and clock < 3 then return end
        local x = blasts[1] and blasts[1]:get("explosion") or {}
        local at = x.at or {}
        -- The wall's face is at x = 5.5.
        suite.assert_test("E3_the_first_other_thing_ends_it_with_an_explosion",
            #blasts == 1 and x.radius == 2.5 and x.duration == 3 and (x.color or {}).b == 1
                and math.abs((at.x or 0) - 5.5) < 0.6 and named(world, "fired") == nil,
            string.format("blasts=%d at.x=%s", #blasts, tostring(at.x)))
        local kept = named(world, "kept")
        world:get_entity(kept:id()):patch({ ["projectile/explode"] = null })
        step("removed")

    elseif phase == "removed" then
        if clock < 0.3 then return end
        local kept = named(world, "kept")
        local blast = world:query({ with = { "explosion" }, optional = { "core/net/sync" } })[1]
        suite.assert_test("E7_its_explosion_is_local", blast ~= nil and blast:get("core/net/sync") == nil,
            "sync=" .. tostring(blast and blast:get("core/net/sync")))
        suite.assert_test("E4_taken_off_it_is_no_longer_a_sensor",
            kept ~= nil and not kept:has("collision_trigger") and not kept:has("Sensor3d"), "")
        local caster = world:query({ with = { "zz/caster" } })[1]
        commands:spawn({
            ["zz/ball"] = { name = "cast" },
            projectile = { from = { x = 0, y = 70, z = 0 }, velocity = { x = 4, y = 0, z = 0 },
                           gravity = 0, lifetime = 30, radius = 0.2 },
            ["projectile/explode"] = { radius = 1, duration = 3 },
            ["projectile/caster"] = { entity = caster:id() },
        })
        step("cast")

    elseif phase == "cast" then
        if clock < 0.6 then return end
        -- About 2.4 m out: inside the caster (x 1.5 to 2.5) or just past it.
        local caster = world:query({ with = { "zz/caster" }, optional = { "projectile/casts" } })[1]
        local casts = caster:get("projectile/casts") or {}
        local cast = named(world, "cast")
        ts_flying = #casts == 1 and cast ~= nil and casts[1] == cast:id()
        step("cast_hit")

    elseif phase == "cast_hit" then
        local blasts = world:query({ with = { "explosion" } })
        local lane = nil
        for _, b in ipairs(blasts) do
            local at = b:get("explosion").at or {}
            if (at.y or 0) > 60 then lane = at end
        end
        if lane == nil and clock < 3 then return end
        -- The wall's face is at x = 5.5; the caster's is at x = 1.5.
        suite.assert_test("E5_it_flies_through_its_caster",
            lane ~= nil and math.abs((lane.x or 0) - 5.5) < 0.6,
            "blast at x=" .. tostring(lane and lane.x))
        step("cast_gone")

    elseif phase == "cast_gone" then
        if clock < 0.3 then return end
        local caster = world:query({ with = { "zz/caster" }, optional = { "projectile/casts" } })[1]
        suite.assert_test("E6_the_caster_lists_it_while_it_flies",
            ts_flying == true and caster:get("projectile/casts") == nil,
            "while flying=" .. tostring(ts_flying) .. " after=" .. tostring(caster:get("projectile/casts")))
        suite.finish("PROJECTILE_EXPLODE")
        phase = "done"
    end
end):in_set("zz/projectile_explode_suite")
