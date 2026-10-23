-- --host
local Quat = require("bevy::math::Quat")

local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ThirdPersonSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "camera", "camera/third_person", "camera/first_person", "input/game" },
    })) do
        if e:get("zz/carrier").name == name then
            return e
        end
    end
end

local function eyes_of(world, e)
    return world:query({
        entities = { e:id() },
        with = { "camera/3d/eye", "Camera" },
        optional = { "Transform" },
    })
end

-- An eye is spawned with an identity Transform; `transform/follow` has placed it once it is not.
-- That mod loads when the first eye appears, and its first run can come frames after its load.
local function followed(eye)
    local t = eye:get("Transform").translation
    return not (t.x == 0 and t.y == 0 and t.z == 0)
end

local function near(a, b) return math.abs(a - b) < 1e-3 end

-- Where the orbit puts the eye, worked out independently: rotate (0, 0, distance) by
-- pitch then yaw, raise it by height, and add the shoulder offset turned by yaw.
local function orbit(at, cam)
    local back = { y = -cam.distance * math.sin(cam.pitch), z = cam.distance * math.cos(cam.pitch) }
    local c, s = math.cos(cam.yaw), math.sin(cam.yaw)
    return {
        x = at.x + back.z * s + cam.offset.x * c + cam.offset.z * s,
        y = at.y + cam.height + back.y + cam.offset.y,
        z = at.z + back.z * c - cam.offset.x * s + cam.offset.z * c,
    }
end

local function placed(world, eye_id, at, cam)
    local t = world:get_entity(eye_id).GlobalTransform:compute_transform()
    local want = orbit(at, cam)
    local turn = Quat.mul_quat(Quat.from_rotation_y(cam.yaw),
        Quat.from_rotation_x(cam.pitch))
    local ok = near(t.translation.x, want.x) and near(t.translation.y, want.y) and near(t.translation.z, want.z)
        and near(t.rotation.x, turn.x) and near(t.rotation.y, turn.y)
        and near(t.rotation.z, turn.z) and near(t.rotation.w, turn.w)
    return ok, string.format("at %.2f %.2f %.2f, want %.2f %.2f %.2f",
        t.translation.x, t.translation.y, t.translation.z, want.x, want.y, want.z)
end

local AT = { x = 2, y = 0, z = 3 }
local phase, clock = "spawn", 0
local first_eye, nearest, looked_exact, exact, custom, custom_ok, yaw_before

local function eye_of_late(world)
    local late = carrier(world, "late")
    return late and eyes_of(world, late)[1]
end

-- A look and a zoom injected before Update must move the eye in the same frame: read
-- after transforms propagate, in Last.
app:add_systems(PreUpdate, { World }, function(world)
    if phase == "exact" and not looked_exact then
        looked_exact = true
        yaw_before = carrier(world, "me"):get("camera").yaw
        carrier(world, "me"):patch({
            ["input/game/third_person/look"] = { dx = 30, dy = 0 },
            ["input/game/third_person/zoom"] = { dx = 0, dy = 1 },
        })
    end
end):in_set("zz/third_person_suite_look")

app:add_systems(Last, { World }, function(world)
    if looked_exact and exact == nil then
        local me = carrier(world, "me")
        local cam = me:get("camera")
        local ok, got = placed(world, eyes_of(world, me)[1]:id(), AT, cam)
        exact = {
            ok = ok and near(cam.distance, 7) and near(cam.yaw, yaw_before - 0.3),
            got = string.format("distance=%s yaw=%s %s", tostring(cam.distance), tostring(cam.yaw), got),
        }
    end
end):in_set("zz/third_person_suite_exact")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local me, other = carrier(world, "me"), carrier(world, "other")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        -- `input` with no mode: no binding is active, so a mouse moved while the test window has
        -- focus does not turn or zoom the camera. The suite writes the look and the zoom itself;
        -- the camera mod binds into `input/game` whatever the mode.
        commands:spawn({
            ["zz/carrier"] = { name = "me" },
            ["core/net/local"] = {},
            input = {},
            ["core/net/sync"] = false,
            Transform = { translation = AT },
            ["camera/third_person"] = {},
        })
        commands:spawn({
            ["zz/carrier"] = { name = "other" },
            ["core/net/sync"] = false,
            Transform = {},
            ["camera/third_person"] = {},
        })
        -- keeps camera/first_person loaded, so switching to it is not its first run
        commands:spawn({
            ["zz/carrier"] = { name = "bystander" },
            ["core/net/sync"] = false,
            Transform = {},
            ["camera/first_person"] = {},
        })
        step("spawned")

    elseif phase == "spawned" and me and #eyes_of(world, me) > 0 and followed(eyes_of(world, me)[1]) and clock > 0.3 then
        local bindings = (me:get("input/game") or {}).third_person
        local tp = me:get("camera/third_person")
        suite.assert_test("T1_the_local_carrier_gets_look_and_zoom_bindings_and_default_config",
            bindings ~= nil and bindings.look.motion == true and bindings.zoom.scroll == true
                and tp.sensitivity == 0.003 and tp.min_pitch == -1.2 and tp.max_pitch == 0.2
                and tp.zoom_step == 0.5 and tp.min_distance == 2 and tp.max_distance == 20, "")
        suite.assert_test("T2_a_remote_carrier_gets_no_eye_and_no_binding",
            #eyes_of(world, other) == 0 and (other:get("input/game") or {}).third_person == nil, "")
        first_eye = eyes_of(world, me)[1]:id()
        local ok, got = placed(world, first_eye, AT, me:get("camera"))
        suite.assert_test("T3_the_eye_orbits_behind_the_carrier_looking_at_it", ok, got)
        me:patch({ ["input/game/third_person/look"] = { dx = -300, dy = -200 } })
        step("looked")

    elseif phase == "looked" and clock > 0.3 then
        local cam = me:get("camera")
        local ok, got = placed(world, first_eye, AT, cam)
        suite.assert_test("T4_mouse_motion_turns_the_orbit_and_clamps_to_max_pitch",
            near(cam.yaw, 0.9) and near(cam.pitch, 0.2) and ok,
            string.format("yaw=%s pitch=%s %s", tostring(cam.yaw), tostring(cam.pitch), got))
        me:patch({ ["input/game/third_person/look"] = { dx = 0, dy = 1000 } })
        step("looked down")

    elseif phase == "looked down" and clock > 0.3 then
        local cam = me:get("camera")
        suite.assert_test("T5_pitch_clamps_to_min_pitch", near(cam.pitch, -1.2), "pitch=" .. tostring(cam.pitch))
        me:patch({ ["input/game/third_person/zoom"] = { dx = 0, dy = 3 } })
        step("zoomed")

    elseif phase == "zoomed" and clock > 0.3 then
        local cam = me:get("camera")
        local ok, got = placed(world, first_eye, AT, cam)
        suite.assert_test("T6_scrolling_zooms_by_zoom_step_and_moves_the_eye", near(cam.distance, 6.5) and ok,
            "distance=" .. tostring(cam.distance) .. " " .. got)
        me:patch({ ["input/game/third_person/zoom"] = { dx = 0, dy = 100 } })
        step("zoomed in")

    elseif phase == "zoomed in" and clock > 0.3 then
        nearest = me:get("camera").distance
        me:patch({ ["input/game/third_person/zoom"] = { dx = 0, dy = -100 } })
        step("zoomed out")

    elseif phase == "zoomed out" and clock > 0.3 then
        local farthest = me:get("camera").distance
        suite.assert_test("T7_distance_clamps_to_min_and_max", near(nearest, 2) and near(farthest, 20),
            string.format("nearest=%s farthest=%s", tostring(nearest), tostring(farthest)))
        me:patch({ ["camera/first_person"] = {} })
        step("switched")

    elseif phase == "switched" and clock > 0.5 then
        local eyes = eyes_of(world, me)
        local t = #eyes == 1 and world:get_entity(eyes[1]:id()).GlobalTransform:compute_transform()
        local bindings = me:get("input/game") or {}
        suite.assert_test("T8_switching_to_first_person_keeps_the_eye_and_moves_it_to_the_head",
            #eyes == 1 and eyes[1]:id() == first_eye and me:get("camera/third_person") == nil
                and bindings.third_person == nil and bindings.first_person ~= nil
                and near(t.translation.x, AT.x) and near(t.translation.y, 1.5) and near(t.translation.z, AT.z),
            "eyes=" .. #eyes)
        me:patch({ ["camera/third_person"] = {} })
        step("switched back")

    elseif phase == "switched back" and clock > 0.5 then
        local eyes = eyes_of(world, me)
        local ok, got = false, "eyes=" .. #eyes
        if #eyes == 1 then ok, got = placed(world, eyes[1]:id(), AT, me:get("camera")) end
        local bindings = me:get("input/game") or {}
        suite.assert_test("T9_switching_back_keeps_the_eye_and_returns_it_to_the_orbit",
            ok and eyes[1]:id() == first_eye and me:get("camera/first_person") == nil
                and bindings.first_person == nil and bindings.third_person ~= nil, got)
        me:remove("camera/third_person")
        step("removed")

    elseif phase == "removed" and clock > 0.5 then
        local bindings = me:get("input/game") or {}
        suite.assert_test("T10_removing_the_camera_mod_despawns_the_eye_and_unbinds",
            #eyes_of(world, me) == 0 and bindings.third_person == nil, "")
        me:patch({ ["camera/third_person"] = {
            sensitivity = 0.01, min_pitch = -0.6, max_pitch = 0.5,
            zoom_step = 2, min_distance = 5, max_distance = 9,
        } })
        step("readded")

    elseif phase == "readded" and #eyes_of(world, me) > 0 and clock > 0.3 then
        me:patch({
            ["input/game/third_person/look"] = { dx = 0, dy = -100 },
            ["input/game/third_person/zoom"] = { dx = 0, dy = 1 },
        })
        step("custom")

    elseif phase == "custom" and clock > 0.3 then
        local cam = me:get("camera")
        custom = string.format("pitch=%s distance=%s", tostring(cam.pitch), tostring(cam.distance))
        custom_ok = near(cam.pitch, 0.5) and near(cam.distance, 6)
        me:patch({
            ["input/game/third_person/look"] = { dx = 0, dy = 1000 },
            ["input/game/third_person/zoom"] = { dx = 0, dy = 10 },
        })
        step("custom low")

    elseif phase == "custom low" and clock > 0.3 then
        local cam = me:get("camera")
        custom = custom .. string.format(", low pitch=%s distance=%s", tostring(cam.pitch), tostring(cam.distance))
        custom_ok = custom_ok and near(cam.pitch, -0.6) and near(cam.distance, 5)
        me:patch({ ["input/game/third_person/zoom"] = { dx = 0, dy = -10 } })
        step("custom high")

    elseif phase == "custom high" and clock > 0.3 then
        local cam = me:get("camera")
        suite.assert_test("T11_config_sets_sensitivity_pitch_limits_zoom_step_and_distance_limits",
            custom_ok and near(cam.distance, 9), custom .. ", high distance=" .. tostring(cam.distance))
        step("exact")

    elseif phase == "exact" and exact ~= nil then
        suite.assert_test("T12_look_and_zoom_move_the_eye_in_the_same_frame", exact.ok, exact.got)
        commands:spawn({
            ["zz/carrier"] = { name = "late" },
            ["core/net/local"] = {},
            input = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = -5, y = 0, z = 0 } },
            camera = { yaw = 0.4, pitch = -0.5, distance = 4, height = 2.5, offset = { x = 0.5, y = 0, z = 0 } },
        })
        step("late camera")

    elseif phase == "late camera" and clock > 0.5 then
        carrier(world, "late"):patch({ ["camera/third_person"] = {} })
        step("late added")

    elseif phase == "late added" and eye_of_late(world) and clock > 0.5 then
        local late = carrier(world, "late")
        local ok, got = placed(world, eye_of_late(world):id(), { x = -5, y = 0, z = 0 }, late:get("camera"))
        suite.assert_test("T13_a_camera_already_on_the_carrier_puts_the_eye_on_its_orbit", ok, got)
        carrier(world, "me"):remove("input")
        step("no input")

    -- `input` taken off and added again: the bindings go with it and come back.
    elseif phase == "no input" and clock > 0.3 then
        local who = carrier(world, "me")
        suite.assert_test("T14a_removing_input_takes_the_bindings", (world:get_entity(who:id()):get("input/game") or {}).third_person == nil, "")
        who:patch({ input = {} })
        step("input back")

    elseif phase == "input back" and clock > 0.3 then
        local who = carrier(world, "me")
        suite.assert_test("T14b_input_added_again_binds_again", (world:get_entity(who:id()):get("input/game") or {}).third_person ~= nil, "")
        phase = "done"
        suite.finish("ThirdPersonSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("T0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ThirdPersonSuite")
    end
end):in_set("zz/third_person_suite")
