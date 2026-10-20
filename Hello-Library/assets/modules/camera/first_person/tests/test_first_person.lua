-- --host
local Quat = require("bevy::math::Quat")

require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("FirstPersonSuite")

spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })

local QUARTER = { x = 0, y = 0.70710678, z = 0, w = 0.70710678 }

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "camera", "camera/first_person", "input/game", "core/net/local" },
    })) do
        if e:get("zz/carrier").name == name then
            return e
        end
    end
end

local function eye_of(world, e)
    for _, eye in ipairs(world:query({
        entities = { e:id() },
        with = { "camera/3d/eye", "Camera" },
    })) do
        return eye
    end
end

local function near(a, b) return math.abs(a - b) < 1e-3 end

local phase, clock = "spawn", 0
local first_eye, yaw_before, looked_exact, exact

-- A look injected before Update must turn the eye in the same frame: read after
-- transforms propagate, in Last.
register_system("PreUpdate", function(world)
    if phase == "exact" and not looked_exact then
        looked_exact = true
        carrier(world, "me"):patch({ ["input/game/first_person/look"] = { dx = 30, dy = 0 } })
    end
end, { label = "FirstPersonSuiteLook" })

register_system("Last", function(world)
    if looked_exact and exact == nil then
        local me = carrier(world, "me")
        local cam = me:get("camera")
        local t = world:call_component_method(eye_of(world, me):id(), "GlobalTransform", "compute_transform")
        local want = Quat.mul_quat(Quat.from_rotation_y(cam.yaw),
            Quat.from_rotation_x(cam.pitch))
        exact = {
            ok = near(cam.yaw, yaw_before - 1.3) and near(t.rotation.y, want.y) and near(t.rotation.w, want.w),
            got = string.format("yaw=%s eye y=%.3f want %.3f", tostring(cam.yaw), t.rotation.y, want.y),
        }
    end
end, { label = "FirstPersonSuiteExact" })

register_system("Update", function(world)
    clock = clock + (world:delta_time() or 0)
    local me, other = carrier(world, "me"), carrier(world, "other")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        spawn({
            ["zz/carrier"] = { name = "me" },
            ["core/net/local"] = {},
            input = { mode = "input/game" },
            ["core/net/sync"] = false,
            Transform = { translation = { x = 2, y = 0, z = 3 } },
            ["camera/first_person"] = {},
        })
        spawn({
            ["zz/carrier"] = { name = "other" },
            ["core/net/sync"] = false,
            Transform = {},
            ["camera/first_person"] = {},
        })
        step("spawned")

    elseif phase == "spawned" and me and eye_of(world, me) and clock > 0.3 then
        local eye = eye_of(world, me)
        local bindings = me:get("input/game") or {}
        local fp = me:get("camera/first_person")
        suite.assert_test("F1_the_local_carrier_gets_an_eye_a_look_binding_and_default_config",
            bindings.first_person ~= nil and bindings.first_person.look.motion == true
                and fp.sensitivity == 0.0025 and fp.pitch_limit == 1.4, "")
        suite.assert_test("F2_a_remote_carrier_gets_no_eye_and_no_binding",
            eye_of(world, other) == nil and (other:get("input/game") or {}).first_person == nil, "")
        local t = world:call_component_method(eye:id(), "GlobalTransform", "compute_transform")
        suite.assert_test("F3_the_eye_sits_at_the_head",
            near(t.translation.x, 2) and near(t.translation.y, 1.5) and near(t.translation.z, 3),
            string.format("at %.2f %.2f %.2f", t.translation.x, t.translation.y, t.translation.z))
        first_eye = eye:id()
        me:patch({ Transform = { rotation = QUARTER } })
        step("body turned")

    elseif phase == "body turned" and clock > 0.3 then
        local t = world:call_component_method(first_eye, "GlobalTransform", "compute_transform")
        local want = Quat.from_rotation_x(me:get("camera").pitch)
        suite.assert_test("F4_turning_the_body_does_not_turn_the_eye",
            near(t.rotation.x, want.x) and near(t.rotation.y, 0) and near(t.rotation.w, want.w)
                and near(t.translation.x, 2) and near(t.translation.z, 3),
            string.format("rotation y=%.3f w=%.3f at %.2f %.2f", t.rotation.y, t.rotation.w, t.translation.x, t.translation.z))
        me:patch({ ["input/game/first_person/look"] = { dx = 100, dy = 2000 } })
        step("looked")

    elseif phase == "looked" and clock > 0.3 then
        local cam = me:get("camera")
        local t = world:call_component_method(first_eye, "GlobalTransform", "compute_transform")
        local want_y = Quat.from_rotation_y(-0.25)
        local want = Quat.mul_quat(want_y,
            Quat.from_rotation_x(-1.4))
        suite.assert_test("F5_mouse_motion_turns_the_eye_and_clamps_pitch",
            near(cam.yaw, -0.25) and near(cam.pitch, -1.4)
                and near(t.rotation.x, want.x) and near(t.rotation.y, want.y) and near(t.rotation.w, want.w),
            string.format("yaw=%s pitch=%s", tostring(cam.yaw), tostring(cam.pitch)))
        me:patch({ ["core/net/local"] = null })
        step("away")

    elseif phase == "away" and clock > 0.2 then
        local eye = eye_of(world, me)
        suite.assert_test("F6_leaving_the_world_turns_the_eye_off",
            eye ~= nil and eye:get("Camera").is_active == false, "")
        me:patch({ ["core/net/local"] = {} })
        step("back")

    elseif phase == "back" and clock > 0.2 then
        local eye = eye_of(world, me)
        local eyes = #world:query({ entities = { me:id() }, with = { "camera/3d/eye" } })
        suite.assert_test("F7_coming_back_turns_the_same_eye_on",
            eyes == 1 and eye:id() == first_eye and eye:get("Camera").is_active == true, "eyes=" .. eyes)
        me:remove("camera/first_person")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local bindings = me:get("input/game") or {}
        suite.assert_test("F8_removal_despawns_the_eye_and_unbinds",
            eye_of(world, me) == nil and bindings.first_person == nil, "")
        me:patch({
            Transform = { translation = { x = 7, y = 0, z = 0 } },
            ["camera/first_person"] = { sensitivity = 0.01, pitch_limit = 0.5 },
        })
        step("readded")

    elseif phase == "readded" and eye_of(world, me) and clock > 0.3 then
        local t = world:call_component_method(eye_of(world, me):id(), "GlobalTransform", "compute_transform")
        suite.assert_test("F9_a_readded_camera_starts_at_the_head_without_a_look",
            near(t.translation.x, 7) and near(t.translation.y, 1.5) and near(t.rotation.y, 0),
            string.format("at %.2f %.2f", t.translation.x, t.translation.y))
        yaw_before = me:get("camera").yaw
        me:patch({ ["input/game/first_person/look"] = { dx = 100, dy = 2000 } })
        step("custom")

    elseif phase == "custom" and clock > 0.3 then
        local cam = me:get("camera")
        suite.assert_test("F10_config_sets_sensitivity_and_pitch_limit",
            near(cam.yaw, yaw_before - 1.0) and near(cam.pitch, -0.5),
            string.format("yaw=%s pitch=%s", tostring(cam.yaw), tostring(cam.pitch)))
        step("exact")

    elseif phase == "exact" and exact ~= nil then
        suite.assert_test("F11_a_look_turns_the_eye_in_the_same_frame", exact.ok, exact.got)
        spawn({
            ["zz/carrier"] = { name = "late" },
            ["core/net/local"] = {},
            input = { mode = "input/game" },
            ["core/net/sync"] = false,
            Transform = { translation = { x = -5, y = 0, z = 0 } },
            camera = { yaw = 0, pitch = 0, distance = 8, height = 2.5, offset = { x = 0, y = 0, z = 0 } },
        })
        step("late camera")

    elseif phase == "late camera" and clock > 0.5 then
        carrier(world, "late"):patch({ ["camera/first_person"] = {} })
        step("late added")

    elseif phase == "late added" and eye_of(world, carrier(world, "late")) and clock > 0.5 then
        local t = world:call_component_method(eye_of(world, carrier(world, "late")):id(),
            "GlobalTransform", "compute_transform")
        suite.assert_test("F12_a_camera_already_on_the_carrier_puts_the_eye_at_its_height",
            near(t.translation.x, -5) and near(t.translation.y, 2.5),
            string.format("at %.2f %.2f", t.translation.x, t.translation.y))
        carrier(world, "me"):remove("input")
        step("no input")

    -- `input` taken off and added again: the bindings go with it and come back.
    elseif phase == "no input" and clock > 0.3 then
        local who = carrier(world, "me")
        suite.assert_test("F13a_removing_input_takes_the_bindings", (world:get_entity(who:id()):get("input/game") or {}).first_person == nil, "")
        who:patch({ input = { mode = "input/game" } })
        step("input back")

    elseif phase == "input back" and clock > 0.3 then
        local who = carrier(world, "me")
        suite.assert_test("F13b_input_added_again_binds_again", (world:get_entity(who:id()):get("input/game") or {}).first_person ~= nil, "")
        phase = "done"
        suite.finish("FirstPersonSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("F0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("FirstPersonSuite")
    end
end, { label = "FirstPersonSuite" })
