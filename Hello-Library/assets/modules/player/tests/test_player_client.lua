-- --host (windowed: input and the sidebar act on a window)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ Camera2d = {}, Camera = { order = 0 } })
end)

-- A player as the server sends it: kinematic, with its collider.
local function arrive(commands, name)
    commands:spawn({
        ["zz/name"] = { name = name },
        player = { client_id = name == "me" and 1 or 2, spawn_index = 1 },
        Transform = { translation = { x = 0, y = 3, z = 0 } },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        ["core/net/sync"] = false,
    })
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "player", "input", "sidebar", "RigidBody3d" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function y_of(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform().translation.y
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        arrive(commands, "me")
        arrive(commands, "other")
        step("arrived")

    -- The net client marks its own player local frames after it arrives.
    elseif phase == "arrived" and clock > 0.3 then
        suite.assert_test("C0b_nothing_happens_before_the_player_is_ours", not named(world, "me"):has("input"), "")
        named(world, "me"):patch({ ["core/net/local"] = {} })
        step("local")

    elseif phase == "local" and clock > 1.0 then
        local me, other = named(world, "me"), named(world, "other")
        suite.assert_test("C1_the_local_player_starts_in_game_input_with_its_sidebar",
            me:get("input").mode == "input/game" and me:has("sidebar")
                and #world:query({ with = { "sidebar/container" } }) == 1, "")
        suite.assert_test("C2_its_own_body_turns_dynamic_and_falls",
            me:get("RigidBody3d").Dynamic == true and y_of(world, me) < 2,
            string.format("y=%.2f", y_of(world, me)))
        suite.assert_test("C3_a_remote_player_is_left_as_the_server_sent_it",
            other:get("RigidBody3d").KinematicPositionBased == true and not other:has("input")
                and not other:has("sidebar") and math.abs(y_of(world, other) - 3) < 0.01, "")
        me:remove("player")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local me = named(world, "me")
        suite.assert_test("C4_removing_player_takes_off_input_and_sidebar",
            me ~= nil and not me:has("input") and not me:has("sidebar"), "")
        phase = "done"
        suite.finish("PlayerClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerClientSuite")
    end
end):in_set("zz/player_client_suite")
