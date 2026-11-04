-- --host
-- A 2D player over a real connection: an isolated server world runs `player/2d/spawner`, and this VM
-- is a client of it, in the shape a world would be. Its world names no sheet, so no sprite is drawn:
-- `animation/sprite`'s windowed suite covers what builds one.
--
--   N1  this client's player arrives and is marked its own, with its identity, and nothing 3D
--   N2  it starts in game input with its sidebar, its keys bound
--   N3  its own body turns dynamic, as it arrived with its collider
--   N4  its camera arrives at 1:1, and an eye is there at that scale
--   N5  its sprite's settings cross whole, naming no image
--   N6  a key walks it here, its clip follows, and the server's Transform follows what the owner sends
--   N7  another client's player follows the server here, kinematic, and binds nothing
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("Player2dNetSuite")

local PORT = 15277

local DEFAULTS = { srv_ready = false, server_y = 0 }
local ts = helpers.shared_state("Player2dNetState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_player_2d_net_vm1.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local boot = Instances.boot_data()
local ts = helpers.shared_state("Player2dNetState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zz2d", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zz2d", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/2d/spawner"] = { count = 2 }, ["core/net/sync"] = false })
    -- Another client's player, as the spawner makes one, moved on the server.
    commands:spawn({
        ["zz/other"] = {},
        ["movement/2d"] = {},
        Transform = { translation = { x = 500, y = 0, z = 0 } },
        RigidBody2d = "KinematicPositionBased",
        Collider2d = { capsule_y = { radius = 8, half_height = 10 } },
        GravityScale2d = 0,
        ["core/net/owner"] = { client_id = 999 },
        ["core/net/sync"] = {
            Transform = { authority = "server", reliable = false },
            RigidBody2d = { authority = "server" },
            Collider2d = { authority = "server" },
            GravityScale2d = { authority = "server" },
            ["zz/other"] = { authority = "server" },
        },
    })
end)
app:add_systems(Update, { Res[Time], Query[{ with = { "zz/other", Mut["Transform"] } }] }, function(time, others)
    for _, e in ipairs(others:iter_mut()) do
        local t = e:get("Transform").translation
        e:patch({ Transform = { translation = { x = t.x, y = t.y + 40 * time:delta_secs(), z = t.z } } })
    end
    ts.srv_ready = true
end):in_set("zz/player_2d_net_other")
app:add_systems(Update, { Query[{ with = { "player/2d", "Transform" } }] }, function(players)
    for _, p in ipairs(players:iter()) do
        ts.server_y = p:get("Transform").translation.y
    end
end):in_set("zz/player_2d_net_report")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_player_2d_net_vm1.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
}, { headless = true })

local key_frames = {}
app:add_systems(First, { World }, function(world)
    local ev = table.remove(key_frames, 1)
    if ev ~= nil then world:write_message("input/synthetic_key", ev) end
end):in_set("zz/player_2d_net_keys")
local function key(code, state)
    key_frames[#key_frames + 1] = { key_code = code, state = state }
end

local function mine(world)
    return world:query({
        with = { "player/2d", "core/net/local" },
        optional = {
            "player", "movement", "camera/third_person", "animation",
            "core/player/attest", "input/mode", "input/game", "sidebar", "RigidBody2d", "Velocity2d",
            "camera", "camera/2d", "movement/2d", "animation/sprite", "animation/sprite/playing", "Children",
        },
    })[1]
end

local function other(world)
    return world:query({
        with = { "zz/other" },
        optional = { "RigidBody2d", "input/game", "core/net/local" },
    })[1]
end

local function at(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform().translation
end

local phase, t, mark = "wait_srv", 0, 0
local start, server_start, other_y

app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    local function step(next_phase) phase, mark = next_phase, t end
    local since = t - mark

    if phase == "wait_srv" and ts.srv_ready then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zz2d_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zz2d_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        step("connecting")

    elseif phase == "connecting" and mine(world) ~= nil and other(world) ~= nil then
        step("settling")

    elseif phase == "settling" and since > 1.5 then
        local me = mine(world)
        suite.assert_test("N1a_this_clients_player_arrives_with_its_identity", me:has("core/player/attest"), "")
        suite.assert_test("N1b_and_nothing_3d",
            not me:has("player") and not me:has("movement") and not me:has("camera/third_person") and not me:has("animation"), "")
        local keys = (me:get("input/game") or {}).movement_2d
        suite.assert_test("N2_it_starts_in_game_input_with_its_sidebar_its_keys_bound",
            (me:get("input/mode") or {}).mode == "input/game" and me:has("sidebar") and keys ~= nil and keys.up.key == "KeyW", "")
        suite.assert_test("N3_its_own_body_turns_dynamic", me:get("RigidBody2d") == "Dynamic", tostring(me:get("RigidBody2d")))
        local camera = me:get("camera") or {}
        local eyes = world:query({
            iter_many = world:descendants(me:id()),
            with = { "camera/2d/eye", "Transform" },
        })
        suite.assert_test("N4_its_camera_arrives_at_1_to_1_with_an_eye",
            camera.distance == 1 and #eyes == 1 and eyes[1]:get("Transform").scale.x == 1, "distance " .. tostring(camera.distance) .. " eyes " .. #eyes)
        local sprite = me:get("animation/sprite") or {}
        suite.assert_test("N5_its_sprites_settings_cross_whole_naming_no_image", sprite.image == nil and sprite.columns == 1 and sprite.clips ~= nil and sprite.speed == 1, "")
        start, server_start = at(world, me), ts.server_y
        other_y = at(world, other(world)).y
        key("KeyW", "Pressed")
        step("walking")

    elseif phase == "walking" and since > 1.5 then
        local me = mine(world)
        local now = at(world, me)
        suite.assert_test("N6a_a_key_walks_it_here", now.y > start.y + 100, string.format("%.2f to %.2f", start.y, now.y))
        local playing = me:get("animation/sprite/playing") or {}
        suite.assert_test("N6b_its_clip_follows", playing.state == "walk_up", tostring(playing.state))
        suite.assert_test("N6c_the_servers_transform_follows_what_the_owner_sends",
            ts.server_y > server_start + 100, string.format("%.2f to %.2f", server_start, ts.server_y))
        local copy = other(world)
        local y = at(world, copy).y
        suite.assert_test("N7a_another_clients_player_follows_the_server_here", y > other_y + 20, string.format("%.2f to %.2f", other_y, y))
        suite.assert_test("N7b_kinematic_and_bound_to_nothing",
            copy:get("RigidBody2d") == "KinematicPositionBased" and not copy:has("input/game") and not copy:has("core/net/local"), "")
        key("KeyW", "Released")
        phase = "done"
        suite.finish("Player2dNetSuite")
    end

    if phase ~= "done" and since > 20 then
        suite.assert_test("N0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        phase = "done"
        suite.finish("Player2dNetSuite")
    end
end):in_set("zz/player_2d_net_client")
