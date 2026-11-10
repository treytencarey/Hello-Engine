-- --host
-- `movement/2d` on a client, in a world with no 2D camera: keys go through `input` as the real ones
-- do, and the bodies are what `player/2d/spawner` sends. The wall is a real collider.
--
--   M0   nothing is bound, and the body stays as the server sent it, before the player is ours
--   M1   missing fields get defaults; a body with no velocity gets one
--   M2   the owner binds its keys, and its own body stays kinematic while its player waits: the
--        player mod turns it dynamic
--   M3   up walks up at `speed`, with no gravity and no turn; right walks right
--   M4   two keys at once are no faster than one
--   M5   letting go eases it to rest, and at rest it writes no more
--   M6   a wall stops it, as its own body is simulated
--   M7   another client's copy follows its synced Transform, stays kinematic and binds nothing
--   M8   `input` taken off takes the bindings; added again binds again
--   M9   the mod's file edited: it stays bound and still walks
--   M10  `movement/2d` taken off unbinds only its own group, and its velocity stays
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("Movement2dSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    -- As `player/2d/spawner` sends a body: kinematic, with its collider.
    commands:spawn({
        ["zz/name"] = { name = "me" },
        ["movement/2d"] = {},
        input = {},
        ["input/mode"] = { mode = "input/game" },
        ["input/game"] = { zzother = { go = { key = "KeyO" } } },
        ["core/net/sync"] = false,
        Transform = { translation = { x = 0, y = 0, z = 0 } },
        RigidBody2d = "KinematicPositionBased",
        Collider2d = { capsule_y = { radius = 8, half_height = 10 } },
        LockedAxes2d = "ROTATION_LOCKED",
        GravityScale2d = 0,
    })
    commands:spawn({
        ["zz/name"] = { name = "other" },
        ["movement/2d"] = {},
        ["core/net/sync"] = false,
        Transform = { translation = { x = 300, y = 0, z = 0 } },
        RigidBody2d = "KinematicPositionBased",
        Collider2d = { capsule_y = { radius = 8, half_height = 10 } },
        GravityScale2d = 0,
    })
    commands:spawn({
        ["zz/name"] = { name = "wall" },
        ["core/net/sync"] = false,
        Transform = { translation = { x = -100, y = 0, z = 0 } },
        RigidBody2d = "Fixed",
        Collider2d = { cuboid = { half_x = 5, half_y = 500 } },
    })
end)

-- Keys go through `input` as the real ones do.
local key_frames = {}
app:add_systems(First, { World }, function(world)
    local ev = table.remove(key_frames, 1)
    if ev ~= nil then world:write_message("input/synthetic_key", ev) end
end):in_set("zz/movement_2d_suite_keys")
local function key(code, state)
    key_frames[#key_frames + 1] = { key_code = code, state = state }
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "movement/2d", "Velocity2d", "Transform", "RigidBody2d", "input/game", "core/net/sync/Transform" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function placed(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform()
end

local phase, clock = "arrived", 0
local start

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    -- The net client marks its own player local frames after it arrives.
    if phase == "arrived" and clock > 0.5 then
        local me = named(world, "me")
        suite.assert_test("M0_nothing_happens_before_the_player_is_ours",
            (me:get("input/game") or {}).movement_2d == nil and me:get("RigidBody2d") == "KinematicPositionBased",
            tostring(me:get("RigidBody2d")))
        me:patch({ ["core/net/local"] = {} })
        step("standing")

    elseif phase == "standing" and clock > 0.5 then
        local me, other = named(world, "me"), named(world, "other")
        local m = me:get("movement/2d")
        suite.assert_test("M1_missing_fields_get_defaults_and_a_velocity",
            m.speed == 160 and m.acceleration == 14 and m.deceleration == 20 and m.smoothing == 16
                and me:has("Velocity2d") and other:has("Velocity2d"), "")
        local keys = (me:get("input/game") or {}).movement_2d
        suite.assert_test("M2a_the_owner_binds_its_keys", keys ~= nil and keys.up.key == "KeyW" and keys.right.key == "KeyD", "")
        -- No player mod here, as in a world whose player waits for its map.
        suite.assert_test("M2b_a_player_that_waits_keeps_its_own_body_kinematic",
            me:get("RigidBody2d") == "KinematicPositionBased", tostring(me:get("RigidBody2d")))
        -- The player mod turns its body dynamic then; `movement/2d` leaves this client's own body alone.
        me:patch({ RigidBody2d = "Dynamic" })
        other:patch({ ["core/net/sync/Transform"] = { translation = { x = 300, y = 200, z = 0 } } })
        start = placed(world, me).translation
        key("KeyW", "Pressed")
        step("up")

    elseif phase == "up" and clock > 0.8 then
        local me = named(world, "me")
        local now = placed(world, me)
        local v = me:get("Velocity2d").linvel
        suite.assert_test("M3a_up_walks_up_at_speed",
            math.abs(v.y - 160) < 1 and math.abs(v.x) < 0.1 and now.translation.y > start.y + 60 and math.abs(now.translation.x - start.x) < 1,
            string.format("v=%.2f,%.2f at %.2f,%.2f", v.x, v.y, now.translation.x, now.translation.y))
        suite.assert_test("M3b_a_2d_body_does_not_turn", math.abs(now.rotation.z) < 1e-3 and math.abs(now.rotation.y) < 1e-3, "")
        local other = placed(world, named(world, "other")).translation
        suite.assert_test("M7a_another_clients_copy_follows_its_synced_transform", math.abs(other.y - 200) < 1, string.format("y=%.2f", other.y))
        suite.assert_test("M7b_and_stays_kinematic_and_binds_nothing",
            named(world, "other"):get("RigidBody2d") == "KinematicPositionBased" and not named(world, "other"):has("input/game"), "")
        key("KeyD", "Pressed")
        step("diagonal")

    elseif phase == "diagonal" and clock > 0.8 then
        local v = named(world, "me"):get("Velocity2d").linvel
        suite.assert_test("M4_two_keys_at_once_are_no_faster_than_one",
            math.abs(math.sqrt(v.x * v.x + v.y * v.y) - 160) < 1 and math.abs(v.x - v.y) < 1, string.format("v=%.2f,%.2f", v.x, v.y))
        key("KeyW", "Released")
        step("right")

    elseif phase == "right" and clock > 0.8 then
        local v = named(world, "me"):get("Velocity2d").linvel
        suite.assert_test("M3c_right_walks_right", math.abs(v.x - 160) < 1 and math.abs(v.y) < 0.1, string.format("v=%.2f,%.2f", v.x, v.y))
        key("KeyD", "Released")
        step("rest")

    elseif phase == "rest" and clock > 1.0 then
        local v = named(world, "me"):get("Velocity2d").linvel
        suite.assert_test("M5_letting_go_eases_it_to_rest", v.x == 0 and v.y == 0, string.format("v=%s,%s", v.x, v.y))
        key("KeyA", "Pressed")
        step("wall")

    -- Far enough to pass the wall's face if nothing stopped it.
    elseif phase == "wall" and clock > 3 then
        local x = placed(world, named(world, "me")).translation.x
        suite.assert_test("M6_a_wall_stops_it", x > -100 and x < -70, string.format("x=%.2f", x))
        key("KeyA", "Released")
        named(world, "me"):remove("input")
        step("no input")

    elseif phase == "no input" and clock > 0.3 then
        local me = world:get_entity(named(world, "me"):id())
        suite.assert_test("M8a_removing_input_takes_the_bindings", (me:get("input/game") or {}).movement_2d == nil, "")
        named(world, "me"):patch({
            input = {},
            ["input/mode"] = { mode = "input/game" },
            ["input/game"] = { zzother = { go = { key = "KeyO" } } },
        })
        step("input back")

    elseif phase == "input back" and clock > 0.3 then
        suite.assert_test("M8b_input_added_again_binds_again", (named(world, "me"):get("input/game") or {}).movement_2d ~= nil, "")
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/movement/2d/client/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 then
        start = placed(world, named(world, "me")).translation
        key("KeyD", "Pressed")
        step("walking on")

    elseif phase == "walking on" and clock > 0.5 then
        local me = named(world, "me")
        local keys = (me:get("input/game") or {}).movement_2d
        local x = placed(world, me).translation.x
        suite.assert_test("M9_after_a_reload_it_is_bound_and_walks", keys ~= nil and x > start.x + 20, string.format("x=%.2f from %.2f", x, start.x))
        key("KeyD", "Released")
        me:remove("movement/2d")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local me = named(world, "me")
        local game = me:get("input/game") or {}
        suite.assert_test("M10a_removing_it_unbinds_its_own_group_only", game.movement_2d == nil and game.zzother ~= nil, "")
        suite.assert_test("M10b_and_its_velocity_stays", me:has("Velocity2d"), "")
        phase = "done"
        suite.finish("Movement2dSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("M_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("Movement2dSuite")
    end
end):in_set("zz/movement_2d_suite")
