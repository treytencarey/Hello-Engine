-- --host
-- `vr/input` on this client's own player, fed the messages the engine's VR plugin writes, one of
-- each a frame, as a headset does. Its effect is what `input` then does with them.
--
--   VI1  the a button presses its key, and an action bound to that key follows it
--   VI2  a trigger presses past `press` and lets go only under `release`
--   VI3  a trigger maps to a mouse button
--   VI4  a stick does nothing inside its deadzone; past it, the action's strength runs from 0 to 1
--   VI5  a stick held still writes nothing more
--   VI6  up on the right stick scrolls, as a wheel does
--   VI7  another mapping of a control takes effect
--   VI8  a pose lands in world space through the player's rig, every field, the latest of a frame
--   VI9  another player's copy gets nothing
--   VI10 a reload of the mod lets go of nothing and presses nothing twice
--   VI11 the mod going lets go of what is held, and takes its parts
--   VI12 put back with the mod loading again and a stick pushed, no old removal lets go of it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local VrInputRaw = require("hello::vr_messages::VrInputRaw")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("VrInputSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/player"] = {},
        ["vr/input"] = {},
        input = {},
        ["input/mode"] = { mode = "input/game" },
        ["input/game"] = {
            zz = {
                jump = { key = "Space" },
                walk = { key = "KeyW" },
                fire = { button = "Left" },
                zoom = { scroll = true },
                grip = { key = "KeyG" },
                other = { key = "KeyE" },
            },
        },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = {},
    })
    commands:spawn({
        ["zz/copy"] = {},
        ["vr/input"] = {},
        ["core/net/sync"] = false,
        Transform = {},
    })
end)

local function me(world)
    return world:query({
        with = { "zz/player" },
        optional = {
            "vr/input",
            "vr/input/held",
            "vr/input/pose",
            "input/game/zz/jump",
            "input/game/zz/walk",
            "input/game/zz/fire",
            "input/game/zz/zoom",
            "input/game/zz/grip",
            "input/game/zz/other",
        },
    })[1]
end

local analog_writes, jump_adds = 0, 0
app:add_systems(Update, {
    bevy.MessageReader["input/analog"],
    Query[{ added = { "input/game/zz/jump" } }],
}, function(analog, jumps)
    analog_writes = analog_writes + #analog:read()
    jump_adds = jump_adds + #jumps:iter()
end):in_set("zz/vr_input_edges")

-- What the headset says this frame.
local raw, pose = {}, nil
local function close(a, b) return math.abs(a - b) < 0.001 end

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end

step(function(world) return me(world) ~= nil and me(world):get("vr/input").press ~= nil end, function()
    raw = { a = true }
end)
step(after(0.3), function(world)
    suite.assert_test("VI1_a_presses_its_key", me(world):has("input/game/zz/jump"), "")
    raw = {}
end)
step(after(0.3), function(world)
    suite.assert_test("VI1_and_letting_go_releases_it", not me(world):has("input/game/zz/jump"), "")
    raw = { right_grip = 0.5 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI2_under_press_is_not_pressed", not me(world):has("input/game/zz/grip"), "")
    raw = { right_grip = 0.7 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI2_past_press_is_pressed", me(world):has("input/game/zz/grip"), "")
    raw = { right_grip = 0.5 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI2_between_release_and_press_it_stays", me(world):has("input/game/zz/grip"), "")
    raw = { right_grip = 0.3 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI2_under_release_it_lets_go", not me(world):has("input/game/zz/grip"), "")
    raw = { right_trigger = 1 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI3_a_trigger_is_a_mouse_button", me(world):has("input/game/zz/fire"), "")
    raw = { left_stick_y = 0.1 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI4_inside_the_deadzone_nothing", not me(world):has("input/game/zz/walk"), "")
    raw = { left_stick_y = 0.5 }
end)
step(after(0.3), function(world)
    local walk = me(world):get("input/game/zz/walk")
    suite.assert_test("VI4_past_it_a_strength", walk ~= nil and close(walk.value, 0.35 / 0.85), walk and tostring(walk.value) or "none")
    analog_writes = 0
end)
step(after(0.5), function()
    suite.assert_test("VI5_a_stick_held_still_writes_nothing_more", analog_writes == 0, tostring(analog_writes))
    raw = { left_stick_y = 1 }
end)
step(after(0.3), function(world)
    local walk = me(world):get("input/game/zz/walk")
    suite.assert_test("VI4_at_full_stick_it_is_one", walk ~= nil and close(walk.value, 1), walk and tostring(walk.value) or "none")
    raw = { right_stick_y = 0.8 }
end)
step(function(world) return me(world):has("input/game/zz/zoom") end, function(world)
    suite.assert_test("VI6_the_right_stick_scrolls", close(me(world):get("input/game/zz/zoom").dy, 0.8), "")
    raw = {}
end)
step(after(0.3), function()
    raw = { b = true }
end)
step(after(0.3), function(world)
    suite.assert_test("VI7_only_its_mapped_key_is_held", not me(world):has("input/game/zz/other"), "")
    raw = {}
end)
step(after(0.2), function(world, commands)
    commands:entity(me(world):id()):patch({ ["vr/input"] = { controls = { b = { key = "KeyE" } } } })
end)
step(after(0.2), function()
    raw = { b = true }
end)
step(after(0.3), function(world, commands)
    suite.assert_test("VI7_another_mapping_takes_effect", me(world):has("input/game/zz/other"), "")
    raw = {}
    commands:entity(me(world):id()):patch({
        VmXrRig = { translation = { x = 10, y = 0, z = 0 }, yaw = math.pi / 2 },
    })
end)
step(after(0.2), function()
    pose = {
        hmd_position = { x = 0, y = 1.5, z = -2 },
        hmd_rotation = { x = 0, y = 0, z = 0, w = 1 },
        hmd_forward = { x = 0, y = 0, z = -1 },
        left_position = { x = 1, y = 1, z = 0 },
        left_rotation = { x = 0, y = 0, z = 0, w = 1 },
        left_forward = { x = 1, y = 0, z = 0 },
        right_position = { x = 0, y = 2, z = 3 },
        right_rotation = { x = 0, y = 0, z = 0, w = 1 },
        right_forward = { x = 0, y = 1, z = 0 },
    }
end)
step(after(0.3), function(world)
    local p = me(world):get("vr/input/pose")
    local turn = Quat.from_rotation_y(math.pi / 2)
    local turned = Quat.mul_quat(turn, { x = 0, y = 0, z = 0, w = 1 })
    -- Turned a quarter to the left about the rig at x = 10: -Z goes to -X, +X to -Z.
    suite.assert_test("VI8_the_head_lands_in_world_space", p ~= nil and close(p.hmd_position.x, 8) and close(p.hmd_position.y, 1.5) and close(p.hmd_position.z, 0),
        p and string.format("%.3f %.3f %.3f", p.hmd_position.x, p.hmd_position.y, p.hmd_position.z) or "none")
    suite.assert_test("VI8_a_rotation_turns_with_the_rig", p ~= nil and close(p.hmd_rotation.y, turned.y) and close(p.hmd_rotation.w, turned.w), "")
    suite.assert_test("VI8_a_direction_turns_but_does_not_move", p ~= nil and close(p.hmd_forward.x, -1) and close(p.hmd_forward.z, 0), "")
    suite.assert_test("VI8_both_hands_too", p ~= nil
        and close(p.left_position.x, 10) and close(p.left_position.z, -1) and close(p.left_forward.z, -1)
        and close(p.right_position.x, 13) and close(p.right_position.y, 2) and close(p.right_forward.y, 1), "")
    local copy = world:query({ with = { "zz/copy" }, optional = { "vr/input/pose", "vr/input/held" } })[1]
    suite.assert_test("VI9_another_players_copy_gets_nothing", not copy:has("vr/input/pose") and not copy:has("vr/input/held"), "")
    raw = { a = true, left_stick_y = 1 }
    jump_adds = 0
end)
-- A real reload, once it is held, and a release after it.
step(function(world) return me(world):has("input/game/zz/jump") end, function()
    jump_adds = 0
    write_file_bytes("assets/modules/vr/input/init.lua", read_file_bytes("assets/modules/vr/input/init.lua"))
end)
step(after(1.0), function(world)
    suite.assert_test("VI10_held_through_a_reload", me(world):has("input/game/zz/jump") and me(world):has("input/game/zz/walk"), "")
    suite.assert_test("VI10_and_not_pressed_again", jump_adds == 0, tostring(jump_adds))
    raw = { left_stick_y = 1 }
end)
step(after(0.3), function(world)
    suite.assert_test("VI10_a_release_after_it_works", not me(world):has("input/game/zz/jump") and me(world):has("input/game/zz/walk"), "")
    pose = nil
end)
step(after(0.1), function(world, commands)
    commands:entity(me(world):id()):remove("vr/input")
    commands:entity(world:query({ with = { "zz/copy" } })[1]:id()):remove("vr/input")
end)
step(after(0.5), function(world)
    local e = me(world)
    suite.assert_test("VI11_what_was_held_is_let_go", not e:has("input/game/zz/walk"), "")
    suite.assert_test("VI11_its_parts_go_with_it", not e:has("vr/input/held") and not e:has("vr/input/pose"), "")
    raw = {}
end)
step(after(0.2), function(world, commands)
    raw = { left_stick_y = 1 }
    commands:entity(me(world):id()):patch({ ["vr/input"] = {} })
end)
step(after(1.0), function(world)
    suite.assert_test("VI12_the_stick_still_walks", me(world):has("input/game/zz/walk"), "")
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
        suite.finish("VrInputSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 15 then
        suite.assert_test("VI0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("VrInputSuite")
    end
end):in_set("zz/vr_input_drive")
