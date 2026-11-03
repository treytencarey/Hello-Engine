-- --host (windowed: keys reach `input` through a window)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("MovementSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ Camera2d = {}, Camera = { order = 0 } })
end)

-- Keys go through `input` as the real ones do.
local key_frames = {}
app:add_systems(First, { World }, function(world)
    local ev = table.remove(key_frames, 1)
    if ev ~= nil and ev.key_code ~= nil then world:write_message("input/synthetic_key", ev) end
end):in_set("zz/movement_suite_keys")
local function key(code, state)
    key_frames[#key_frames + 1] = { key_code = code, state = state }
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "movement", "Velocity3d", "Transform", "input/game", "movement/grounded" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function placed(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform()
end

local phase, clock = "spawn", 0
local start, vy_before

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            ["zz/name"] = { name = "floor" },
            Transform = { translation = { x = 0, y = 0, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 50, hy = 0.1, hz = 50 } },
        })
        -- the local player, as `player` leaves it: a dynamic capsule standing on the floor,
        -- with no velocity (the server sends none); its camera turned a quarter to the left,
        -- so forward is -x
        commands:spawn({
            ["zz/name"] = { name = "me" },
            movement = {},
            camera = { yaw = math.pi / 2 },
            input = {},
            ["input/mode"] = { mode = "input/game" },
            ["core/net/sync"] = false,
            Transform = { translation = { x = 0, y = 1.1, z = 0 } },
            RigidBody3d = "Dynamic",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            LockedAxes3d = "ROTATION_LOCKED",
        })
        -- another client's player
        commands:spawn({
            ["zz/name"] = { name = "other" },
            movement = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = 5, y = 1, z = 0 } },
        })
        step("arrived")

    -- The net client marks its own player local frames after it arrives.
    elseif phase == "arrived" and clock > 0.3 then
        local game = named(world, "me"):get("input/game") or {}
        suite.assert_test("V0b_nothing_is_bound_before_the_player_is_ours", game.movement == nil, "")
        named(world, "me"):patch({ ["core/net/local"] = {} })
        step("standing")

    elseif phase == "standing" and clock > 1.0 then
        local me = named(world, "me")
        local m = me:get("movement")
        local keys = me:get("input/game").movement
        suite.assert_test("V1_missing_fields_get_defaults",
            m.speed == 6 and m.jump == 5 and m.turn == 10 and m.ground == 1 and m.smoothing == 10, "")
        suite.assert_test("V2_the_owner_binds_its_movement_keys",
            keys ~= nil and keys.forward.key == "KeyW" and keys.jump.key == "Space", "")
        suite.assert_test("V3_standing_on_the_floor_is_grounded", me:has("movement/grounded"), "")
        suite.assert_test("V3b_a_player_without_a_velocity_gets_one",
            me:has("Velocity3d") and named(world, "other"):has("Velocity3d"), "")
        start = placed(world, me).translation
        key("KeyW", "Pressed")
        named(world, "other"):patch({ ["core/net/sync/Transform"] = { translation = { x = 5, y = 1, z = 4 } } })
        step("walking")

    elseif phase == "walking" and clock > 0.8 then
        local me = named(world, "me")
        local now = placed(world, me)
        local v = me:get("Velocity3d").linvel
        local facing = Quat.mul_vec3(now.rotation, { x = 0, y = 0, z = 1 })
        suite.assert_test("V4_forward_walks_where_the_camera_looks_at_speed",
            math.abs(v.x + 6) < 0.1 and math.abs(v.z) < 0.1 and now.translation.x < start.x - 2
                and math.abs(now.translation.z - start.z) < 0.2,
            string.format("v=%.2f,%.2f at %.2f,%.2f", v.x, v.z, now.translation.x, now.translation.z))
        suite.assert_test("V5_it_turns_to_face_where_it_goes", facing.x < -0.9, string.format("facing.x=%.2f", facing.x))
        local other = placed(world, named(world, "other")).translation
        suite.assert_test("V6_another_clients_player_follows_its_synced_transform",
            math.abs(other.z - 4) < 0.1, string.format("z=%.2f", other.z))
        key("KeyW", "Released")
        step("stopped")

    elseif phase == "stopped" and clock > 0.3 then
        local v = named(world, "me"):get("Velocity3d").linvel
        suite.assert_test("V7_letting_go_stops_it", math.abs(v.x) < 0.05 and math.abs(v.z) < 0.05,
            string.format("v=%.2f,%.2f", v.x, v.z))
        -- something else pushes it, no key held: it must not turn toward the push
        named(world, "me"):patch({ Velocity3d = { linvel = { x = 0, z = 3 } } })
        step("pushed")

    elseif phase == "pushed" and clock > 0.3 then
        local facing = Quat.mul_vec3(placed(world, named(world, "me")).rotation,
            { x = 0, y = 0, z = 1 })
        suite.assert_test("V5b_a_push_without_keys_does_not_turn_it", facing.x < -0.9, string.format("facing.x=%.2f", facing.x))
        key("KeyW", "Pressed")
        key("KeyD", "Pressed")
        step("two keys")

    elseif phase == "two keys" and clock > 0.4 then
        key("KeyW", "Released")
        step("one key")

    elseif phase == "one key" and clock > 0.4 then
        local v = named(world, "me"):get("Velocity3d").linvel
        -- right, turned a quarter left, is -z
        suite.assert_test("V7b_letting_go_of_one_key_walks_on_with_the_other",
            math.abs(v.x) < 0.1 and math.abs(v.z + 6) < 0.1, string.format("v=%.2f,%.2f", v.x, v.z))
        key("KeyD", "Released")
        key("KeyW", "Pressed")
        key("KeyS", "Pressed")
        step("opposite")

    elseif phase == "opposite" and clock > 0.4 then
        local me = named(world, "me")
        local v = me:get("Velocity3d").linvel
        local facing = Quat.mul_vec3(placed(world, me).rotation, { x = 0, y = 0, z = 1 })
        suite.assert_test("V7c_opposite_keys_stand_still_facing_as_before",
            math.abs(v.x) < 0.05 and math.abs(v.z) < 0.05 and facing.z == facing.z and math.abs(facing.z + 1) < 0.1,
            string.format("v=%.2f,%.2f facing.z=%s", v.x, v.z, tostring(facing.z)))
        key("KeyW", "Released")
        key("KeyS", "Released")
        step("still")

    elseif phase == "still" and clock > 0.5 then
        start = placed(world, named(world, "me")).translation
        key("Space", "Pressed")
        key(nil, nil)
        key("Space", "Released")
        step("jumping")

    -- Well up, past the frames its feet still touch: the ground ray must not find the
    -- player's own body, or a second jump would go.
    elseif phase == "jumping" and clock > 0.4 then
        local me = named(world, "me")
        vy_before = me:get("Velocity3d").linvel.y
        suite.assert_test("V8_space_jumps_and_it_leaves_the_ground",
            placed(world, me).translation.y > start.y + 0.5 and not me:has("movement/grounded"),
            string.format("y=%.2f from %.2f vy=%.2f", placed(world, me).translation.y, start.y, vy_before))
        key("Space", "Pressed")
        key(nil, nil)
        key("Space", "Released")
        step("in the air")

    elseif phase == "in the air" and clock > 0.1 then
        local vy = named(world, "me"):get("Velocity3d").linvel.y
        suite.assert_test("V9_no_second_jump_in_the_air", vy < vy_before, string.format("vy=%.2f was %.2f", vy, vy_before))
        step("landing")

    elseif phase == "landing" and clock > 1.5 then
        local me = named(world, "me")
        suite.assert_test("V10_it_lands_and_stands_again", me:has("movement/grounded"), "")
        key("KeyW", "Pressed")
        step("walking to jump")

    -- A jump while walking: the walk writes only the horizontal velocity, so the jump's
    -- vertical one stays.
    elseif phase == "walking to jump" and clock > 0.4 then
        start = placed(world, named(world, "me")).translation
        key("Space", "Pressed")
        key(nil, nil)
        key("Space", "Released")
        step("walking jump")

    elseif phase == "walking jump" and clock > 0.4 then
        local me = named(world, "me")
        suite.assert_test("V13_a_jump_while_walking_leaves_the_ground",
            placed(world, me).translation.y > start.y + 0.5 and not me:has("movement/grounded"),
            string.format("y=%.2f from %.2f", placed(world, me).translation.y, start.y))
        key("KeyW", "Released")
        step("walking landing")

    elseif phase == "walking landing" and clock > 1.5 then
        local me = named(world, "me")
        me:remove("input")
        step("no input")

    -- `input` taken off and added again: the bindings go with it and come back.
    elseif phase == "no input" and clock > 0.3 then
        local who = named(world, "me")
        suite.assert_test("V12a_removing_input_takes_the_bindings",
            (world:get_entity(who:id()):get("input/game") or {}).movement == nil, "")
        who:patch({ input = {}, ["input/mode"] = { mode = "input/game" } })
        step("input back")

    elseif phase == "input back" and clock > 0.3 then
        local who = named(world, "me")
        suite.assert_test("V12b_input_added_again_binds_again",
            (world:get_entity(who:id()):get("input/game") or {}).movement ~= nil, "")
        who:remove("movement")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local me = named(world, "me")
        local game = me:get("input/game") or {}
        suite.assert_test("V11_removing_movement_unbinds_its_keys_and_grounding",
            game.movement == nil and not me:has("movement/grounded"), "")
        phase = "done"
        suite.finish("MovementSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("V0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("MovementSuite")
    end
end):in_set("zz/movement_suite")
