-- --host
-- `abilities/projectile` on the server, headless: a launch becomes a `projectile`.
--
--   P1 it launches 1 m along the look from `at`, at its speed
--   P2 its own fields reach the projectile
--   P3 the pitch aims it: a look straight up launches straight up
--   P4 taken off an entity that stays: the `projectile` goes
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("AbilitiesProjectileSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function near(a, b) return math.abs((a or 0/0) - b) < 1e-3 end

local function named(world, name)
    for _, e in ipairs(world:query({ with = { "zz/shot" }, optional = { "projectile" } })) do
        if e:get("zz/shot").name == name then return e end
    end
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            ["zz/shot"] = { name = "level" },
            ["abilities/projectile"] = { at = { x = 0, y = 51, z = 0 }, yaw = math.pi / 2, pitch = 0,
                                         speed = 10, radius = 0.4, gravity = 0, lifetime = 30 },
        })
        commands:spawn({
            ["zz/shot"] = { name = "up" },
            ["abilities/projectile"] = { at = { x = 50, y = 51, z = 0 }, yaw = 0, pitch = math.pi / 2,
                                         speed = 10, gravity = 0, lifetime = 30 },
        })
        step("launched")

    elseif phase == "launched" then
        if clock < 0.3 then return end
        local level = named(world, "level")
        local p = level and level:get("projectile") or {}
        local v, from = p.velocity or {}, p.from or {}
        -- yaw pi/2 turns the look (-Z) to -X.
        suite.assert_test("P1_launched_along_the_look_at_its_speed",
            near(v.x, -10) and near(v.y, 0) and near(v.z, 0)
                and near(from.x, -1) and near(from.y, 51) and near(from.z, 0),
            string.format("v=(%s,%s,%s) from=(%s,%s,%s)", tostring(v.x), tostring(v.y), tostring(v.z),
                tostring(from.x), tostring(from.y), tostring(from.z)))
        suite.assert_test("P2_its_fields_reach_the_projectile", near(p.radius, 0.4), "radius=" .. tostring(p.radius))
        local up = named(world, "up")
        local u = (up and up:get("projectile") or {}).velocity or {}
        suite.assert_test("P3_the_pitch_aims_it", near(u.x, 0) and near(u.y, 10) and near(u.z, 0),
            string.format("v=(%s,%s,%s)", tostring(u.x), tostring(u.y), tostring(u.z)))
        world:get_entity(level:id()):patch({ ["abilities/projectile"] = null })
        step("removed")

    elseif phase == "removed" then
        if clock < 0.3 then return end
        local level = named(world, "level")
        suite.assert_test("P4_taken_off_the_projectile_goes", level ~= nil and level:get("projectile") == nil, "")
        suite.finish("ABILITIES_PROJECTILE")
        phase = "done"
    end
end):in_set("zz/abilities_projectile_suite")
