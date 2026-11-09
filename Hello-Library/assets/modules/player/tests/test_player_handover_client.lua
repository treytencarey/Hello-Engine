-- --host
-- The local player on a client, handed to another world: the net client takes `core/net/local`
-- off when the server demotes the player, and the entity stays, moved by what the server sends.
--
--   HC1 the local player's body is the owner's, dynamic
--   HC2 once it is no longer this client's, its body is kinematic again and at rest
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerHandoverClientSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local function me(world)
    return world:query({ with = { "zz/phc/me" }, optional = { "RigidBody3d", "Velocity3d", "core/net/local", "player" } })[1]
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            player = { client_id = 7, spawn_index = 1 },
            Transform = { translation = { x = 0, y = 50, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            LockedAxes3d = "ROTATION_LOCKED",
            Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
            ["core/net/local"] = true,
            ["core/net/sync"] = false,
            ["zz/phc/me"] = {},
        })
        step("owned")

    elseif phase == "owned" and me(world) ~= nil and me(world):get("RigidBody3d") == "Dynamic" then
        T("HC1_the_local_players_body_is_dynamic", true, "")
        commands:entity(me(world):id()):insert({
            Velocity3d = { linvel = { x = 4, y = 0, z = 3 }, angvel = { x = 0, y = 0, z = 0 } },
        })
        step("moving")

    elseif phase == "moving" and clock > 0.2 then
        commands:entity(me(world):id()):remove("core/net/local")
        step("handed")

    elseif phase == "handed" and clock > 0.3 then
        local p = me(world)
        local v = p:get("Velocity3d").linvel
        T("HC2_handed_over_its_body_is_kinematic_and_at_rest",
            p:get("RigidBody3d") == "KinematicPositionBased" and math.abs(v.x) < 1e-3 and math.abs(v.y) < 1e-3
                and math.abs(v.z) < 1e-3 and p:has("player"),
            string.format("body=%s v=%.2f %.2f %.2f", tostring(p:get("RigidBody3d")), v.x, v.y, v.z))
        phase = "done"
        suite.finish("PlayerHandoverClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("HC0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerHandoverClientSuite")
    end
end):in_set("zz/player_handover_client_suite")
