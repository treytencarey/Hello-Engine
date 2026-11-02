-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("SteeringServerSuite")

-- A body as a spawner builds one: a dynamic capsule on the ground, turned only by what writes its
-- Transform.
local function agent(commands, name, x, z, steering, extra)
    local bundle = {
        ["zz/name"] = { name = name },
        ["ai/steering"] = steering,
        Transform = { translation = { x = x, y = 1, z = z } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
    }
    for k, v in pairs(extra or {}) do
        bundle[k] = v
    end
    commands:spawn(bundle)
end

local function path(id, ...)
    local list = {}
    for _, p in ipairs({ ... }) do
        list[#list + 1] = { x = p[1], y = 0, z = p[2], kind = "walk" }
    end
    return { solved_id = id, status = #list > 0 and "ready" or "unreachable", path = list, regions = {} }
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 500 } },
    })
    agent(commands, "walker", 0, 0, { speed = 3 })
    agent(commands, "east", 0, 40, { speed = 3 })
    agent(commands, "south", 0, 80, { speed = 3 })
    agent(commands, "passer", 0, 120, { speed = 2 })
    agent(commands, "bystander", 5, 121, {}, { ["ai/nav/path"] = path(1) })
    agent(commands, "control", 0, 160, { speed = 2 })
    agent(commands, "stuck", 0, 200, { speed = 3 })
    commands:spawn({
        ["zz/wall"] = {},
        Transform = { translation = { x = 3, y = 1, z = 200 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 0.5, hy = 2, hz = 3 } },
    })
    agent(commands, "pathless", 0, 240, {})
    agent(commands, "leaver", 0, 280, { speed = 3 }, { ["ai/nav"] = {} })
    agent(commands, "dropper", 0, 320, { speed = 3 })
    agent(commands, "long", 0, 360, { speed = 2 })
    -- Its path is there before its state is.
    agent(commands, "born", 0, 400, { speed = 2 }, { ["ai/nav/path"] = path(1, { 200, 400 }) })
    -- High up, so its fall is plain to see.
    agent(commands, "high", 0, 440, { speed = 3 }, { Transform = { translation = { x = 0, y = 30, z = 440 } } })
    -- Told there is no way on while it is still walking.
    agent(commands, "rerouted", 0, 480, { speed = 3 })
    -- A waypoint straight overhead, as the last and as one on the way.
    agent(commands, "overhead", 0, 560, { speed = 3 })
    agent(commands, "overpass", 0, 600, { speed = 3 })
    -- Its path goes and another arrives in one frame.
    agent(commands, "handed", 0, 520, { speed = 3 })
    -- No body, and no velocity of its own.
    commands:spawn({ ["zz/name"] = { name = "bare" }, ["ai/steering"] = {}, Transform = {} })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/steering", "ai/steering/state", "ai/nav", "ai/nav/path", "Transform", "Velocity3d" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function state_of(world, name) return named(world, name):get("ai/steering/state") or {} end

local function position(world, name)
    return world:get_entity(named(world, name):id()).GlobalTransform:compute_transform().translation
end

local function horizontal(e)
    local v = e:get("Velocity3d").linvel
    return math.sqrt(v.x * v.x + v.z * v.z)
end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 1e-3) end

local function walk(world, commands, name, p)
    commands:entity(named(world, name):id()):insert({ ["ai/nav/path"] = p })
end

-- What happened on the way, frame by frame.
local seen = { top = 0, slowest = nil, flip = nil, passer_z = 120, control_z = 160, writes = 0, stuck_at = nil }
local watching_writes = false

app:add_systems(Update, {
    Query[{
        changed = { "ai/steering/state" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        if watching_writes and e:get("zz/name").name == "long" then
            seen.writes = seen.writes + 1
        end
    end
end):in_set("zz/steering_suite_writes")

-- As `ai/nav` hands a path over: taken away in one system, and answered by one ordered after it,
-- in the schedule before steering runs.
local handing = nil
app:add_systems(PreUpdate, { World, Commands }, function(world, commands)
    if handing == "remove" then
        commands:entity(named(world, "handed"):id()):remove("ai/nav/path")
        handing = "insert"
    end
end):in_set("zz/steering_suite_hand_remove")

app:add_systems(PreUpdate, { World, Commands }, function(world, commands)
    if handing == "insert" then
        walk(world, commands, "handed", path(2, { 200, 521 }))
        handing = nil
    end
end):in_set("zz/steering_suite_hand_insert"):after("zz/steering_suite_hand_remove")

-- A reload refills `ai/steering`, which is how a case knows it ran.
local refills = 0
app:add_systems(Update, {
    Query[{
        changed = { "ai/steering" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        if e:get("zz/name").name == "pathless" then
            refills = refills + 1
        end
    end
end):in_set("zz/steering_suite_refills")

local phase, clock = "filled", 0
local refills_before, cursor_before = 0, nil

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    local w = named(world, "walker")
    if w and w:get("ai/steering/state") and w:get("ai/steering/state").status == "moving" then
        local at = w:get("Transform").translation
        local speed = horizontal(w)
        local cursor = w:get("ai/steering/state").cursor
        if cursor == 1 then
            seen.top = math.max(seen.top, speed)
        end
        if cursor == 2 then
            if seen.flip == nil then
                seen.flip = math.sqrt((at.x - 12) ^ 2 + at.z ^ 2)
            end
            local left = math.sqrt((at.x - 12) ^ 2 + (at.z - 8) ^ 2)
            if left < 1.2 and (seen.slowest == nil or speed < seen.slowest) then
                seen.slowest = speed
            end
        end
    end
    local stuck = named(world, "stuck")
    if seen.stuck_speed == nil and stuck and (stuck:get("ai/steering/state") or {}).status == "blocked" then
        seen.stuck_speed = horizontal(stuck)
    end
    local passer = named(world, "passer")
    if passer and passer:get("Transform") then
        seen.passer_z = math.min(seen.passer_z, passer:get("Transform").translation.z)
    end
    local control = named(world, "control")
    if control and control:get("Transform") then
        seen.control_z = math.min(seen.control_z, control:get("Transform").translation.z)
    end

    if phase == "filled" and w and (w:get("ai/steering") or {}).arrive_radius ~= nil and w:has("ai/steering/state") and clock > 0.5 then
        local s = w:get("ai/steering")
        suite.assert_test("S1_missing_fields_get_defaults_and_given_ones_stay",
            s.speed == 3 and near(s.arrive_radius, 0.9) and near(s.pass_radius, 1.44) and near(s.ease_radius, 2.25)
                and near(s.ease_floor, 0.25) and near(s.separation_radius, 1.5) and near(s.separation_strength, 1.2)
                and s.turn_speed == 6 and near(s.stall_sample, 0.5) and near(s.stall_distance, 0.25)
                and near(s.stall_timeout, 1.5), "")
        suite.assert_test("S2_with_no_path_it_is_idle_and_goes_nowhere",
            state_of(world, "pathless").status == "idle" and horizontal(named(world, "pathless")) < 0.05, "")
        suite.assert_test("S2b_a_path_older_than_its_state_is_walked", state_of(world, "born").status == "moving",
            tostring(state_of(world, "born").status))
        suite.assert_test("S3_it_adds_a_velocity_when_there_is_none", named(world, "bare"):has("Velocity3d"), "")
        walk(world, commands, "walker", path(1, { 12, 0 }, { 12, 8 }))
        walk(world, commands, "east", path(1, { 200, 40 }))
        walk(world, commands, "south", path(1, { 0, -200 }))
        walk(world, commands, "passer", path(1, { 12, 120 }))
        walk(world, commands, "control", path(1, { 12, 160 }))
        walk(world, commands, "stuck", path(1, { 20, 200 }))
        walk(world, commands, "leaver", path(1, { 200, 280 }))
        commands:entity(named(world, "overhead"):id()):insert({
            ["ai/nav/path"] = { solved_id = 1, status = "ready", regions = {}, path = { { x = 0, y = 10, z = 560 } } },
        })
        commands:entity(named(world, "overpass"):id()):insert({
            ["ai/nav/path"] = {
                solved_id = 1,
                status = "ready",
                regions = {},
                path = { { x = 0, y = 10, z = 600 }, { x = 30, y = 0, z = 600 } },
            },
        })
        walk(world, commands, "dropper", path(1, { 200, 320 }))
        walk(world, commands, "handed", path(1, { 200, 520 }))
        walk(world, commands, "long", path(1, { 4, 360 }, { 200, 360 }))
        walk(world, commands, "high", path(1, { 200, 440 }))
        walk(world, commands, "rerouted", path(1, { 200, 480 }))
        step("walking")

    elseif phase == "walking" and clock > 1.5 and clock < 1.8 and not seen.checked_walking then
        seen.checked_walking = true
        local e = named(world, "east"):get("Transform").rotation
        local want_e = Quat.from_rotation_y(math.pi / 2)
        suite.assert_test("S4_it_faces_where_it_goes",
            near(math.abs(e.x * want_e.x + e.y * want_e.y + e.z * want_e.z + e.w * want_e.w), 1, 0.01),
            string.format("rotation y=%.3f w=%.3f", e.y, e.w))
        local s = named(world, "south"):get("Transform").rotation
        suite.assert_test("S5_it_faces_directly_backwards_upright",
            near(math.abs(s.y), 1, 0.01) and near(s.x, 0, 0.01) and near(s.z, 0, 0.01),
            string.format("rotation %.3f %.3f %.3f %.3f", s.x, s.y, s.z, s.w))
        suite.assert_test("S6_it_walks_at_its_speed", near(horizontal(named(world, "east")), 3, 0.3),
            "speed " .. horizontal(named(world, "east")))
        suite.assert_test("S7_rapier_moves_the_body", position(world, "east").x > 3,
            "x " .. position(world, "east").x)
        suite.assert_test("S8_a_body_keeps_falling_while_it_walks", position(world, "high").y < 25,
            "y " .. position(world, "high").y)
        named(world, "east"):patch({ ["ai/steering"] = { speed = 1 } })
        seen.writes, watching_writes = 0, true
        commands:entity(named(world, "dropper"):id()):remove("ai/nav/path")
        handing = "remove"
        commands:entity(named(world, "leaver"):id()):remove("ai/nav")
        step("stops")

    elseif phase == "stops" and clock > 0.5 then
        suite.assert_test("S9b_a_last_waypoint_on_another_floor_is_not_arrived_at", state_of(world, "overhead").status ~= "arrived",
            tostring(state_of(world, "overhead").status))
        suite.assert_test("S9c_nor_one_on_the_way_passed", state_of(world, "overpass").cursor == 1,
            "cursor " .. tostring(state_of(world, "overpass").cursor))
        suite.assert_test("S9d_height_radius_defaults", near(named(world, "overhead"):get("ai/steering").height_radius, 1.5), "")
        suite.assert_test("S9_a_new_speed_applies_at_once", near(horizontal(named(world, "east")), 1, 0.2),
            "speed " .. horizontal(named(world, "east")))
        local dropper, leaver = named(world, "dropper"), named(world, "leaver")
        suite.assert_test("S10b_a_path_replaced_in_the_frame_it_went_walks_on",
            state_of(world, "handed").status == "moving" and state_of(world, "handed").for_solved == 2
                and horizontal(named(world, "handed")) > 2, tostring(state_of(world, "handed").status))
        suite.assert_test("S10_with_its_path_gone_it_stands_still_and_idle",
            state_of(world, "dropper").status == "idle" and horizontal(dropper) < 0.2, "speed " .. horizontal(dropper))
        suite.assert_test("S11_ai_nav_leaving_takes_the_path_and_so_stands_it_still",
            not leaver:has("ai/nav/path") and state_of(world, "leaver").status == "idle" and horizontal(leaver) < 0.2,
            "speed " .. horizontal(leaver))
        commands:entity(named(world, "south"):id()):remove("ai/steering")
        step("left off")

    -- Soon after, while friction alone would still have it sliding.
    elseif phase == "left off" and not named(world, "south"):has("ai/steering") and clock > 0.1 then
        local south = named(world, "south")
        suite.assert_test("S12_removing_it_takes_its_state_stands_it_still_and_keeps_its_velocity",
            not south:has("ai/steering/state") and south:has("Velocity3d") and clock < 0.3 and horizontal(south) < 0.3,
            string.format("speed %.2f after %.2f s", horizontal(south), clock))
        step("arriving")

    elseif phase == "arriving" and state_of(world, "walker").status == "arrived" and clock > 0.5 then
        local at = position(world, "walker")
        local left = math.sqrt((at.x - 12) ^ 2 + (at.z - 8) ^ 2)
        suite.assert_test("S13_it_arrives_at_the_last_waypoint", left < 1.1, "left " .. left)
        suite.assert_test("S14_arrived_it_stands_still", horizontal(w) < 0.2, "speed " .. horizontal(w))
        suite.assert_test("S15_a_waypoint_on_the_way_only_needs_brushing_past",
            seen.flip ~= nil and seen.flip > 1.2 and seen.flip < 1.6, "at " .. tostring(seen.flip))
        suite.assert_test("S16_it_slows_for_the_last_waypoint", seen.slowest ~= nil and seen.slowest < 3 * 0.6,
            "slowest " .. tostring(seen.slowest))
        -- several seconds walking, at twice a second, against hundreds of frames
        suite.assert_test("S17_a_walking_agent_rarely_writes_its_state", seen.writes <= 30 and seen.writes >= 1,
            "writes " .. seen.writes)
        walk(world, commands, "walker", path(2, { 12, -6 }))
        step("again")

    elseif phase == "again" and state_of(world, "walker").for_solved == 2 and clock > 0.1 then
        suite.assert_test("S18_a_new_path_starts_from_its_first_waypoint",
            state_of(world, "walker").cursor == 1 and state_of(world, "walker").status == "moving", "")
        step("second arrival")

    elseif phase == "second arrival" and state_of(world, "walker").status == "arrived" then
        local at = position(world, "walker")
        suite.assert_test("S19_and_walks_it", near(at.x, 12, 1.2) and near(at.z, -6, 1.2),
            string.format("at %.2f %.2f", at.x, at.z))
        walk(world, commands, "walker", path(3))
        suite.assert_test("S19b_the_one_still_walking_is_at_speed", horizontal(named(world, "rerouted")) > 2,
            "speed " .. horizontal(named(world, "rerouted")))
        walk(world, commands, "rerouted", path(2))
        step("no route")

    elseif phase == "no route" and state_of(world, "walker").for_solved == 3 and state_of(world, "rerouted").for_solved == 2 then
        suite.assert_test("S20_an_empty_path_is_idle", state_of(world, "walker").status == "idle", "")
        suite.assert_test("S20b_told_mid_walk_it_stands_still_rather_than_gliding",
            state_of(world, "rerouted").status == "idle" and horizontal(named(world, "rerouted")) < 0.05,
            "speed " .. horizontal(named(world, "rerouted")))
        suite.assert_test("S21_a_neighbour_pushes_it_aside", seen.passer_z < 119.8,
            string.format("passer's least z %.2f", seen.passer_z))
        suite.assert_test("S22_with_no_neighbour_it_goes_straight", seen.control_z > 159.9,
            string.format("control's least z %.2f", seen.control_z))
        step("blocked")

    elseif phase == "blocked" and state_of(world, "stuck").status == "blocked" then
        suite.assert_test("S23_against_a_wall_it_is_blocked_in_the_end", true, "")
        suite.assert_test("S23b_and_it_stops_pushing_that_same_frame", seen.stuck_speed ~= nil and seen.stuck_speed < 0.05,
            "speed " .. tostring(seen.stuck_speed))
        suite.assert_test("S24_one_walking_freely_is_not", state_of(world, "east").status == "moving", tostring(state_of(world, "east").status))
        cursor_before = state_of(world, "long").cursor
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local file = "assets/modules/ai/steering/server/init.lua"
        write_file_bytes(file, read_file_bytes(file))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        step("after reload")

    elseif phase == "after reload" and clock > 0.5 then
        suite.assert_test("S25_a_reload_keeps_the_progress",
            cursor_before == 2 and state_of(world, "long").cursor == 2 and state_of(world, "long").status == "moving",
            "cursor " .. tostring(state_of(world, "long").cursor))
        suite.assert_test("S26_a_reload_does_not_walk_a_path_it_finished", state_of(world, "stuck").status == "blocked"
            and state_of(world, "dropper").status == "idle", tostring(state_of(world, "stuck").status))
        suite.assert_test("S27_a_reload_keeps_the_fields_given", named(world, "long"):get("ai/steering").speed == 2, "")
        suite.assert_test("S28_after_a_reload_it_still_walks", horizontal(named(world, "long")) > 1.5,
            "speed " .. horizontal(named(world, "long")))
        phase = "done"
        suite.finish("SteeringServerSuite")
    end

    if phase ~= "done" and clock > 15 then
        suite.assert_test("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        phase = "done"
        suite.finish("SteeringServerSuite")
    end
-- After the walk, so this reads what it wrote before Rapier answers: a wall zeroes a velocity by
-- itself, and "it stops pushing" could then not fail.
end):in_set("zz/steering_suite"):after("ai/steering/walk")
