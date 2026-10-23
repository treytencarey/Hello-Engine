-- --host
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("MapServerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "map/default", "RigidBody3d", "Collider3d", "Mesh3d" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function y_of(world, name)
    return world:get_entity(named(world, name):id()).GlobalTransform:compute_transform().translation.y
end

local function ball(commands, name, x)
    commands:spawn({
        ["zz/name"] = { name = name },
        Transform = { translation = { x = x, y = 2, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { ball = { radius = 0.5 } },
    })
end

local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-3) end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["zz/name"] = { name = "plain" }, ["map/default"] = {}, ["core/net/sync"] = false })
        step("defaults")

    elseif phase == "defaults" and clock > 0.2 then
        local m = named(world, "plain"):get("map/default")
        suite.assert_test("M1_missing_fields_get_defaults",
            m.size.x == 100 and m.size.y == 0.2 and m.size.z == 100 and m.color.g == 0.5 and m.sun == 10000, "")
        commands:entity(named(world, "plain"):id()):despawn()
        commands:spawn({
            ["zz/name"] = { name = "small" },
            ["map/default"] = { size = { x = 10, y = 1, z = 10 } },
            ["core/net/sync"] = false,
        })
        ball(commands, "on", 3)
        ball(commands, "off", 8)
        step("landed")

    elseif phase == "landed" and clock > 2.5 then
        local map = named(world, "small")
        local body = map:get("RigidBody3d")
        local given = map:get("map/default")
        suite.assert_test("M1b_fields_not_given_get_defaults_beside_those_given",
            given.size.x == 10 and given.sun == 10000 and given.color.g == 0.5, "")
        suite.assert_test("M2_the_ground_is_a_fixed_body", body ~= nil and body.Fixed == true, "")
        suite.assert_test("M3_a_ball_rests_on_its_top_surface", near(y_of(world, "on"), 1.0, 0.05),
            string.format("y=%.3f", y_of(world, "on")))
        suite.assert_test("M4_its_size_sets_its_edge", y_of(world, "off") < -1,
            string.format("y=%.3f", y_of(world, "off")))
        suite.assert_test("M5_the_server_draws_nothing", not map:has("Mesh3d"), "")
        map:patch({ ["map/default"] = { size = { x = 20, y = 1, z = 10 } } })
        ball(commands, "later", 8)
        step("grown")

    elseif phase == "grown" and clock > 2.0 then
        suite.assert_test("M7_a_changed_size_moves_its_edge", near(y_of(world, "later"), 1.0, 0.05),
            string.format("y=%.3f", y_of(world, "later")))
        named(world, "small"):remove("map/default")
        step("removed")

    elseif phase == "removed" and clock > 1.5 then
        local map = named(world, "small")
        suite.assert_test("M6_removing_map_default_takes_off_the_ground",
            map ~= nil and not map:has("RigidBody3d") and not map:has("Collider3d") and y_of(world, "on") < 0,
            string.format("y=%.3f", y_of(world, "on")))
        phase = "done"
        suite.finish("MapServerSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("M0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("MapServerSuite")
    end
end):in_set("zz/map_server_suite")
