-- --host
-- `vr/pointer` and `vr/grabbable` on this client's own player, fed the poses the engine's VR plugin
-- writes. What needs a view is in `vr/ui_panels/tests/test_vr_ui_panels_windowed.lua`: a ray meets
-- only what a view sees, and a headless run has none.
--
--   VP1 each binds its group in `input/ui`
--   VP2 the ray starts at the right hand and is turned in the hand's own frame by `yaw` and `pitch`
--   VP3 with no turn it is the hand's forward, and a changed `vr/pointer` applies at once
--   VP4 one laser, a child of the player, hidden while nothing is hovered
--   VP5 a reload keeps one laser and the bindings, and the ray still follows the hand
--   VP6 removal takes the bindings, the ray and the laser; removed with `input`, no binding comes back
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("VrPointerSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    for _, name in ipairs({ "me", "together" }) do
        commands:spawn({
            ["zz/carrier"] = { name = name },
            ["vr/pointer"] = {},
            ["vr/grabbable"] = {},
            ["vr/input"] = {},
            input = {},
            ["input/mode"] = { mode = "input/ui" },
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = 2, y = 0, z = 1 } },
        })
    end
end)

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "vr/pointer", "vr/pointer/ray", "input/ui", "Children" },
    })) do
        if e:get("zz/carrier").name == name then
            return e
        end
    end
end

local function lasers(world, e)
    return world:query({ iter_many = world:descendants(e:id()), with = { "vr/pointer/laser" }, optional = { "Visibility" } })
end

local function close(a, b) return math.abs(a.x - b.x) < 1e-3 and math.abs(a.y - b.y) < 1e-3 and math.abs(a.z - b.z) < 1e-3 end
local function show(v) return v and string.format("%.4f %.4f %.4f", v.x, v.y, v.z) or "nil" end

local hand = { x = 1, y = 1.2, z = -0.5 }
local turn = Quat.from_rotation_y(0.4)

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end

step(function(world)
    local me = carrier(world, "me")
    return me ~= nil and me:has("vr/pointer/ray") and #lasers(world, me) == 1
end, function(world, commands)
    local me = carrier(world, "me")
    local ui = me:get("input/ui")
    T("VP1_the_pointer_binds_press_and_scroll",
        ui.vr_pointer ~= nil and ui.vr_pointer.press.button == "Left" and ui.vr_pointer.scroll.scroll == true, "")
    T("VP1_the_grip_binds_grab", ui.vr_grabbable ~= nil and ui.vr_grabbable.grab.key == "KeyG", "")
    local ray = me:get("vr/pointer/ray")
    T("VP2_the_ray_starts_at_the_hand", close(ray.origin, hand), show(ray.origin))
    -- -60 degrees of pitch, then -10 of yaw, worked by hand from -Z in the hand's frame
    local tilted = Quat.mul_vec3(turn, { x = 0.5 * math.sin(math.rad(10)), y = -math.sin(math.rad(60)), z = -0.5 * math.cos(math.rad(10)) })
    T("VP2_turned_in_the_hands_own_frame", close(ray.direction, tilted), show(ray.direction) .. " against " .. show(tilted))
    local laser = lasers(world, me)
    T("VP4_one_laser_a_child_hidden_while_nothing_is_hovered", #laser == 1 and laser[1]:get("Visibility") == "Hidden",
        tostring(#laser) .. " " .. tostring(laser[1] and laser[1]:get("Visibility")))
    local copy = me:get("vr/pointer")
    copy.pitch, copy.yaw = 0, 0
    commands:entity(me:id()):insert({ ["vr/pointer"] = copy })
end)
step(after(0.3), function(world)
    local ray = carrier(world, "me"):get("vr/pointer/ray")
    local forward = Quat.mul_vec3(turn, { x = 0, y = 0, z = -1 })
    T("VP3_no_turn_is_the_hands_forward", close(ray.direction, forward), show(ray.direction))
    write_file_bytes("assets/modules/vr/pointer/init.lua", read_file_bytes("assets/modules/vr/pointer/init.lua"))
end)
step(after(1.0), function(world)
    hand = { x = 3, y = 1.2, z = -0.5 }
end)
step(after(0.3), function(world, commands)
    local me = carrier(world, "me")
    T("VP5_after_a_reload_one_laser", #lasers(world, me) == 1, tostring(#lasers(world, me)))
    local ui = me:get("input/ui")
    T("VP5_the_bindings_stay", ui.vr_pointer ~= nil and ui.vr_grabbable ~= nil, "")
    T("VP5_the_ray_still_follows_the_hand", close(me:get("vr/pointer/ray").origin, hand), show(me:get("vr/pointer/ray").origin))
    commands:entity(me:id()):remove("vr/pointer", "vr/grabbable")
    commands:entity(carrier(world, "together"):id()):remove("vr/pointer", "vr/grabbable", "input", "input/ui")
end)
step(after(0.5), function(world)
    local me = carrier(world, "me")
    local ui = me:get("input/ui") or {}
    T("VP6_removal_takes_the_bindings", ui.vr_pointer == nil and ui.vr_grabbable == nil, "")
    T("VP6_the_ray", not me:has("vr/pointer/ray"), "")
    T("VP6_and_the_laser", #world:query({ with = { "vr/pointer/laser" } }) == 0, tostring(#world:query({ with = { "vr/pointer/laser" } })))
    T("VP6_removed_with_input_no_binding_comes_back", not carrier(world, "together"):has("input/ui"), "")
end)

local done = false
app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter[VrPoseInput],
}, function(world, commands, write_pose)
    t = t + world:delta_time()
    write_pose:write({
        hmd_position = { x = hand.x, y = 1.6, z = hand.z + 0.4 },
        hmd_rotation = { x = 0, y = 0, z = 0, w = 1 },
        hmd_forward = { x = 0, y = 0, z = -1 },
        right_position = hand,
        right_rotation = turn,
        right_forward = Quat.mul_vec3(turn, { x = 0, y = 0, z = -1 }),
    })
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("VrPointerSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 15 then
        T("VP0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("VrPointerSuite")
    end
end):in_set("zz/vr_pointer_drive")
