-- --host
-- `camera/vr` on this client's own player, with `vr/input` feeding it the messages the engine's VR
-- plugin writes, one of each a frame. What a headset shows is not here: the engine places the eyes
-- from the rig this writes.
--
--   CV1 the rig follows the player, at `height`
--   CV2 the right stick turns the rig, by strength, and right is negative yaw
--   CV3 `camera.yaw` is where the head looks, and the rig's turn counts
--   CV4 with `movement_direction = "body"`, the stick's turn only
--   CV5 one mirror, a child, at the headset's world pose
--   CV6 another player's copy gets no rig, mirror or binding
--   CV7 a reload keeps one mirror, the binding and the turn so far, and it still follows
--   CV8 leaving this client stops the mirror and takes the rig; coming back restores both
--   CV9 its removal takes the rig, the mirror and the binding
--   CV10 removed together with `input`, its cleanup brings no binding back
--   CV11 put back with the mod loading again, no old removal is taken for a new one: the rig, the
--        binding and a mirror that is on
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local VrInputRaw = require("hello::vr_messages::VrInputRaw")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("CameraVrSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/carrier"] = { name = "me" },
        ["camera/vr"] = {},
        ["vr/input"] = {},
        input = {},
        ["input/mode"] = { mode = "input/game" },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = { translation = { x = 4, y = 1, z = 2 } },
    })
    commands:spawn({
        ["zz/carrier"] = { name = "copy" },
        ["camera/vr"] = {},
        input = {},
        ["core/net/sync"] = false,
        Transform = { translation = { x = 40, y = 1, z = 2 } },
    })
    commands:spawn({
        ["zz/carrier"] = { name = "together" },
        ["camera/vr"] = {},
        input = {},
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = { translation = { x = 80, y = 1, z = 2 } },
    })
end)

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "camera", "camera/vr", "VmXrRig", "input/game", "Children", "core/net/local", "Transform" },
    })) do
        if e:get("zz/carrier").name == name then
            return e
        end
    end
end

local function mirrors_of(world, e)
    return world:query({
        iter_many = world:descendants(e:id()),
        with = { "camera/vr/mirror", "Camera" },
    })
end

local function close(a, b) return math.abs(a - b) < 0.01 end

local raw, pose = {}, nil
local head = { x = 1, y = 1.5, z = -1 }
local yaw_before = 0

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end

step(function(world)
    local me = carrier(world, "me")
    return me ~= nil and me:has("VmXrRig") and me:has("input/game") and #mirrors_of(world, me) == 1
end, function(world)
    local rig = carrier(world, "me"):get("VmXrRig")
    suite.assert_test("CV1_the_rig_is_at_the_player_at_height", close(rig.translation.x, 4) and close(rig.translation.y, 0.5) and close(rig.translation.z, 2),
        string.format("%.3f %.3f %.3f", rig.translation.x, rig.translation.y, rig.translation.z))
    raw = { right_stick_x = 1 }
end)
step(after(0.5), function(world)
    local rig = carrier(world, "me"):get("VmXrRig")
    -- 2 rad/s at full stick; the first frames wait for the action.
    suite.assert_test("CV2_full_stick_right_turns_at_turn_speed_negative", rig.yaw < -0.5 and rig.yaw > -1.2, tostring(rig.yaw))
    raw = {}
end)
step(after(0.3), function(world)
    yaw_before = carrier(world, "me"):get("VmXrRig").yaw
    raw = { right_stick_x = 0.575 }
end)
step(after(0.5), function(world)
    -- Half strength past the deadzone turns about half as fast as full.
    local turned = yaw_before - carrier(world, "me"):get("VmXrRig").yaw
    suite.assert_test("CV2_half_stick_turns_slower", turned > 0.2 and turned < 0.6, tostring(turned))
    raw = {}
end)
step(after(0.2), function(world, commands)
    -- The real rig's turn is the world's only turn from here on: a level head, looking along -Z in
    -- tracking space, then turned a quarter by the head.
    yaw_before = carrier(world, "me"):get("VmXrRig").yaw
    pose = {
        hmd_position = head,
        hmd_rotation = Quat.from_rotation_y(math.pi / 2),
        hmd_forward = { x = -1, y = 0, z = 0 },
    }
end)
step(after(0.3), function(world, commands)
    local cam = carrier(world, "me"):get("camera")
    suite.assert_test("CV3_yaw_is_where_the_head_looks", close(cam.yaw, yaw_before + math.pi / 2),
        string.format("%.3f against %.3f", cam.yaw, yaw_before + math.pi / 2))
    commands:entity(carrier(world, "me"):id()):patch({ ["camera/vr"] = { movement_direction = "body" } })
end)
step(after(0.3), function(world, commands)
    local me = carrier(world, "me")
    suite.assert_test("CV4_body_is_the_sticks_turn_only", close(me:get("camera").yaw, me:get("VmXrRig").yaw), tostring(me:get("camera").yaw))
    commands:entity(me:id()):patch({ ["camera/vr"] = { movement_direction = "head" } })
end)
step(after(0.3), function(world)
    local me = carrier(world, "me")
    local mirrors = mirrors_of(world, me)
    suite.assert_test("CV5_one_mirror_a_child_of_the_player", #mirrors == 1, tostring(#mirrors))
    local rig = me:get("VmXrRig")
    local expect = Quat.mul_vec3(Quat.from_rotation_y(rig.yaw), head)
    local global = world:get_entity(mirrors[1]:id()).GlobalTransform:compute_transform()
    suite.assert_test("CV5_it_stands_at_the_headsets_world_pose",
        close(global.translation.x, rig.translation.x + expect.x)
        and close(global.translation.y, rig.translation.y + expect.y)
        and close(global.translation.z, rig.translation.z + expect.z),
        string.format("%.3f %.3f %.3f", global.translation.x, global.translation.y, global.translation.z))
    local turned = Quat.mul_vec3(global.rotation, { x = 0, y = 0, z = -1 })
    local look = Quat.mul_vec3(Quat.from_rotation_y(rig.yaw + math.pi / 2), { x = 0, y = 0, z = -1 })
    suite.assert_test("CV5_and_looks_where_it_looks", close(turned.x, look.x) and close(turned.z, look.z),
        string.format("%.3f %.3f", turned.x, turned.z))
    local copy = carrier(world, "copy")
    suite.assert_test("CV6_a_copy_gets_no_rig_mirror_or_binding",
        not copy:has("VmXrRig") and #mirrors_of(world, copy) == 0 and not copy:has("input/game"), "")
    yaw_before = rig.yaw
    write_file_bytes("assets/modules/camera/vr/client/init.lua", read_file_bytes("assets/modules/camera/vr/client/init.lua"))
end)
step(after(1.0), function(world, commands)
    local me = carrier(world, "me")
    suite.assert_test("CV7_after_a_reload_one_mirror", #mirrors_of(world, me) == 1, tostring(#mirrors_of(world, me)))
    suite.assert_test("CV7_the_turn_so_far_stays", close(me:get("VmXrRig").yaw, yaw_before), tostring(me:get("VmXrRig").yaw))
    suite.assert_test("CV7_the_binding_stays", (me:get("input/game") or {}).camera_vr ~= nil, "")
    commands:entity(me:id()):patch({ Transform = { translation = { x = 7, y = 1, z = 2 } } })
end)
step(after(0.3), function(world, commands)
    local me = carrier(world, "me")
    suite.assert_test("CV7_and_it_still_follows", close(me:get("VmXrRig").translation.x, 7), tostring(me:get("VmXrRig").translation.x))
    commands:entity(me:id()):remove("core/net/local")
end)
step(after(0.3), function(world, commands)
    local me = carrier(world, "me")
    suite.assert_test("CV8_a_player_gone_elsewhere_has_no_rig", not me:has("VmXrRig"), "")
    suite.assert_test("CV8_and_its_mirror_stops", mirrors_of(world, me)[1]:get("Camera").is_active == false, "")
    commands:entity(me:id()):insert({ ["core/net/local"] = {} })
end)
step(after(0.3), function(world, commands)
    local me = carrier(world, "me")
    suite.assert_test("CV8_coming_back_restores_the_rig", me:has("VmXrRig"), "")
    local mirrors = mirrors_of(world, me)
    suite.assert_test("CV8_and_the_same_mirror", #mirrors == 1 and mirrors[1]:get("Camera").is_active == true, tostring(#mirrors))
    commands:entity(me:id()):remove("camera/vr")
    local together = carrier(world, "together")
    commands:entity(together:id()):remove("camera/vr", "input", "input/game")
    commands:entity(carrier(world, "copy"):id()):remove("camera/vr")
end)
step(after(0.5), function(world, commands)
    local me = carrier(world, "me")
    suite.assert_test("CV9_its_removal_takes_the_rig", not me:has("VmXrRig"), "")
    suite.assert_test("CV9_the_mirror", #world:query({ with = { "camera/vr/mirror" } }) == 0, "")
    suite.assert_test("CV9_and_the_binding", (me:get("input/game") or {}).camera_vr == nil, "")
    suite.assert_test("CV10_removed_with_input_no_binding_comes_back", not carrier(world, "together"):has("input/game"), "")
    commands:entity(me:id()):patch({ ["camera/vr"] = {} })
end)
step(after(1.0), function(world)
    local me = carrier(world, "me")
    suite.assert_test("CV11_the_rig_is_back", me:has("VmXrRig"), "")
    suite.assert_test("CV11_the_binding_too", (me:get("input/game") or {}).camera_vr ~= nil, "")
    local mirrors = mirrors_of(world, me)
    suite.assert_test("CV11_and_one_mirror_that_is_on", #mirrors == 1 and mirrors[1]:get("Camera").is_active == true, tostring(#mirrors))
end)

local done = false
app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter[VrInputRaw],
    bevy.MessageWriter[VrPoseInput],
}, function(world, commands, write_raw, write_pose)
    t = t + world:delta_time()
    write_raw:write(raw)
    if pose ~= nil then
        write_pose:write(pose)
    end
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("CameraVrSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 15 then
        suite.assert_test("CV0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("CameraVrSuite")
    end
end):in_set("zz/camera_vr_drive")
