-- --host
-- `facing` on a client, headless. A movement key is held by writing its action as `input` does, and
-- the walk's velocity is written as `movement/walk` leaves it, so only facing turns anything here.
--
--   F1 a character given a variant gets `facing` from its base, with its turn rate
--   F2 walking (a movement key held) turns it toward where it goes, at the turn rate
--   F3 a push, with no key held, does not turn it
--   F4 another client's character is not turned here, even with a target: its rotation comes with
--      its Transform
--   F5 `facing/camera` replaces `facing/velocity`; moving, the body faces where the camera looks
--   F6 standing, a camera that swings does not turn it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")
local Net = require("modules/core/net/shared/net.lua")

local suite = helpers.create_suite("FacingSuite")
local T = suite.assert_test

local own_net

app:add_systems(Startup, { World, Commands }, function(world, commands)
    Net.declare_ownership(world, commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzfacing" },
        ["core/net/sync"] = false,
    }):id()
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/facing" },
        optional = { "facing", "facing/velocity", "facing/camera", "Transform", "camera" },
    })) do
        if e:get("zz/facing").name == name then return e end
    end
end

-- Where the body's front (+Z) points.
local function front(e)
    return Quat.mul_vec3(e:get("Transform").rotation, { x = 0, y = 0, z = 1 })
end

local function near(a, b) return math.abs(a - b) < 0.02 end

local phase, clock = "spawn", 0
local turned_at

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local me, other = named(world, "me"), named(world, "other")

    if phase == "spawn" and clock > 0.2 then
        for _, name in ipairs({ "me", "other" }) do
            commands:spawn({
                ["zz/facing"] = { name = name },
                ["facing/velocity"] = {},
                ["core/net/owner"] = name == "me" and own_net or nil,
                Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
                Transform = {},
                camera = { yaw = 0 },
                ["core/net/sync"] = false,
            })
        end
        step("spawned")

    elseif phase == "spawned" and ((me and me:has("facing") and other and other:has("facing")) or clock > 5) then
        local f = me and me:get("facing")
        T("F1_a_variant_brings_facing_with_its_turn_rate", f ~= nil and f.turn_rate == 10 and f.target == nil,
            tostring(f and f.turn_rate))
        -- walking toward -X: a quarter turn, about 0.16 s at 10 radians a second
        for _, e in ipairs({ me, other }) do
            commands:entity(e:id()):insert({
                ["input/game/movement/forward"] = { value = 1 },
                Velocity3d = { linvel = { x = -6, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
            })
        end
        commands:entity(other:id()):insert({ facing = { target = Quat.from_rotation_y(-math.pi / 2), turn_rate = 10 } })
        step("walking")

    elseif phase == "walking" then
        if turned_at == nil and front(me).x < -0.99 then turned_at = clock end
        if clock < 0.6 then return end
        T("F2_walking_turns_it_toward_where_it_goes_at_the_turn_rate", turned_at ~= nil and turned_at > 0.1
            and turned_at < 0.4, "turned in " .. tostring(turned_at) .. " s, front.x=" .. string.format("%.2f", front(me).x))
        T("F4_another_clients_character_is_not_turned_here", near(front(other).z, 1), string.format("%.2f", front(other).z))
        -- let go, then something pushes it along +Z
        commands:entity(me:id()):remove("input/game/movement/forward")
        commands:entity(me:id()):insert({ Velocity3d = { linvel = { x = 0, y = 0, z = 3 }, angvel = { x = 0, y = 0, z = 0 } } })
        step("pushed")

    elseif phase == "pushed" and clock > 0.5 then
        T("F3_a_push_with_no_key_held_does_not_turn_it", front(me).x < -0.99, string.format("front.x=%.2f", front(me).x))
        -- strafing along +Z with the camera turned a quarter
        commands:entity(me:id()):insert({
            ["facing/camera"] = {},
            camera = { yaw = -math.pi / 2 },
            Velocity3d = { linvel = { x = 0, y = 0, z = 3 }, angvel = { x = 0, y = 0, z = 0 } },
        })
        step("strafing")

    elseif phase == "strafing" and clock > 0.6 then
        -- a look down -Z turned by yaw -pi/2 looks along +X, and so does the body
        T("F5_camera_replaces_velocity_and_moving_faces_where_the_camera_looks", me:has("facing/camera")
            and not me:has("facing/velocity") and front(me).x > 0.99,
            string.format("camera=%s velocity=%s front.x=%.2f", tostring(me:has("facing/camera")),
                tostring(me:has("facing/velocity")), front(me).x))
        commands:entity(me:id()):insert({
            camera = { yaw = 0 },
            Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        })
        step("standing")

    elseif phase == "standing" and clock > 0.5 then
        T("F6_standing_a_swinging_camera_does_not_turn_it", front(me).x > 0.99, string.format("front.x=%.2f", front(me).x))
        phase = "done"
        suite.finish("FACING")
    end

    if phase ~= "done" and clock > 10 then
        T("F0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("FACING")
    end
end):in_set("zz/facing_suite")
