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
        ["ai/archetype/backrooms_wanderer/spawner"] = {},
    })
    commands:spawn({ ["zz/name"] = { name = "alone" }, ["ai/archetype/backrooms_wanderer/spawner"] = {} })
    commands:spawn({ ["zz/name"] = { name = "plain" }, ["ai/spawner"] = { count = 1, center_x = 200, y = 1 } })
end)

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
            "ai/archetype/backrooms_wanderer",
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

    if phase == "becoming" and #pack == 2 and pack[1]:has("ai/agent/options") and #pack[1]:get("ai/agent/options") == 3 and clock > 0.5 then
        local b = pack[1]
        suite.assert_test("AR1_a_body_from_its_spawner_becomes_the_creature", b:has("ai/archetype/backrooms_wanderer") and b:has("ai/agent"), "")
        suite.assert_test("AR2_its_base_gives_it_memory", b:has("ai/agent/memory"), "")
        suite.assert_test("AR3_it_declares_navigation_steering_and_perception",
            b:has("ai/nav") and b:has("ai/nav/request") and b:has("ai/steering") and b:has("ai/perception"), "")
        suite.assert_test("AR4_and_its_behaviours", b:has("ai/behavior/chase") and b:has("ai/behavior/investigate") and b:has("ai/behavior/patrol"), "")
        suite.assert_test("AR5_with_how_this_creature_wants_each",
            b:get("ai/agent").think_hz == 6 and b:get("ai/nav").capabilities.walk == true and b:get("ai/perception").vision_range == 20
                and b:get("ai/behavior/chase").speed == 5.2 and b:get("ai/behavior/patrol").radius == 14, "")
        suite.assert_test("AR6_what_it_does_not_say_keeps_the_mods_default", b:get("ai/steering").stall_timeout == 1.5, "")
        local plain = bodies(world, "plain")[1]
        suite.assert_test("AR7_a_body_from_a_plain_spawner_stays_plain",
            plain ~= nil and not plain:has("ai/archetype/backrooms_wanderer") and not plain:has("ai/agent") and plain:has("movement"), "")
        local alone = bodies(world, "alone")[1]
        suite.assert_test("AR7b_its_base_makes_the_bodies_with_nothing_else_said", alone ~= nil and alone:has("ai/archetype/backrooms_wanderer"), "")
        body_id = b:id()
        step("walking")

    elseif phase == "walking" and clock > 3 then
        local moved = false
        for _, b in ipairs(pack) do
            local at = world:get_entity(b:id()).GlobalTransform:compute_transform().translation
            moved = moved or math.abs(math.sqrt(at.x ^ 2 + at.z ^ 2) - 10) > 0.5
        end
        suite.assert_test("AR8_left_alone_it_wanders", moved, "")
        commands:entity(body_id):remove("ai/archetype/backrooms_wanderer")
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
