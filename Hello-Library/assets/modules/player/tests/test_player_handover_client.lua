-- --host
-- The local player on a client, handed to another world: the net client takes `core/net/local`
-- off when the server demotes the player, and the entity stays, moved by what the server sends.
-- Then this client world as the target of a predicted crossing, still only watching: root is
-- stubbed by its ask as it arrives here, an entity carrying `WorldMirror { world_id = 0 }`; a
-- lookalike is a mirror from another VM, or this VM's own entity.
--
--   HC1 the local player's body is the owner's, dynamic
--   HC2 once it is no longer this client's, its body is kinematic again and at rest
--   HS1 no stand-in from a lookalike ask, nor from root's naming another world
--   HS2 root's predicted ask naming this world through a door makes the stand-in at once, with no
--       body while its place has not landed
--   HS3 ...and its body once the place lands: at the place times where the player stood relative
--       to the door, turned likewise, with the player's whole camera, its yaw turned by its facing,
--       local and never synced
--   HS4 confirmed (`promoting`), it stays
--   HS5 the real player arriving takes its place and its whole camera, and it goes
--   HS6 a prediction through any other portal stands it where the player stood
--   HS7 the prediction failing takes it away
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local Quat = require("bevy::math::Quat")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerHandoverClientSuite")
local T = suite.assert_test

local HERE = "github:zzphc/here:main"
local ELSEWHERE = "github:zzphc/elsewhere:main"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = true },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
end)

local function me(world)
    return world:query({ with = { "zz/phc/me" }, optional = { "RigidBody3d", "Velocity3d", "core/net/local", "player" } })[1]
end

-- The stand-ins here, and the first.
local function standins(world)
    local out = world:query({
        with = { "player/spawner/standin" },
        without = { "core/world/flip" },
        optional = { "player", "Transform", "camera", "core/net/local", "core/net/sync", "RigidBody3d", "Collider3d",
            "movement", "camera/third_person" },
    })
    return out, out[1]
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-2 end

local function yaw_of(q) return q and Quat.to_euler(q, "YXZ")[1] end

-- A predicted ask as root's arrives here, carrying where the player stood relative to a door and
-- its look relative to its body.
local function ask(scope, status, at, from)
    local q = Quat.from_rotation_y(0.5 - math.pi / 2)
    return {
        ["core/world/flip"] = {
            scope = scope,
            status = status,
            predicted = {
                at = at,
                place = {
                    translation = { x = -2, y = 1, z = 2 },
                    rotation = { x = q.x, y = q.y, z = q.z, w = q.w },
                    scale = { x = 1, y = 1, z = 1 },
                },
                look = { yaw = 0.8, pitch = -0.1, distance = 6, height = 2 },
            },
        },
        ["player/spawner/standin"] = {},
        WorldMirror = from ~= nil and { world_id = from } or nil,
        ["core/net/sync"] = false,
    }
end

local phase, clock = "spawn", 0
local rooted

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
        commands:entity(p:id()):despawn()
        commands:spawn(ask(HERE, "predicted", "zz_arrival", nil))
        commands:spawn(ask(HERE, "predicted", "zz_arrival", 7))
        commands:spawn(ask(ELSEWHERE, "predicted", "zz_arrival", 0))
        step("lookalikes")

    elseif phase == "lookalikes" and clock > 0.5 then
        T("HS1_no_stand_in_from_a_lookalike_or_from_root_s_ask_naming_another_world", #standins(world) == 0,
            "stand-ins=" .. #standins(world))
        rooted = commands:spawn(ask(HERE, "predicted", "zz_arrival", 0)):id()
        step("predicted")

    elseif phase == "predicted" and clock > 0.3 then
        local all, s = standins(world)
        T("HS2_root_s_predicted_ask_makes_the_stand_in_at_once_with_no_body_until_its_place_lands",
            #all == 1 and not s:has("player") and not s:has("RigidBody3d"), "stand-ins=" .. #all)
        -- The node the door's `at` names lands, at (10, 0, 5) turned half a turn.
        commands:spawn({ Name = "zz_arrival", Transform = { translation = { x = 10, y = 0, z = 5 },
            rotation = Quat.from_rotation_y(math.pi) }, ["core/net/sync"] = false })
        step("landed")

    elseif phase == "landed" and clock > 0.3 then
        local all, s = standins(world)
        local t = s and s:get("Transform")
        local at = t and t.translation or {}
        local cam = s and s:get("camera") or {}
        -- Relative (-2, 1, 2) at (10, 0, 5) half turned is (12, 1, 3); the body turned 0.5 - pi/2
        -- there is turned pi/2 + 0.5, and the look 0.8 to its left is pi/2 + 1.3.
        T("HS3_once_the_place_lands_it_stands_there_turned_with_the_whole_camera_local_and_never_synced",
            #all == 1 and s:has("player") and s:get("RigidBody3d") == "Dynamic" and s:has("Collider3d")
                and s:has("movement") and s:has("camera/third_person") and s:has("core/net/local")
                and s:get("core/net/sync") == false
                and near(at.x, 12) and near(at.z, 3) and near(yaw_of(t.rotation), math.pi / 2 + 0.5)
                and near(cam.yaw, math.pi / 2 + 1.3) and near(cam.pitch, -0.1) and cam.distance == 6 and cam.height == 2,
            string.format("stand-ins=%d at=%s,%s,%s turned=%s yaw=%s distance=%s", #all, tostring(at.x), tostring(at.y),
                tostring(at.z), tostring(t and yaw_of(t.rotation)), tostring(cam.yaw), tostring(cam.distance)))
        commands:entity(rooted):entry("core/world/flip"):and_modify(function(flip) flip.status = "promoting" end)
        step("confirmed")

    elseif phase == "confirmed" and clock > 0.3 then
        local all = standins(world)
        T("HS4_confirmed_it_stays", #all == 1, "stand-ins=" .. #all)
        commands:spawn({
            player = { client_id = 7, spawn_index = 1 },
            Transform = { translation = { x = 0, y = 50, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            LockedAxes3d = "ROTATION_LOCKED",
            camera = { yaw = 0, pitch = 0 },
            ["core/net/local"] = true,
            ["core/net/sync"] = false,
            ["zz/phc/real"] = {},
        })
        step("arrived")

    elseif phase == "arrived" and clock > 0.3 then
        local real = world:query({ with = { "zz/phc/real" }, optional = { "Transform", "camera" } })[1]
        local t = real and real:get("Transform")
        local at = t and t.translation or {}
        local cam = real and real:get("camera") or {}
        T("HS5_the_real_player_takes_its_place_and_whole_camera_and_it_goes",
            #standins(world) == 0 and near(at.x, 12) and near(at.z, 3) and near(yaw_of(t.rotation), math.pi / 2 + 0.5)
                and near(cam.yaw, math.pi / 2 + 1.3) and near(cam.pitch, -0.1) and cam.distance == 6 and cam.height == 2,
            string.format("stand-ins=%d at=%s,%s turned=%s yaw=%s", #standins(world), tostring(at.x), tostring(at.z),
                tostring(t and yaw_of(t.rotation)), tostring(cam.yaw)))
        commands:entity(real:id()):despawn()
        commands:entity(rooted):entry("core/world/flip"):and_modify(function(flip) flip.status = "done" end)
        rooted = commands:spawn(ask(HERE, "predicted", nil, 0)):id()
        step("identity")

    elseif phase == "identity" and clock > 0.3 then
        local all, s = standins(world)
        local t = s and s:get("Transform")
        local at = t and t.translation or {}
        T("HS6_through_any_other_portal_it_stands_where_the_player_stood",
            #all == 1 and near(at.x, -2) and near(at.z, 2) and near(yaw_of(t.rotation), 0.5 - math.pi / 2),
            string.format("stand-ins=%d at=%s,%s", #all, tostring(at.x), tostring(at.z)))
        commands:entity(rooted):entry("core/world/flip"):and_modify(function(flip)
            flip.status = "failed"
            flip.reason = "predict-timeout"
        end)
        step("failed")

    elseif phase == "failed" and clock > 0.3 then
        T("HS7_the_prediction_failing_takes_it_away", #standins(world) == 0, "stand-ins=" .. #standins(world))
        phase = "done"
        suite.finish("PlayerHandoverClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("HC0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerHandoverClientSuite")
    end
end):in_set("zz/player_handover_client_suite")
