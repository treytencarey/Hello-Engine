-- --host
local Quat = require("bevy::math::Quat")

require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("Camera3dSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local QUARTER = { x = 0, y = 0.70710678, z = 0, w = 0.70710678 }

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "camera", "camera/3d", "core/net/local" },
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

-- The eye's world transform, against yaw, pitch and the carrier's position plus offset.
local function placed(world, eye_id, at, yaw, pitch)
    local t = world:get_entity(eye_id).GlobalTransform:compute_transform()
    local want = Quat.mul_quat(Quat.from_rotation_y(yaw),
        Quat.from_rotation_x(pitch))
    local ok = near(t.translation.x, at.x) and near(t.translation.y, at.y) and near(t.translation.z, at.z)
        and near(t.rotation.x, want.x) and near(t.rotation.y, want.y)
        and near(t.rotation.z, want.z) and near(t.rotation.w, want.w)
    return ok, string.format("at %.2f %.2f %.2f rotation %.3f %.3f %.3f %.3f",
        t.translation.x, t.translation.y, t.translation.z, t.rotation.x, t.rotation.y, t.rotation.z, t.rotation.w)
end

local phase, clock = "spawn", 0
local first_eye

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local me, other = carrier(world, "me"), carrier(world, "other")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            ["zz/carrier"] = { name = "me" },
            ["core/net/local"] = {},
            input = { mode = "input/game" },
            ["core/net/sync"] = false,
            Transform = { translation = { x = 2, y = 0, z = 3 } },
            camera = { yaw = 0.5, pitch = -0.2 },
            ["camera/3d"] = { offset = { x = 1, y = 2, z = 3 } },
        })
        commands:spawn({
            ["zz/carrier"] = { name = "other" },
            ["core/net/sync"] = false,
            Transform = {},
            ["camera/3d"] = {},
        })
        step("spawned")

    elseif phase == "spawned" and me and #eyes_of(world, me) > 0 and followed(eyes_of(world, me)[1]) and clock > 0.3 then
        local eyes = eyes_of(world, me)
        local ok, got = placed(world, eyes[1]:id(), { x = 3, y = 2, z = 6 }, 0.5, -0.2)
        suite.assert_test("D1_the_local_carrier_gets_one_eye_at_the_offset_turned_to_the_camera",
            #eyes == 1 and ok, "eyes=" .. #eyes .. " " .. got)
        suite.assert_test("D2_a_remote_carrier_gets_no_eye", #eyes_of(world, other) == 0, "")
        first_eye = eyes[1]:id()
        me:patch({ Transform = { rotation = QUARTER } })
        step("body turned")

    elseif phase == "body turned" and clock > 0.3 then
        local ok, got = placed(world, first_eye, { x = 3, y = 2, z = 6 }, 0.5, -0.2)
        suite.assert_test("D3_turning_the_body_does_not_turn_or_move_the_eye", ok, got)
        me:patch({ camera = { yaw = -1, pitch = 0.4 } })
        step("turned")

    elseif phase == "turned" and clock > 0.3 then
        local ok, got = placed(world, first_eye, { x = 3, y = 2, z = 6 }, -1, 0.4)
        suite.assert_test("D4_changing_the_camera_turns_the_eye", ok, got)
        me:patch({ ["camera/3d"] = { offset = { x = 0, y = 1, z = -2 } } })
        step("moved")

    elseif phase == "moved" and clock > 0.3 then
        local ok, got = placed(world, first_eye, { x = 2, y = 1, z = 1 }, -1, 0.4)
        suite.assert_test("D5_changing_the_offset_moves_the_eye", ok, got)
        me:patch({ ["core/net/local"] = null })
        step("away")

    elseif phase == "away" and clock > 0.2 then
        local eyes = eyes_of(world, me)
        suite.assert_test("D6_leaving_the_world_turns_the_eye_off",
            #eyes == 1 and eyes[1]:get("Camera").is_active == false, "eyes=" .. #eyes)
        me:patch({ ["core/net/local"] = {} })
        step("back")

    elseif phase == "back" and clock > 0.2 then
        local eyes = eyes_of(world, me)
        suite.assert_test("D7_coming_back_turns_the_same_eye_on",
            #eyes == 1 and eyes[1]:id() == first_eye and eyes[1]:get("Camera").is_active == true,
            "eyes=" .. #eyes)
        other:patch({
            Transform = { translation = { x = -4, y = 0, z = 0 } },
            camera = { yaw = 0.3, pitch = 0.1 },
            ["camera/3d"] = { offset = { x = 0, y = 2, z = 0 } },
        })
        step("other aimed")

    elseif phase == "other aimed" and clock > 0.3 then
        other:patch({ ["core/net/local"] = {}, input = { mode = "input/game" } })
        step("other local")

    elseif phase == "other local" and #eyes_of(world, other) > 0 and clock > 0.3 then
        local ok, got = placed(world, eyes_of(world, other)[1]:id(), { x = -4, y = 2, z = 0 }, 0.3, 0.1)
        suite.assert_test("D8_a_carrier_that_becomes_local_gets_an_eye_already_aimed", ok, got)
        me:remove("camera/3d")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        suite.assert_test("D9_removal_despawns_the_eye", #eyes_of(world, me) == 0
            and #world:query({ entities = { first_eye }, with = { "Camera" } }) == 0, "")
        phase = "done"
        suite.finish("Camera3dSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("D0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("Camera3dSuite")
    end
end):in_set("zz/camera3d_suite")
