-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("NavRequestSuite")

local function box(min_x, max_x, min_z, max_z)
    return { min_x = min_x, max_x = max_x, min_z = min_z, max_z = max_z }
end

local function agent(commands, name, x, z, extra)
    local bundle = {
        ["zz/name"] = { name = name },
        ["ai/nav"] = {},
        Transform = { translation = { x = x, y = 1, z = z } },
    }
    for k, v in pairs(extra or {}) do
        bundle[k] = v
    end
    commands:spawn(bundle)
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    agent(commands, "scout", -16, 0)
    agent(commands, "crawler", -16, 4, { ["ai/nav"] = { capabilities = { crawl = true } } })
    agent(commands, "walker", -16, 8)
    agent(commands, "one", -16, 12)
    agent(commands, "two", -16, 14)
    agent(commands, "leaver", -16, 16)
    agent(commands, "stranger", 300, 300)
    -- A real body with steering, walking what it is given.
    agent(commands, "body", -16, -12, {
        ["ai/steering"] = { speed = 10 },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
    })
    commands:spawn({
        ["zz/floor"] = {},
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 500 } },
    })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav", "ai/nav/request", "ai/nav/path", "ai/nav/serving", "ai/nav/search", "Transform", "ai/steering/state", "ai/steering", "Velocity3d" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function path_of(world, name) return named(world, name):get("ai/nav/path") end

local function ask(commands, world, name, key, x, z)
    commands:entity(named(world, name):id()):patch({ ["ai/nav/request"] = { [key] = { to = { x = x, y = 0.5, z = z } } } })
end

local function drop(commands, world, name, key)
    commands:entity(named(world, name):id()):patch({ ["ai/nav/request"] = { [key] = null } })
end

local function goal_of(path)
    local list = path and path.path or {}
    return list[#list] or {}
end

-- Two askers writing in one frame, one system ordered before the other. On "one" the first
-- writes `chase`, and on "two" the first writes `flee`, so each order is seen.
local collide = nil
app:add_systems(Update, { World, Commands }, function(world, commands)
    if collide == "ask" then
        ask(commands, world, "one", "chase", 16, 0)
        ask(commands, world, "two", "flee", 16, 0)
    elseif collide == "swap" then
        drop(commands, world, "one", "chase")
        drop(commands, world, "two", "flee")
    end
end):in_set("zz/nav_request_suite_first")

app:add_systems(Update, { World, Commands }, function(world, commands)
    if collide == "ask" then
        ask(commands, world, "one", "flee", 16, 4)
        ask(commands, world, "two", "chase", 16, 4)
        collide = nil
    elseif collide == "swap" then
        ask(commands, world, "one", "guard", 16, 8)
        ask(commands, world, "two", "guard", 16, 8)
        collide = nil
    end
end):in_set("zz/nav_request_suite_second"):after("zz/nav_request_suite_first")

-- How high a walker's detour takes it.
local body_reach = 0
app:add_systems(Update, {
    Query[{ with = { "zz/name", "ai/steering/state", "Transform" } }],
}, function(bodies)
    for _, e in ipairs(bodies:iter()) do
        body_reach = math.max(body_reach, math.abs(e:get("Transform").translation.z))
    end
end):in_set("zz/nav_request_suite_body")

-- The watcher says when it saw the mod's file change: this is how a case knows the reload ran.
local refills = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/nav/server/init.lua", 1, true) then
            refills = refills + 1
        end
    end
end):in_set("zz/nav_request_suite_refills")

local phase, clock = "setup", 0
local solved, refills_before = nil, 0
local frame, asked_at = 0, 0
local ring = {}

local function spawn_ring(commands)
    ring.west = commands:spawn({ ["zz/ring"] = {}, ["ai/nav/region"] = box(-24, -8, -24, 24) }):id()
    ring.north = commands:spawn({ ["zz/ring"] = {}, ["ai/nav/region"] = box(-8, 8, 8, 24) }):id()
    ring.east = commands:spawn({ ["zz/ring"] = {}, ["ai/nav/region"] = box(8, 24, -24, 24) }):id()
    ring.south = commands:spawn({ ["zz/ring"] = {}, ["ai/nav/region"] = box(-8, 8, -24, -8) }):id()
end

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local scout = named(world, "scout")
    frame = frame + 1

    if phase == "setup" and scout and scout:has("ai/nav/request") then
        suite.assert_test("R1_it_adds_the_request_empty_when_it_sets_up",
            next(scout:get("ai/nav/request")) == nil and not scout:has("ai/nav/path") and not scout:has("ai/nav/serving"), "")
        ask(commands, world, "scout", "chase", 16, 0)
        step("no regions")

    elseif phase == "no regions" and path_of(world, "scout") then
        local p = path_of(world, "scout")
        suite.assert_test("R2_with_no_regions_at_all_it_walks_straight_to_the_goal",
            p.status == "ready" and #p.path == 1 and goal_of(p).x == 16 and goal_of(p).y == 0.5 and goal_of(p).kind == "goal", "")
        solved = p.solved_id
        spawn_ring(commands)
        step("regions arrived")

    elseif phase == "regions arrived" and path_of(world, "scout").solved_id ~= solved then
        local p = path_of(world, "scout")
        suite.assert_test("R3_when_the_graph_changes_it_answers_again_with_the_route_around",
            p.status == "ready" and #p.path == 3 and #p.regions == 3 and goal_of(p).x == 16 and math.abs(math.abs(p.path[1].z) - 16) < 1,
            "waypoints " .. #p.path)
        suite.assert_test("R4_a_waypoints_first_step_crosses_a_border", math.abs(p.path[1].x + 8) < 0.5,
            "x " .. tostring(p.path[1].x))
        solved = p.solved_id
        ask(commands, world, "scout", "chase", -16, 16)
        asked_at = frame
        step("short")

    elseif phase == "short" and path_of(world, "scout").solved_id ~= solved then
        local p = path_of(world, "scout")
        suite.assert_test("R5_a_short_path_replaces_a_long_one_whole",
            #p.path == 1 and goal_of(p).z == 16 and #p.regions == 0, "waypoints " .. #p.path)
        suite.assert_test("R6_a_new_goal_changes_the_solved_id", p.solved_id ~= solved, "")
        suite.assert_test("R6b_an_answer_within_the_budget_is_there_the_next_frame", frame == asked_at + 1,
            "after " .. (frame - asked_at) .. " frames")
        solved = p.solved_id
        ask(commands, world, "scout", "chase", -16, 16)
        step("same place")

    elseif phase == "same place" and clock > 0.2 then
        suite.assert_test("R7_writing_the_same_place_again_solves_nothing", path_of(world, "scout").solved_id == solved, "")
        ask(commands, world, "scout", "chase", 500, 500)
        step("off graph")

    elseif phase == "off graph" and path_of(world, "scout").status == "unreachable" then
        local p = path_of(world, "scout")
        suite.assert_test("R8_a_goal_off_the_graph_is_unreachable_with_an_empty_path", #p.path == 0 and #p.regions == 0, "")
        -- a region of its own, which nothing reaches
        commands:spawn({ ["zz/name"] = { name = "island" }, ["ai/nav/region"] = box(200, 210, 200, 210) })
        ask(commands, world, "scout", "chase", 205, 205)
        solved = p.solved_id
        step("island")

    elseif phase == "island" and path_of(world, "scout").solved_id ~= solved and clock > 0.2 then
        local p = path_of(world, "scout")
        suite.assert_test("R9_a_goal_nothing_reaches_is_unreachable_with_an_empty_path",
            p.status == "unreachable" and #p.path == 0, tostring(p.status))
        ask(commands, world, "stranger", "chase", 16, 0)
        step("stranger")

    elseif phase == "stranger" and path_of(world, "stranger") then
        local p = path_of(world, "stranger")
        suite.assert_test("R10_an_agent_off_the_graph_walks_straight_to_the_goal",
            p.status == "ready" and #p.path == 1 and goal_of(p).x == 16, tostring(p.status))
        drop(commands, world, "scout", "chase")
        step("dropped")

    elseif phase == "dropped" and not named(world, "scout"):has("ai/nav/path") then
        suite.assert_test("R11_with_no_entries_the_path_and_the_serving_go",
            not named(world, "scout"):has("ai/nav/serving") and not named(world, "scout"):has("ai/nav/search")
                and named(world, "scout"):has("ai/nav/request"), "")
        ask(commands, world, "scout", "chase", 16, 0)
        step("again")

    elseif phase == "again" and path_of(world, "scout") and goal_of(path_of(world, "scout")).x == 16 then
        solved = path_of(world, "scout").solved_id
        -- One asker leaves and another arrives in one frame.
        commands:entity(scout:id()):patch({
            ["ai/nav/request"] = { chase = null, flee = { to = { x = 16, y = 0.5, z = 20 } } },
        })
        step("handover")

    elseif phase == "handover" and path_of(world, "scout") and goal_of(path_of(world, "scout")).z == 20 then
        suite.assert_test("R12_at_a_handover_the_new_entry_is_served", scout:get("ai/nav/serving").key == "flee",
            tostring(scout:get("ai/nav/serving").key))
        solved = path_of(world, "scout").solved_id
        -- The next arrives while the last is still there.
        ask(commands, world, "scout", "aaa", 16, -20)
        step("overlap")

    elseif phase == "overlap" and goal_of(path_of(world, "scout")).z == -20 then
        suite.assert_test("R13_a_new_entry_is_served_while_the_old_is_still_there",
            scout:get("ai/nav/request").flee ~= nil and scout:get("ai/nav/serving").key == "aaa", "")
        solved = path_of(world, "scout").solved_id
        drop(commands, world, "scout", "flee")
        step("overlap ends")

    elseif phase == "overlap ends" and clock > 0.2 then
        suite.assert_test("R14_the_old_entry_leaving_solves_nothing", path_of(world, "scout").solved_id == solved
            and scout:get("ai/nav/serving").key == "aaa", "")
        -- A new one arrives, and then leaves while the first is still there.
        ask(commands, world, "scout", "zzz", -16, 20)
        step("back up")

    elseif phase == "back up" and goal_of(path_of(world, "scout")).z == 20 then
        solved = path_of(world, "scout").solved_id
        -- The older entry, written again unchanged, is not news.
        ask(commands, world, "scout", "aaa", 16, -20)
        step("unchanged older")

    elseif phase == "unchanged older" and clock > 0.2 then
        suite.assert_test("R14b_an_older_entry_written_unchanged_takes_nothing_over",
            path_of(world, "scout").solved_id == solved and scout:get("ai/nav/serving").key == "zzz",
            tostring(scout:get("ai/nav/serving").key))
        drop(commands, world, "scout", "zzz")
        step("falls back")

    elseif phase == "falls back" and goal_of(path_of(world, "scout")).z == -20 then
        suite.assert_test("R15_with_its_entry_gone_it_serves_the_one_that_remains",
            scout:get("ai/nav/serving").key == "aaa", tostring(scout:get("ai/nav/serving").key))
        solved = path_of(world, "scout").solved_id
        ask(commands, world, "scout", "aaa", 16, -21)
        step("moved")

    elseif phase == "moved" and goal_of(path_of(world, "scout")).z == -21 then
        suite.assert_test("R16_an_entry_going_somewhere_new_is_answered_again", path_of(world, "scout").solved_id ~= solved, "")
        commands:entity(scout:id()):patch({ ["ai/nav/request"] = { bad = { nothing = true } } })
        solved = path_of(world, "scout").solved_id
        step("no place")

    elseif phase == "no place" and clock > 0.2 then
        suite.assert_test("R17_an_entry_with_no_place_is_not_served",
            path_of(world, "scout").solved_id == solved and scout:get("ai/nav/serving").key == "aaa", "")
        drop(commands, world, "scout", "bad")
        collide = "ask"
        step("collide")

    elseif phase == "collide" and path_of(world, "one") and path_of(world, "two") then
        local one, two = named(world, "one"):get("ai/nav/request"), named(world, "two"):get("ai/nav/request")
        suite.assert_test("R18_two_askers_writing_in_one_frame_both_survive_in_either_order",
            one.chase ~= nil and one.flee ~= nil and two.chase ~= nil and two.flee ~= nil, "")
        collide = "swap"
        step("swapped")

    elseif phase == "swapped" and named(world, "one"):get("ai/nav/request").guard ~= nil
        and named(world, "two"):get("ai/nav/request").guard ~= nil then
        local one, two = named(world, "one"):get("ai/nav/request"), named(world, "two"):get("ai/nav/request")
        suite.assert_test("R19_one_leaving_and_another_arriving_in_one_frame_need_no_order",
            one.chase == nil and one.flee ~= nil and two.flee == nil and two.chase ~= nil, "")
        commands:spawn({
            ["zz/name"] = { name = "vent" },
            ["ai/nav/link"] = {
                from = { x = -16, y = 0, z = 0 },
                to = { x = 16, y = 0, z = 0 },
                cost = 1,
                kind = "vent",
                capability = "crawl",
                behavior = "squeeze",
            },
        })
        step("vent")

    elseif phase == "vent" and clock > 0.2 then
        ask(commands, world, "crawler", "chase", 16, 4)
        ask(commands, world, "walker", "chase", 16, 8)
        step("capabilities")

    elseif phase == "capabilities" and path_of(world, "crawler") and path_of(world, "walker") then
        local through, around = path_of(world, "crawler"), path_of(world, "walker")
        suite.assert_test("R20_an_agent_with_the_capability_takes_the_link",
            #through.path == 2 and through.path[1].kind == "vent" and through.path[1].behavior == "squeeze",
            "waypoints " .. #through.path)
        suite.assert_test("R21_an_agent_without_it_goes_around", #around.path == 3, "waypoints " .. #around.path)
        solved = path_of(world, "crawler").solved_id
        commands:entity(ring.north):despawn()
        commands:entity(ring.south):despawn()
        step("cut off")

    elseif phase == "cut off" and path_of(world, "walker").status == "unreachable" then
        suite.assert_test("R22_a_graph_that_no_longer_reaches_answers_unreachable", #path_of(world, "walker").path == 0, "")
        suite.assert_test("R23_every_served_agent_is_answered_again", path_of(world, "crawler").solved_id ~= solved, "")
        spawn_ring(commands)
        for _, name in ipairs({ "west", "east" }) do
            commands:entity(ring[name]):despawn()
        end
        step("restored")

    elseif phase == "restored" and path_of(world, "walker").status == "ready" then
        suite.assert_test("R24_and_a_graph_that_reaches_again_answers_ready", #path_of(world, "walker").path >= 1, "")
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/nav/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        step("after reload")

    elseif phase == "after reload" and clock > 0.4 then
        local s = named(world, "scout")
        suite.assert_test("R25_a_reload_keeps_the_entries_the_serving_and_the_path",
            s:get("ai/nav/request").aaa ~= nil and s:get("ai/nav/serving").key == "aaa" and goal_of(s:get("ai/nav/path")).z == -21, "")
        ask(commands, world, "body", "chase", 16, 0)
        step("walking")

    elseif phase == "walking" and named(world, "body"):get("ai/steering/state")
        and named(world, "body"):get("ai/steering/state").status == "arrived" then
        local at = world:get_entity(named(world, "body"):id()).GlobalTransform:compute_transform().translation
        suite.assert_test("R26_steering_walks_the_answer_to_the_goal",
            math.abs(at.x - 16) < 1.2 and math.abs(at.z) < 1.2, string.format("at %.2f %.2f", at.x, at.z))
        suite.assert_test("R27_around_what_is_not_walkable", body_reach > 12, "reach " .. body_reach)
        ask(commands, world, "body", "chase", -16, 0)
        step("second walk")

    elseif phase == "second walk" and clock > 0.6 then
        drop(commands, world, "body", "chase")
        step("stands")

    -- Soon after, while friction alone would still have it sliding.
    elseif phase == "stands" and not named(world, "body"):has("ai/nav/path") and clock > 0.1 then
        local v = named(world, "body"):get("Velocity3d").linvel
        suite.assert_test("R28_with_no_entries_steering_stands_it_still",
            clock < 0.3 and math.sqrt(v.x * v.x + v.z * v.z) < 2 and named(world, "body"):get("ai/steering/state").status == "idle",
            string.format("speed %.2f after %.2f s", math.sqrt(v.x * v.x + v.z * v.z), clock))
        commands:entity(named(world, "leaver"):id()):patch({ ["ai/nav/request"] = { chase = { to = { x = 16, y = 0, z = 0 } } } })
        step("leaver asks")

    elseif phase == "leaver asks" and path_of(world, "leaver") then
        commands:entity(named(world, "leaver"):id()):remove("ai/nav")
        step("left")

    elseif phase == "left" and not named(world, "leaver"):has("ai/nav") and clock > 0.2 then
        local l = named(world, "leaver")
        suite.assert_test("R29_ai_nav_going_takes_the_request_the_path_and_the_serving",
            not l:has("ai/nav/request") and not l:has("ai/nav/path") and not l:has("ai/nav/serving"), "")
        phase = "done"
        suite.finish("NavRequestSuite")
    end

    if phase ~= "done" and clock > 12 then
        suite.assert_test("R0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s")
        phase = "done"
        suite.finish("NavRequestSuite")
    end
end):in_set("zz/nav_request_suite")
