-- --host
-- What makes a player something an agent can notice: it is a target to look for and it makes noise.
-- The rest of the server half is in test_player_server.lua.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local On = require("bevy::ecs::prelude::On")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerNoticedSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    -- As `player/spawner` makes one.
    commands:spawn({
        ["zz/name"] = { name = "player" },
        player = { client_id = 7, spawn_index = 1 },
        Transform = { translation = { x = 0, y = 3, z = 0 } },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync/Transform"] = { translation = { x = 0, y = 3, z = 0 }, rotation = { x = 0, y = 0, z = 0, w = 1 } },
        ["core/net/sync"] = false,
    })
end)

local sounds = 0
app:add_observer(On["ai/noisemaker/sound"], {}, function()
    sounds = sounds + 1
end)

local function row(world)
    return world:query({
        with = { "zz/name" },
        optional = { "player", "ai/perception/target", "ai/noisemaker", "movement" },
    })[1]
end

local phase, clock, x = "joined", 0, 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    local dt = world:delta_time() or 0
    clock = clock + dt
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "joined" and clock > 0.5 then
        local p = row(world)
        suite.assert_test("PN1_a_player_is_a_target_for_agents", p:has("ai/perception/target"), "")
        suite.assert_test("PN2_and_makes_noise", p:has("ai/noisemaker") and p:get("ai/noisemaker").interval ~= nil, "")
        step("standing")

    elseif phase == "standing" and clock > 1 then
        suite.assert_test("PN3_standing_still_it_is_silent", sounds == 0, "sounds " .. sounds)
        step("running")

    -- The owner runs, as its client's Transform arrives in the shadow.
    elseif phase == "running" then
        x = x + 6 * dt
        row(world):patch({ ["core/net/sync/Transform"] = { translation = { x = x, y = 3, z = 0 } } })
        if clock > 2 then
            suite.assert_test("PN4_running_it_is_heard", sounds > 0, "sounds " .. sounds)
            commands:entity(row(world):id()):remove("player")
            step("removed")
        end

    elseif phase == "removed" and clock > 0.5 then
        local p = row(world)
        suite.assert_test("PN5_removing_player_takes_both_off", not p:has("ai/perception/target") and not p:has("ai/noisemaker"), "")
        suite.assert_test("PN6_with_what_else_it_added", not p:has("movement"), "")
        phase = "done"
        suite.finish("PlayerNoticedSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("PN0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerNoticedSuite")
    end
end):in_set("zz/player_noticed_suite")
