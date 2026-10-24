-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("Camera2dSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local QUARTER_Z = { x = 0, y = 0, z = 0.70710678, w = 0.70710678 }

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "camera", "camera/2d", "camera/third_person", "input/game" },
    })) do
        if e:get("zz/carrier").name == name then
            return e
        end
    end
end

local function eyes_of(world, e)
    return world:query({
        entities = { e:id() },
        with = { "camera/2d/eye", "Camera" },
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

-- The eye's world transform: `z` above the carrier, level, scaled by `scale`.
local function placed(world, eye_id, at, z, scale)
    local t = world:get_entity(eye_id).GlobalTransform:compute_transform()
    local ok = near(t.translation.x, at.x) and near(t.translation.y, at.y) and near(t.translation.z, at.z + z)
        and near(t.rotation.z, 0) and near(t.rotation.w, 1)
        and near(t.scale.x, scale) and near(t.scale.y, scale)
    return ok, string.format("at %.2f %.2f %.2f rotation z=%.3f scale %.3f",
        t.translation.x, t.translation.y, t.translation.z, t.rotation.z, t.scale.x)
end

local AT = { x = 2, y = 3, z = 0 }
local phase, clock = "spawn", 0
local first_eye, nearest, zoomed_exact, exact

-- A zoom injected before Update must scale the eye in the same frame: read after
-- transforms propagate, in Last.
app:add_systems(PreUpdate, { World }, function(world)
    if phase == "exact" and not zoomed_exact then
        zoomed_exact = true
        carrier(world, "me"):patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = -5 } })
    end
end):in_set("zz/camera2d_suite_zoom")

app:add_systems(Last, { World }, function(world)
    if zoomed_exact and exact == nil then
        local me = carrier(world, "me")
        local ok, got = placed(world, eyes_of(world, me)[1]:id(), AT, 500, 1.5)
        exact = { ok = ok and near(me:get("camera").distance, 1.5), got = got }
    end
end):in_set("zz/camera2d_suite_exact")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local me, other = carrier(world, "me"), carrier(world, "other")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        -- `input` with no mode: no binding is active, so a mouse moved or scrolled while the test
        -- window has focus does not move the camera. The suite writes the zoom itself; the camera
        -- mods bind into `input/game` whatever the mode.
        commands:spawn({
            ["zz/carrier"] = { name = "me" },
            ["core/net/local"] = {},
            input = {},
            ["core/net/sync"] = false,
            Transform = { translation = AT },
            camera = { distance = 1 },
            ["camera/2d"] = {},
        })
        commands:spawn({
            ["zz/carrier"] = { name = "other" },
            ["core/net/sync"] = false,
            Transform = {},
            ["camera/2d"] = {},
        })
        step("spawned")

    elseif phase == "spawned" and me and #eyes_of(world, me) > 0 and followed(eyes_of(world, me)[1]) and clock > 0.3 then
        local c2d = me:get("camera/2d")
        local bindings = (me:get("input/game") or {}).camera_2d
        suite.assert_test("C1_the_local_carrier_gets_a_zoom_binding_and_default_config",
            bindings ~= nil and bindings.zoom.scroll == true
                and c2d.zoom_step == 0.1 and c2d.min_distance == 0.25
                and c2d.max_distance == 4 and c2d.z == 1000, "")
        suite.assert_test("C2_a_remote_carrier_gets_no_eye_and_no_binding",
            #eyes_of(world, other) == 0 and (other:get("input/game") or {}).camera_2d == nil, "")
        first_eye = eyes_of(world, me)[1]:id()
        local ok, got = placed(world, first_eye, AT, 1000, 1)
        suite.assert_test("C3_one_eye_sits_above_the_carrier_at_1_to_1",
            #eyes_of(world, me) == 1 and ok, got)
        me:patch({ Transform = { rotation = QUARTER_Z } })
        step("turned")

    elseif phase == "turned" and clock > 0.3 then
        local ok, got = placed(world, first_eye, AT, 1000, 1)
        suite.assert_test("C4_turning_the_carrier_does_not_turn_the_eye", ok, got)
        me:patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = -5 } })
        step("zoomed")

    elseif phase == "zoomed" and clock > 0.3 then
        local ok, got = placed(world, first_eye, AT, 1000, 1.5)
        suite.assert_test("C5_scrolling_changes_distance_by_zoom_step_and_scales_the_eye",
            near(me:get("camera").distance, 1.5) and ok, got)
        me:patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = 100 } })
        step("zoomed in")

    elseif phase == "zoomed in" and clock > 0.3 then
        nearest = me:get("camera").distance
        me:patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = -100 } })
        step("zoomed out")

    elseif phase == "zoomed out" and clock > 0.3 then
        local farthest = me:get("camera").distance
        suite.assert_test("C6_distance_clamps_to_min_and_max", near(nearest, 0.25) and near(farthest, 4),
            string.format("nearest=%s farthest=%s", tostring(nearest), tostring(farthest)))
        me:patch({ camera = { distance = 1 } })
        step("reset")

    elseif phase == "reset" and clock > 0.3 then
        me:patch({ ["core/net/local"] = null })
        step("away")

    elseif phase == "away" and clock > 0.2 then
        local eyes = eyes_of(world, me)
        suite.assert_test("C7_leaving_the_world_turns_the_eye_off",
            #eyes == 1 and eyes[1]:get("Camera").is_active == false, "eyes=" .. #eyes)
        me:patch({ ["core/net/local"] = {} })
        step("back")

    elseif phase == "back" and clock > 0.2 then
        local eyes = eyes_of(world, me)
        suite.assert_test("C8_coming_back_turns_the_same_eye_on",
            #eyes == 1 and eyes[1]:id() == first_eye and eyes[1]:get("Camera").is_active == true,
            "eyes=" .. #eyes)
        me:patch({ ["camera/2d"] = { z = 500 } })
        step("raised")

    elseif phase == "raised" and clock > 0.3 then
        local ok, got = placed(world, first_eye, AT, 500, 1)
        suite.assert_test("C9_changing_z_moves_the_eye", ok, got)
        other:patch({ camera = { distance = 3 } })
        step("other zoomed")

    elseif phase == "other zoomed" and clock > 0.3 then
        other:patch({ ["core/net/local"] = {}, input = {} })
        step("other local")

    elseif phase == "other local" and #eyes_of(world, other) > 0 and clock > 0.3 then
        local ok, got = placed(world, eyes_of(world, other)[1]:id(), { x = 0, y = 0, z = 0 }, 1000, 3)
        suite.assert_test("C10_a_carrier_that_becomes_local_gets_an_eye_already_placed", ok, got)
        step("exact")

    elseif phase == "exact" and exact ~= nil then
        suite.assert_test("C11_a_zoom_scales_the_eye_in_the_same_frame", exact.ok, exact.got)
        me:patch({ ["camera/third_person"] = {} })
        step("switched")

    elseif phase == "switched" and clock > 0.5 then
        local bindings = me:get("input/game") or {}
        local eyes_3d = world:query({ entities = { me:id() }, with = { "camera/3d/eye", "Camera" } })
        suite.assert_test("C12_switching_to_third_person_removes_the_2d_camera_eye_and_binding",
            me:get("camera/2d") == nil and #eyes_of(world, me) == 0 and bindings.camera_2d == nil
                and #eyes_3d == 1, "3d eyes=" .. #eyes_3d)
        commands:spawn({
            ["zz/carrier"] = { name = "late" },
            ["core/net/local"] = {},
            input = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = -5, y = 0, z = 0 } },
            camera = { yaw = 0, pitch = 0, distance = 16, height = 0, offset = { x = 0, y = 0, z = 0 } },
        })
        commands:spawn({
            ["zz/carrier"] = { name = "plain" },
            ["core/net/local"] = {},
            input = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = 0, y = 7, z = 0 } },
            camera = { yaw = 0, pitch = 0, distance = 16, height = 0, offset = { x = 0, y = 0, z = 0 } },
        })
        step("late camera")

    elseif phase == "late camera" and clock > 0.5 then
        carrier(world, "late"):patch({
            ["camera/2d"] = { z = 50, zoom_step = 2, min_distance = 10, max_distance = 18 },
        })
        carrier(world, "plain"):patch({ ["camera/2d"] = {} })
        step("late added")

    elseif phase == "late added" and #eyes_of(world, carrier(world, "late")) > 0 and clock > 0.5 then
        local late = carrier(world, "late")
        local ok, got = placed(world, eyes_of(world, late)[1]:id(), { x = -5, y = 0, z = 0 }, 50, 16)
        suite.assert_test("C13_a_camera_already_on_the_carrier_sets_the_scale_and_config_sets_z", ok, got)
        local plain = carrier(world, "plain")
        local plain_eyes = eyes_of(world, plain)
        local plain_ok, plain_got = false, "no eye"
        if #plain_eyes == 1 then
            plain_ok, plain_got = placed(world, plain_eyes[1]:id(), { x = 0, y = 7, z = 0 }, 1000, 16)
        end
        suite.assert_test("C16_a_camera_already_on_the_carrier_gets_the_default_config", plain_ok, plain_got)
        late:patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = -1 } })
        step("late zoomed")

    elseif phase == "late zoomed" and clock > 0.3 then
        local late = carrier(world, "late")
        nearest = late:get("camera").distance
        late:patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = 100 } })
        step("late zoomed in")

    elseif phase == "late zoomed in" and clock > 0.3 then
        local late = carrier(world, "late")
        local d = late:get("camera").distance
        late:patch({ ["input/game/camera_2d/zoom"] = { dx = 0, dy = -100 } })
        nearest = { nearest, d }
        step("late zoomed out")

    elseif phase == "late zoomed out" and clock > 0.3 then
        local late = carrier(world, "late")
        local d = late:get("camera").distance
        suite.assert_test("C14_config_sets_zoom_step_and_distance_limits",
            near(nearest[1], 18) and near(nearest[2], 10) and near(d, 18),
            string.format("step=%s min=%s max=%s", tostring(nearest[1]), tostring(nearest[2]), tostring(d)))
        late:remove("camera/2d")
        step("removed")

    elseif phase == "removed" and clock > 0.5 then
        local late = carrier(world, "late")
        suite.assert_test("C15_removal_despawns_the_eye_and_unbinds",
            #eyes_of(world, late) == 0 and ((late:get("input/game") or {}).camera_2d == nil), "")
        carrier(world, "other"):remove("input")
        step("no input")

    -- `input` taken off and added again: the bindings go with it and come back (on "other",
    -- which still carries camera/2d; "me" moved on to third person).
    elseif phase == "no input" and clock > 0.3 then
        local who = carrier(world, "other")
        suite.assert_test("C16a_removing_input_takes_the_bindings", (world:get_entity(who:id()):get("input/game") or {}).camera_2d == nil, "")
        who:patch({ input = {} })
        step("input back")

    elseif phase == "input back" and clock > 0.3 then
        local who = carrier(world, "other")
        suite.assert_test("C16b_input_added_again_binds_again", (world:get_entity(who:id()):get("input/game") or {}).camera_2d ~= nil, "")
        phase = "done"
        suite.finish("Camera2dSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("Camera2dSuite")
    end
end):in_set("zz/camera2d_suite")
