-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("WandererSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 500 } },
    })
    commands:spawn({
        ["zz/name"] = { name = "pack" },
        ["ai/spawner"] = { count = 2, radius = 10, y = 1 },
        ["ai/archetype/wanderer/spawner"] = {},
    })
    commands:spawn({ ["zz/name"] = { name = "alone" }, ["ai/archetype/wanderer/spawner"] = {} })
    commands:spawn({ ["zz/name"] = { name = "plain" }, ["ai/spawner"] = { count = 1, center_x = 200, y = 1 } })
    commands:spawn({
        ["zz/name"] = { name = "slow" },
        ["ai/archetype/wanderer/tests/fixtures/zz_slow"] = {},
        Transform = { translation = { x = 0, y = 1, z = 200 } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/name"] = { name = "given" },
        ["ai/archetype/wanderer"] = {},
        ["ai/perception"] = { vision_range = 30 },
        Transform = { translation = { x = 0, y = 1, z = -200 } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
end)

local function body(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/archetype/wanderer", "ai/steering", "ai/perception" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/spawner/agents" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function bodies(world, name)
    return world:query({
        iter_many = named(world, name):get("ai/spawner/agents") or {},
        with = { "ai/spawner/agent" },
        optional = {
            "ai/archetype/wanderer",
            "ai/agent",
            "ai/agent/memory",
            "ai/agent/options",
            "ai/nav",
            "ai/nav/request",
            "ai/steering",
            "ai/perception",
            "ai/behavior/chase",
            "ai/behavior/investigate",
            "ai/behavior/patrol",
            "movement",
        },
    })
end

local phase, clock = "becoming", 0
local body_id = nil

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local pack = named(world, "pack") and bodies(world, "pack") or {}

    local slow, given = body(world, "slow"), body(world, "given")
    if phase == "becoming" and #pack == 2 and pack[1]:has("ai/agent/options") and #pack[1]:get("ai/agent/options") == 3 and clock > 0.5
        and slow ~= nil and slow:has("ai/steering") and given ~= nil and given:has("ai/steering") then
        local b = pack[1]
        suite.assert_test("AR1_a_body_from_its_spawner_becomes_the_creature", b:has("ai/archetype/wanderer") and b:has("ai/agent"), "")
        suite.assert_test("AR2_its_base_gives_it_memory", b:has("ai/agent/memory"), "")
        suite.assert_test("AR3_it_declares_navigation_steering_and_perception",
            b:has("ai/nav") and b:has("ai/nav/request") and b:has("ai/steering") and b:has("ai/perception"), "")
        suite.assert_test("AR4_and_its_behaviours", b:has("ai/behavior/chase") and b:has("ai/behavior/investigate") and b:has("ai/behavior/patrol"), "")
        suite.assert_test("AR5_it_walks_and_each_mod_keeps_its_defaults",
            b:get("ai/agent").think_hz == 5 and b:get("ai/nav").capabilities.walk == true and b:get("ai/perception").vision_range == 18
                and b:get("ai/steering").separation_radius == 1.5 and b:get("ai/behavior/chase").speed == 5.2 and b:get("ai/behavior/patrol").radius == 14,
            string.format("think_hz %s, vision %s, separation %s", tostring(b:get("ai/agent").think_hz),
                tostring(b:get("ai/perception").vision_range), tostring(b:get("ai/steering").separation_radius)))
        suite.assert_test("AR6_a_value_given_at_spawn_stays",
            given:get("ai/perception").vision_range == 30 and given:get("ai/perception").hearing_range == 25,
            tostring(given:get("ai/perception").vision_range))
        -- Not `speed`: the chosen behaviour writes its own speed there, patrol's being 1.8 too.
        local steer = slow:get("ai/steering")
        suite.assert_test("AR6b_a_creature_built_on_it_sets_its_own_numbers",
            slow:has("ai/archetype/wanderer") and steer.separation_radius == 1.6 and steer.arrive_radius == 0.9,
            string.format("separation %s", tostring(steer.separation_radius)))
        local plain = bodies(world, "plain")[1]
        suite.assert_test("AR7_a_body_from_a_plain_spawner_stays_plain",
            plain ~= nil and not plain:has("ai/archetype/wanderer") and not plain:has("ai/agent") and plain:has("movement"), "")
        local alone = bodies(world, "alone")[1]
        suite.assert_test("AR7b_its_base_makes_the_bodies_with_nothing_else_said", alone ~= nil and alone:has("ai/archetype/wanderer"), "")
        body_id = b:id()
        step("walking")

    elseif phase == "walking" and clock > 3 then
        local moved = false
        for _, b in ipairs(pack) do
            local at = world:get_entity(b:id()).GlobalTransform:compute_transform().translation
            moved = moved or math.abs(math.sqrt(at.x ^ 2 + at.z ^ 2) - 10) > 0.5
        end
        suite.assert_test("AR8_left_alone_it_wanders", moved, "")
        commands:entity(body_id):remove("ai/archetype/wanderer")
        step("taken off")

    elseif phase == "taken off" and clock > 0.5 then
        local b
        for _, one in ipairs(pack) do
            if one:id() == body_id then
                b = one
            end
        end
        local stayed = {}
        for _, name in ipairs({ "ai/nav", "ai/nav/request", "ai/steering", "ai/perception", "ai/behavior/chase", "ai/behavior/patrol" }) do
            if b:has(name) then
                stayed[#stayed + 1] = name
            end
        end
        suite.assert_test("AR9_taken_off_what_it_declared_goes", #stayed == 0, table.concat(stayed, ", "))
        suite.assert_test("AR10_with_its_base", not b:has("ai/agent") and not b:has("ai/agent/memory"), "")
        suite.assert_test("AR11_and_its_options_go", not b:has("ai/agent/options"), "")
        suite.assert_test("AR12_the_body_stays_a_body", b:has("movement"), "")
        phase = "done"
        suite.finish("WandererSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("AR0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("WandererSuite")
    end
end):in_set("zz/wanderer_suite")
