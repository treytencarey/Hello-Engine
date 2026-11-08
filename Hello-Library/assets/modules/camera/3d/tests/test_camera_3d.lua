-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("Camera3dSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local QUARTER = { x = 0, y = 0.70710678, z = 0, w = 0.70710678 }

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "camera", "camera/3d", "core/net/local", "camera/3d/viewed_by" },
    })) do
        if e:get("zz/carrier").name == name then
            return e
        end
    end
end

local function eyes_of(world, e)
    return world:query({
        iter_many = world:descendants(e:id()),
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

-- Whether the carrier's engine-kept list names exactly these sources.
local function viewed_by(e, sources)
    local list = e:get("camera/3d/viewed_by")
    if #sources == 0 then return list == nil end
    if type(list) ~= "table" or #list ~= #sources then return false end
    for i, s in ipairs(sources) do
        if list[i] ~= s then return false end
    end
    return true
end

local function view_of(world, source)
    local rows = world:query({ iter_many = { source }, with = { "camera/3d/view_of" } })
    return #rows == 1
end

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
local sources = {}

-- An entity showing the carrier's view instead, as a viewpoint would.
local function source(commands, of)
    return commands:spawn({
        Transform = {},
        ["camera/3d/view_of"] = { entity = of },
        ["core/net/sync"] = false,
    }):id()
end

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local me, other = carrier(world, "me"), carrier(world, "other")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            ["zz/carrier"] = { name = "me" },
            ["core/net/local"] = {},
            input = {},
            ["input/mode"] = { mode = "input/game" },
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
        commands:entity(me:id()):remove("core/net/local")
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
        sources[1] = source(commands, me:id())
        step("viewed")

    elseif phase == "viewed" and clock > 0.3 then
        local eyes = eyes_of(world, me)
        suite.assert_test("C1_a_view_of_the_carrier_leaves_it_no_eye",
            #eyes == 0 and viewed_by(me, { sources[1] }), "eyes=" .. #eyes)
        sources[2] = source(commands, me:id())
        commands:entity(sources[1]):remove("camera/3d/view_of")
        step("one left")

    elseif phase == "one left" and clock > 0.3 then
        local eyes = eyes_of(world, me)
        suite.assert_test("C3_with_two_views_removing_one_keeps_no_eye",
            #eyes == 0 and viewed_by(me, { sources[2] }), "eyes=" .. #eyes)
        commands:entity(sources[2]):remove("camera/3d/view_of")
        step("released")

    elseif phase == "released" and #eyes_of(world, me) > 0 and followed(eyes_of(world, me)[1]) and clock > 0.3 then
        local eyes = eyes_of(world, me)
        local ok, got = placed(world, eyes[1]:id(), { x = 2, y = 1, z = 1 }, -1, 0.4)
        suite.assert_test("C2_removing_the_last_view_spawns_a_new_eye_aimed",
            #eyes == 1 and eyes[1]:id() ~= first_eye and eyes[1]:get("Camera").is_active == true
                and viewed_by(me, {}) and ok,
            "eyes=" .. #eyes .. " " .. got)
        first_eye = eyes[1]:id()
        sources[3] = source(commands, me:id())
        step("viewed again")

    elseif phase == "viewed again" and clock > 0.3 then
        if #eyes_of(world, me) > 0 then
            suite.assert_test("C4_setup_a_view_leaves_no_eye", false, "eyes=" .. #eyes_of(world, me))
        end
        commands:entity(sources[3]):despawn()
        step("source gone")

    elseif phase == "source gone" and clock > 0.3 then
        local eyes = eyes_of(world, me)
        suite.assert_test("C4_despawning_the_view_brings_the_eye_back",
            #eyes == 1 and eyes[1]:id() ~= first_eye and eyes[1]:get("Camera").is_active == true
                and viewed_by(me, {}),
            "eyes=" .. #eyes)
        other:patch({
            Transform = { translation = { x = -4, y = 0, z = 0 } },
            camera = { yaw = 0.3, pitch = 0.1 },
            ["camera/3d"] = { offset = { x = 0, y = 2, z = 0 } },
        })
        step("other aimed")

    elseif phase == "other aimed" and clock > 0.3 then
        other:patch({ ["core/net/local"] = {}, input = {}, ["input/mode"] = { mode = "input/game" } })
        step("other local")

    elseif phase == "other local" and #eyes_of(world, other) > 0 and clock > 0.3 then
        local ok, got = placed(world, eyes_of(world, other)[1]:id(), { x = -4, y = 2, z = 0 }, 0.3, 0.1)
        suite.assert_test("D8_a_carrier_that_becomes_local_gets_an_eye_already_aimed", ok, got)
        sources[4] = source(commands, me:id())
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/camera/3d/client/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s. A reload reaps what the old run spawned, the eyes
    -- included, and the new run spawns them again.
    elseif phase == "reloaded" and clock > 7 then
        local eyes, other_eyes = eyes_of(world, me), eyes_of(world, other)
        suite.assert_test("C5_a_reload_while_viewed_spawns_no_eye",
            #eyes == 0 and viewed_by(me, { sources[4] }) and #other_eyes == 1,
            "eyes=" .. #eyes .. " other eyes=" .. #other_eyes)
        commands:entity(sources[4]):remove("camera/3d/view_of")
        step("reload released")

    elseif phase == "reload released" and #eyes_of(world, me) > 0 and followed(eyes_of(world, me)[1]) and clock > 0.3 then
        local eyes, other_eyes = eyes_of(world, me), eyes_of(world, other)
        local ok, got = false, "no eye"
        if #eyes == 1 then
            first_eye = eyes[1]:id()
            ok, got = placed(world, first_eye, { x = 2, y = 1, z = 1 }, -1, 0.4)
        end
        suite.assert_test("D10_after_a_reload_each_carrier_has_one_eye_on_and_aimed",
            #eyes == 1 and eyes[1]:get("Camera").is_active == true and ok and #other_eyes == 1,
            "eyes=" .. #eyes .. " other eyes=" .. #other_eyes .. " " .. got)
        sources[5] = source(commands, other:id())
        step("other viewed")

    elseif phase == "other viewed" and clock > 0.3 then
        if #eyes_of(world, other) > 0 then
            suite.assert_test("C6_setup_a_view_leaves_no_eye", false, "eyes=" .. #eyes_of(world, other))
        end
        other:remove("camera/3d")
        step("other removed")

    -- `me` still carries `camera/3d`, so only `other`'s own parts are taken off. The list is the
    -- engine's, so the registry leaves it: a removal would be refused, with a warning in the log.
    elseif phase == "other removed" and clock > 0.3 then
        suite.assert_test("C6_removing_camera_3d_while_viewed_leaves_the_view_and_no_eye",
            #eyes_of(world, other) == 0 and viewed_by(other, { sources[5] }) and view_of(world, sources[5]),
            "eyes=" .. #eyes_of(world, other))
        me:remove("camera/3d")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        suite.assert_test("D9_removal_despawns_the_eye", #eyes_of(world, me) == 0
            and #world:query({ iter_many = { first_eye }, with = { "Camera" } }) == 0, "")
        phase = "done"
        suite.finish("Camera3dSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("D0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("Camera3dSuite")
    end
end):in_set("zz/camera3d_suite")
