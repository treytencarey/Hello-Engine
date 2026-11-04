-- --host
-- The VR stack over a real connection. An isolated server world runs `player/spawner`, an isolated
-- client world plays, and this VM stands where the host's VR plugin does: what it writes reaches the
-- client through the engine, as a headset's messages do.
--
--   PV1  a player with no headset has `vr` and nothing else of VR: no `vr/active`, its third-person
--        camera and eye untouched, and no file of the stack asks for the host's `VrMode`
--   PV2  a controller alone, with no pose, changes nothing
--   PV3  the first pose: the client states `vr/active` and the server hears it
--   PV4  the camera swaps on both sides, across base levels: third person and its eye go, `camera` stays
--   PV5  `camera/vr`'s tuning crosses whole; this client binds and has a rig and a mirror
--   PV6  another player's copy gets none of it
--   PV7  the body faces where the head looks, standing
--   PV8  the left stick walks, at its strength, where the head looks, and the rig follows
--   PV9  poses stopping: `vr/active` goes on both sides, the desktop camera, eye and bindings return,
--        and a stick still held lets go
--   PV10 poses returning: the same again, one mirror
--   PV11 a reload of the composer on the server, and of `vr` on the client, after all that, doubles and
--        loses nothing, and takes no old removal for a new one
--   PV12 `player/vr` taken off a player that stays: every part goes on both sides, the camera returns
--   PV13 `player` taken off a player in VR: `camera/vr` goes, and no desktop camera comes back
--   PV14 `player/vr` put back, its mods loading again: in VR again, no old removal taken for a new one
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local VrInputRaw = require("hello::vr_messages::VrInputRaw")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("PlayerVrNetSuite")

local PORT = 15377

local DEFAULTS = {
    srv_ready = false,
    reload_server = false,
    reload_client = false,
    take_off_stack = false,
    take_off_player = false,
    put_back_stack = false,
}
local ts = helpers.shared_state("PlayerVrNetState", DEFAULTS)

local GROUND = {
    Transform = { translation = { x = 0, y = -0.5, z = 0 } },
    RigidBody3d = "Fixed",
    Collider3d = { cuboid = { hx = 100, hy = 0.5, hz = 100 } },
    ["core/net/sync"] = false,
}

helpers.make_fixture("modules/test_fixtures/gen_player_vr_net_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PlayerVrNetState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzvr", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzvr", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn(boot.GROUND)
    commands:spawn({ ["player/spawner"] = { count = 1, height = 1 }, ["core/net/sync"] = false })
    -- Another client's player in VR, as this client sees one.
    commands:spawn({
        ["zz/other"] = {},
        ["camera/vr"] = {},
        ["vr/active"] = {},
        Transform = { translation = { x = 30, y = 1, z = 0 } },
        ["core/net/owner"] = { client_id = 999 },
        ["core/net/sync"] = {
            Transform = { authority = "server", reliable = false },
            ["zz/other"] = { authority = "server" },
            ["vr/active"] = { authority = "server" },
        },
    })
    -- A player only this side holds, in VR, for what goes when `player` goes.
    commands:spawn({
        ["zz/quitter"] = {},
        player = { client_id = 998, spawn_index = 0 },
        ["vr/active"] = {},
        Transform = { translation = { x = -30, y = 1, z = 0 } },
        ["core/net/sync"] = false,
        ["core/script/owner"] = false,
    })
end)

local reloaded = false
app:add_systems(Update, {
    World,
    Commands,
}, function(world, commands)
    ts.srv_ready = true
    local me = world:query({
        with = { "player", "core/net/owner" },
        optional = { "player/vr", "vr", "vr/active", "camera", "camera/vr", "camera/3d", "camera/third_person", "movement", "core/net/sync" },
    })[1]
    ts.s_player = me ~= nil
    if me ~= nil then
        ts.s_vr = me:has("vr")
        ts.s_stack = me:has("player/vr")
        ts.s_active = me:has("vr/active")
        ts.s_camera = me:has("camera")
        ts.s_camera_vr = me:has("camera/vr")
        ts.s_camera_3d = me:has("camera/3d")
        ts.s_third = me:has("camera/third_person")
        ts.s_face = (me:get("movement") or {}).face
        ts.s_synced = (me:get("core/net/sync") or {})["vr/active"] ~= nil
        if ts.take_off_stack and me:has("player/vr") then
            commands:entity(me:id()):remove("player/vr")
            ts.take_off_stack = false
        end
        if ts.put_back_stack and not me:has("player/vr") then
            commands:entity(me:id()):patch({ ["player/vr"] = {} })
            ts.put_back_stack = false
        end
    end
    local q = world:query({
        with = { "zz/quitter" },
        optional = { "player", "player/vr", "vr", "camera/vr", "camera/third_person", "movement" },
    })[1]
    if q ~= nil then
        ts.q_camera_vr = q:has("camera/vr")
        ts.q_third = q:has("camera/third_person")
        ts.q_vr = q:has("vr")
        ts.q_stack = q:has("player/vr")
        ts.q_movement = q:has("movement")
        if ts.take_off_player and q:has("player") then
            commands:entity(q:id()):remove("player")
            ts.take_off_player = false
        end
    end
    if ts.reload_server and not reloaded then
        reloaded = true
        local path = "assets/modules/player/vr/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
    end
end):in_set("zz/player_vr_server")
]=])

helpers.make_fixture("modules/test_fixtures/gen_player_vr_net_client.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PlayerVrNetState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn(boot.GROUND)
end)

local joined, reloaded = false, false
app:add_systems(Update, {
    World,
    Commands,
}, function(world, commands)
    if ts.srv_ready and not joined then
        joined = true
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzvr_c", ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzvr_c", ip = "127.0.0.1", port = boot.PORT },
            ["core/net/sync"] = false,
        })
    end
    local me = world:query({
        with = { "player", "core/net/local" },
        optional = {
            "vr",
            "vr/active",
            "vr/tracking",
            "vr/input",
            "vr/input/pose",
            "camera",
            "camera/vr",
            "camera/3d",
            "camera/third_person",
            "movement",
            "VmXrRig",
            "input/game",
            "input/game/movement/forward",
            "Velocity3d",
            "Transform",
        },
    })[1]
    ts.c_player = me ~= nil
    ts.c_eyes = #world:query({ with = { "camera/3d/eye" } })
    ts.c_mirrors = #world:query({ with = { "camera/vr/mirror" } })
    if me ~= nil then
        ts.c_vr = me:has("vr")
        ts.c_active = me:has("vr/active")
        ts.c_tracking = me:has("vr/tracking")
        ts.c_vr_input = me:has("vr/input")
        ts.c_pose = me:has("vr/input/pose")
        ts.c_camera = me:has("camera")
        ts.c_camera_vr = me:has("camera/vr")
        ts.c_camera_3d = me:has("camera/3d")
        ts.c_third = me:has("camera/third_person")
        ts.c_rig = me:has("VmXrRig")
        local game = me:get("input/game") or {}
        ts.c_bound_camera_vr = game.camera_vr ~= nil
        ts.c_bound_third = game.third_person ~= nil
        ts.c_turn_speed = (me:get("camera/vr") or {}).turn_speed
        ts.c_face = (me:get("movement") or {}).face
        ts.c_yaw = (me:get("camera") or {}).yaw
        local forward = me:get("input/game/movement/forward")
        ts.c_forward = forward and forward.value or false
        local v = me:get("Velocity3d")
        ts.c_vx, ts.c_vz = v and v.linvel.x or 0, v and v.linvel.z or 0
        local t = me:get("Transform")
        local front = Quat.mul_vec3(t.rotation, { x = 0, y = 0, z = 1 })
        ts.c_front_x, ts.c_front_z = front.x, front.z
        ts.c_x = t.translation.x
        local rig = me:get("VmXrRig")
        ts.c_rig_x = rig and rig.translation.x or false
    end
    local other = world:query({
        with = { "zz/other" },
        optional = { "camera/vr", "VmXrRig", "vr/input", "input/game", "vr/active", "core/net/local" },
    })[1]
    ts.o_seen = other ~= nil
    if other ~= nil then
        ts.o_camera_vr = other:has("camera/vr")
        ts.o_active = other:has("vr/active")
        ts.o_rig = other:has("VmXrRig")
        ts.o_vr_input = other:has("vr/input")
        ts.o_bound = other:has("input/game")
        ts.o_local = other:has("core/net/local")
    end
    if ts.reload_client and not reloaded then
        reloaded = true
        local path = "assets/modules/vr/client/init.lua"
        write_file_bytes(path, read_file_bytes(path))
    end
end):in_set("zz/player_vr_client")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_player_vr_net_server.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
    GROUND = GROUND,
}, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_player_vr_net_client.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
    GROUND = GROUND,
}, { headless = true })

local function close(a, b, within) return type(a) == "number" and math.abs(a - b) < (within or 0.05) end

-- What the headset says this frame: nothing until a step gives it.
local raw, pose = nil, nil
local x_before = 0
local function look(yaw)
    pose = {
        hmd_position = { x = 0, y = 1.6, z = 0 },
        hmd_rotation = Quat.from_rotation_y(yaw),
        hmd_forward = Quat.mul_vec3(Quat.from_rotation_y(yaw), { x = 0, y = 0, z = -1 }),
    }
end

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end

-- What every side has on the desktop.
local function on_the_desktop(tag)
    suite.assert_test(tag .. "_no_vr_active", not ts.c_active and not ts.s_active, "")
    suite.assert_test(tag .. "_third_person_on_both_sides", ts.c_third and ts.s_third and not ts.c_camera_vr and not ts.s_camera_vr,
        string.format("c %s/%s, s %s/%s", tostring(ts.c_third), tostring(ts.c_camera_vr), tostring(ts.s_third), tostring(ts.s_camera_vr)))
    suite.assert_test(tag .. "_one_eye_no_mirror_no_rig", ts.c_eyes == 1 and ts.c_mirrors == 0 and not ts.c_rig,
        string.format("%d eyes, %d mirrors, rig %s", ts.c_eyes, ts.c_mirrors, tostring(ts.c_rig)))
    suite.assert_test(tag .. "_the_mouse_is_bound", ts.c_bound_third and not ts.c_bound_camera_vr,
        string.format("third %s, camera_vr %s", tostring(ts.c_bound_third), tostring(ts.c_bound_camera_vr)))
    suite.assert_test(tag .. "_it_faces_where_it_goes", ts.c_face == "velocity" and ts.s_face == "velocity", tostring(ts.c_face))
    suite.assert_test(tag .. "_no_controllers", not ts.c_vr_input, "")
end

-- What every side has in VR.
local function in_vr(tag)
    suite.assert_test(tag .. "_vr_active_on_both_sides", ts.c_active and ts.s_active, "")
    suite.assert_test(tag .. "_camera_vr_on_both_sides", ts.c_camera_vr and ts.s_camera_vr, "")
    suite.assert_test(tag .. "_third_person_gone_on_both_sides", not ts.c_third and not ts.s_third and not ts.c_camera_3d and not ts.s_camera_3d,
        string.format("c %s/%s, s %s/%s", tostring(ts.c_third), tostring(ts.c_camera_3d), tostring(ts.s_third), tostring(ts.s_camera_3d)))
    suite.assert_test(tag .. "_camera_stays", ts.c_camera and ts.s_camera, "")
    suite.assert_test(tag .. "_no_eye_one_mirror_a_rig", ts.c_eyes == 0 and ts.c_mirrors == 1 and ts.c_rig,
        string.format("%d eyes, %d mirrors, rig %s", ts.c_eyes, ts.c_mirrors, tostring(ts.c_rig)))
    suite.assert_test(tag .. "_the_stick_is_bound", ts.c_bound_camera_vr and not ts.c_bound_third, "")
    suite.assert_test(tag .. "_it_faces_the_look", ts.c_face == "look" and ts.s_face == "look", tostring(ts.c_face))
    suite.assert_test(tag .. "_controllers", ts.c_vr_input and ts.c_pose, "")
end

step(function()
    return ts.c_player and ts.s_player and ts.o_seen and ts.c_vr and ts.s_synced and ts.c_third and ts.c_eyes == 1
end, function() end)
step(after(1.5), function()
    on_the_desktop("PV1")
    suite.assert_test("PV1_it_has_vr_and_no_tracking", ts.c_vr and ts.s_vr and not ts.c_tracking, "")
    for _, path in ipairs({
        "assets/modules/vr/client/init.lua",
        "assets/modules/vr/server/init.lua",
        "assets/modules/vr/shared/init.lua",
        "assets/modules/vr/input/init.lua",
        "assets/modules/camera/vr/client/init.lua",
        "assets/modules/player/vr/client/init.lua",
        "assets/modules/player/vr/server/init.lua",
    }) do
        suite.assert_test("PV1_no_VrMode_in_" .. path, read_file_bytes(path):find("VrMode", 1, true) == nil, "")
    end
    raw = { left_stick_y = 1, a = true }
end)
step(after(1.0), function()
    on_the_desktop("PV2")
    suite.assert_test("PV2_a_stick_alone_walks_nothing", ts.c_forward == false, tostring(ts.c_forward))
    raw = {}
    look(0)
end)
step(function() return ts.s_camera_vr and ts.c_camera_vr and ts.c_vr_input and ts.c_rig end, function() end)
step(after(1.0), function()
    in_vr("PV3_PV4")
    suite.assert_test("PV5_its_tuning_crosses_whole", ts.c_turn_speed == 2, tostring(ts.c_turn_speed))
    suite.assert_test("PV6_a_copy_keeps_its_camera_and_hears_vr_active", ts.o_camera_vr and ts.o_active and not ts.o_local, "")
    suite.assert_test("PV6_and_gets_no_rig_controllers_or_binding", not ts.o_rig and not ts.o_vr_input and not ts.o_bound, "")
    look(math.pi / 2)
end)
step(after(1.0), function()
    -- A quarter to the left: a look along -X.
    suite.assert_test("PV7_yaw_is_the_heads", close(ts.c_yaw, math.pi / 2), tostring(ts.c_yaw))
    suite.assert_test("PV7_the_body_faces_it_standing", close(ts.c_front_x, -1) and close(ts.c_front_z, 0),
        string.format("%.3f %.3f", ts.c_front_x, ts.c_front_z))
    x_before = ts.c_x
    raw = { left_stick_y = 0.5 }
end)
step(after(1.0), function()
    local strength = 0.35 / 0.85
    suite.assert_test("PV8_the_stick_is_the_walk_key_at_its_strength", close(ts.c_forward, strength, 0.01), tostring(ts.c_forward))
    suite.assert_test("PV8_it_walks_where_the_head_looks", close(ts.c_vx, -6 * strength, 0.1) and close(ts.c_vz, 0, 0.1),
        string.format("%.3f %.3f", ts.c_vx, ts.c_vz))
    suite.assert_test("PV8_the_body_faces_the_look_not_a_new_way", close(ts.c_front_x, -1) and close(ts.c_front_z, 0),
        string.format("%.3f %.3f", ts.c_front_x, ts.c_front_z))
    suite.assert_test("PV8_the_rig_follows", ts.c_x < x_before - 1 and close(ts.c_rig_x, ts.c_x, 0.2),
        string.format("%s %s", tostring(ts.c_x), tostring(ts.c_rig_x)))
    raw = { left_stick_x = 1 }
end)
step(after(1.0), function()
    -- Looking along -X, a push to the right walks along -Z, and the body keeps facing the look.
    suite.assert_test("PV8_a_strafe_goes_sideways", close(ts.c_vz, -6, 0.1) and close(ts.c_vx, 0, 0.1),
        string.format("%.3f %.3f", ts.c_vx, ts.c_vz))
    suite.assert_test("PV8_and_does_not_turn_it", close(ts.c_front_x, -1) and close(ts.c_front_z, 0),
        string.format("%.3f %.3f", ts.c_front_x, ts.c_front_z))
    raw = { left_stick_y = 0.5 }
end)
-- Poses stop, the stick stays pushed.
step(function() return true end, function()
    pose = nil
end)
step(function() return not ts.c_active end, function() end)
step(function() return ts.s_third and ts.c_third and ts.c_eyes == 1 and not ts.c_vr_input end, function() end)
step(after(1.0), function()
    on_the_desktop("PV9")
    suite.assert_test("PV9_a_stick_held_lets_go", ts.c_forward == false, tostring(ts.c_forward))
    suite.assert_test("PV9_and_it_stands_still", close(ts.c_vx, 0, 0.1) and close(ts.c_vz, 0, 0.1),
        string.format("%.3f %.3f", ts.c_vx, ts.c_vz))
    raw = {}
    look(0)
end)
step(function() return ts.s_camera_vr and ts.c_camera_vr and ts.c_vr_input and ts.c_rig end, function() end)
step(after(1.0), function()
    in_vr("PV10")
    ts.reload_server = true
    ts.reload_client = true
end)
step(after(1.5), function()
    in_vr("PV11")
    ts.take_off_stack = true
end)
step(function() return not ts.s_vr and not ts.c_vr end, function() end)
step(after(1.5), function()
    suite.assert_test("PV12_no_stack_no_vr_on_either_side", not ts.s_stack and not ts.s_vr and not ts.c_vr, "")
    suite.assert_test("PV12_no_vr_active_or_its_sync", not ts.c_active and not ts.s_active and not ts.s_synced and not ts.c_tracking, "")
    on_the_desktop("PV12")
    suite.assert_test("PV13_a_quitter_is_in_vr_first", ts.q_camera_vr and ts.q_vr and not ts.q_third, "")
    ts.take_off_player = true
end)
step(after(1.0), function()
    suite.assert_test("PV13_no_vr_camera", not ts.q_camera_vr, "")
    suite.assert_test("PV13_no_desktop_camera_comes_back", not ts.q_third, "")
    suite.assert_test("PV13_no_stack_and_movement_stays_gone", not ts.q_vr and not ts.q_stack and not ts.q_movement, "")
    ts.put_back_stack = true
end)
step(function() return ts.s_camera_vr and ts.c_camera_vr and ts.c_vr_input and ts.c_rig end, function() end)
step(after(1.0), function()
    in_vr("PV14")
    suite.assert_test("PV14_its_sync_stays", ts.s_synced, "")
end)

local done = false
app:add_systems(Update, {
    World,
    bevy.MessageWriter[VrInputRaw],
    bevy.MessageWriter[VrPoseInput],
}, function(world, write_raw, write_pose)
    t = t + world:delta_time()
    if raw ~= nil then
        write_raw:write(raw)
    end
    if pose ~= nil then
        write_pose:write(pose)
    end
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("PlayerVrNetSuite")
    elseif s.ready() then
        s.act()
        at, mark = at + 1, t
    elseif t - mark > 20 then
        suite.assert_test("PV0_stuck_at_step_" .. at, false, string.format(
            "c player %s third %s camera_vr %s active %s; s player %s third %s camera_vr %s active %s synced %s; other %s",
            tostring(ts.c_player), tostring(ts.c_third), tostring(ts.c_camera_vr), tostring(ts.c_active),
            tostring(ts.s_player), tostring(ts.s_third), tostring(ts.s_camera_vr), tostring(ts.s_active), tostring(ts.s_synced), tostring(ts.o_seen)))
        done = true
        suite.finish("PlayerVrNetSuite")
    end
end):in_set("zz/player_vr_drive")
