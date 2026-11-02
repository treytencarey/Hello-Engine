-- --host
-- Two floors, one over the other, with a ramp between, baked from real colliders through the
-- registry. Ground with its top at y = 0; a slab with its top at y = 4 over x -10..10, z -6..6; a
-- ramp from the slab's edge at x = 10 down to the ground at x = 20, over z -2..2, walled on both
-- sides, because a capsule cannot climb a ramp's bare side; and a lid too low to walk under, its
-- underside at y = 1.5.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("NavFloorsSuite")

local function fixed(commands, x, y, z, hx, hy, hz, rotation)
    commands:spawn({
        Transform = { translation = { x = x, y = y, z = z }, rotation = rotation },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = hx, hy = hy, hz = hz } },
    })
end

local function building(commands, name, at, cfg)
    fixed(commands, at, -0.5, 0, 35, 0.5, 25)
    fixed(commands, at, 3.9, 0, 10, 0.1, 6)
    local slope = math.atan(0.4)
    fixed(commands, at + 15 - 0.1 * math.sin(slope), 2 - 0.1 * math.cos(slope), 0, math.sqrt(116) / 2, 0.1, 2,
        Quat.from_rotation_z(-slope))
    fixed(commands, at + 15, 3, 2.5, 5, 3, 0.5)
    fixed(commands, at + 15, 3, -2.5, 5, 3, 0.5)
    fixed(commands, at - 20, 2, 0, 5, 0.5, 5)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav/volumes/box"] = { hx = 30, hz = 20, hy = 3, y = 3 },
        ["ai/nav/volumes"] = cfg,
        Transform = { translation = { x = at, y = 0, z = 0 } },
    })
end

local function agent(commands, name, x, y, z)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav"] = {},
        ["ai/steering"] = { speed = 4 },
        Transform = { translation = { x = x, y = y, z = z } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    building(commands, "map", 0, {})
    building(commands, "slow", 1000, { rays_per_frame = 3 })
    agent(commands, "climber", 0, 1, 4)
    agent(commands, "descender", -5, 5, -3)
    -- one whose first floor overhead has no way up: only the ramp's region reaches it
    commands:spawn({ ["zz/name"] = { name = "scout" }, ["ai/nav"] = {}, Transform = { translation = { x = 0, y = 1, z = 3 } } })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/request", "ai/nav/path", "ai/nav/volumes/due", "ai/nav/volumes/job", "ai/steering/state", "Transform", "Children" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

-- The regions over a point, with the height each sits at.
local function over(graph, x, z)
    local found = {}
    for i, r in ipairs(graph.regions) do
        if x > r.min_x and x < r.max_x and z > r.min_z and z < r.max_z then
            found[#found + 1] = i
        end
    end
    return found
end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 0.05) end

local function at_height(graph, x, z, y)
    for _, i in ipairs(over(graph, x, z)) do
        if near(graph.regions[i].y, y, 0.3) then
            return i
        end
    end
    return nil
end

local function joined(graph, a, b)
    for _, e in ipairs(graph.edges[a] or {}) do
        if e.to == b then
            return e
        end
    end
end

local function ask(commands, world, name, x, y, z)
    commands:entity(named(world, name):id()):patch({ ["ai/nav/request"] = { go = { to = { x = x, y = y, z = z } } } })
end

local function baked(world, name)
    local e = named(world, name)
    return e ~= nil and not e:has("ai/nav/volumes/due") and not e:has("ai/nav/volumes/job")
        and #world:query({ iter_many = e:get("Children") or {}, with = { "ai/nav/volumes/region" } }) > 0
end

local function regions_of(world, name)
    local out = {}
    for _, r in ipairs(world:query({
        iter_many = named(world, name):get("Children") or {},
        with = { "ai/nav/region", "ai/nav/volumes/region" },
    })) do
        local v = r:get("ai/nav/region")
        out[#out + 1] = string.format("%.0f %.0f %.0f %.0f %.2f %.2f %.2f", v.min_x % 1000, v.max_x % 1000, v.min_z, v.max_z, v.y,
            v.min_y or -99, v.max_y or -99)
    end
    table.sort(out)
    return table.concat(out, "|")
end

local reach_x = 0
app:add_systems(Update, {
    Query[{ with = { "zz/name", "ai/steering/state", "Transform" } }],
}, function(agents)
    for _, e in ipairs(agents:iter()) do
        if e:get("zz/name").name == "climber" then
            reach_x = math.max(reach_x, e:get("Transform").translation.x)
        end
    end
end):in_set("zz/nav_floors_suite_reach")

local phase, clock = "baking", 0

app:add_systems(Update, { World, Res[Time], Res["ai/nav/graph"], Commands }, function(world, time, res, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local ok, graph = pcall(function() return res:get() end)

    if phase == "baking" and baked(world, "map") and baked(world, "slow") and clock > 0.5 and ok then
        local ground, upper = at_height(graph, 0, 0, 0), at_height(graph, 0, 0, 4)
        suite.assert_test("F1_the_two_floors_are_each_a_region_over_the_same_point", ground ~= nil and upper ~= nil,
            string.format("ground %s upper %s, regions over it %d", tostring(ground), tostring(upper), #over(graph, 0, 0)))
        suite.assert_test("F2_overlapping_storeys_do_not_join",
            ground ~= nil and upper ~= nil and not joined(graph, ground, upper) and not joined(graph, upper, ground), "")
        suite.assert_test("F3_a_lid_too_low_leaves_no_floor_under_it", at_height(graph, -20, 0, 0) == nil,
            "ground under the lid " .. tostring(at_height(graph, -20, 0, 0)))
        suite.assert_test("F4_the_top_of_the_lid_is_a_floor", at_height(graph, -20, 0, 2.5) ~= nil, "")
        suite.assert_test("F5_ground_under_a_high_enough_slab_runs_on_past_it", ground ~= nil
            and graph.regions[ground].max_z > 6, ground and tostring(graph.regions[ground].max_z) or "")
        local a, b = regions_of(world, "map"), regions_of(world, "slow")
        suite.assert_test("F6_a_small_frame_budget_gives_the_same_regions", a == b and #a > 0, "\n" .. a .. "\n" .. b)
        local spans_ok = true
        for _, r in ipairs(graph.regions) do
            spans_ok = spans_ok and r.min_y <= r.y and r.y <= r.max_y and r.max_y - r.min_y <= 0.46
        end
        suite.assert_test("F6b_each_region_records_its_heights_a_step_apart_at_most", spans_ok, "")
        ask(commands, world, "climber", 0, 4, 4)
        step("climbing")

    elseif phase == "climbing" and (named(world, "climber"):get("ai/steering/state") or {}).status == "arrived" then
        local at = named(world, "climber"):get("Transform").translation
        suite.assert_test("F7_asked_for_the_point_straight_above_it_walks_round_by_the_ramp", reach_x > 12, "reach " .. reach_x)
        suite.assert_test("F8_and_arrives_on_the_upper_floor", at.y > 4.5 and at.y < 5.5 and near(at.x, 0, 1.2) and near(at.z, 4, 1.2),
            string.format("at %.2f %.2f %.2f", at.x, at.y, at.z))
        ask(commands, world, "descender", -5, 0, -3)
        step("descending")

    elseif phase == "descending" and (named(world, "descender"):get("ai/steering/state") or {}).status == "arrived" then
        local at = named(world, "descender"):get("Transform").translation
        suite.assert_test("F9_asked_for_the_point_straight_below_it_walks_down_and_arrives_there",
            at.y > 0.5 and at.y < 1.5 and near(at.x, -5, 1.2) and near(at.z, -3, 1.2),
            string.format("at %.2f %.2f %.2f", at.x, at.y, at.z))
        ask(commands, world, "scout", 0, 0, 3)
        step("same floor")

    elseif phase == "same floor" and named(world, "scout"):has("ai/nav/path") then
        local p = named(world, "scout"):get("ai/nav/path")
        suite.assert_test("F10_a_goal_on_its_own_floor_is_a_straight_walk", p.status == "ready" and #p.path == 1, "waypoints " .. #p.path)
        phase = "done"
        suite.finish("NavFloorsSuite")
    end

    if phase ~= "done" and clock > 40 then
        local who = named(world, phase == "descending" and "descender" or "climber")
        local state = who and who:get("ai/steering/state") or {}
        local at = who and who:get("Transform").translation or {}
        suite.assert_test("F0_reached_" .. phase, false, string.format("stuck; %s at %s %s %s", tostring(state.status),
            tostring(at.x), tostring(at.y), tostring(at.z)))
        phase = "done"
        suite.finish("NavFloorsSuite")
    end
end):in_set("zz/nav_floors_suite")
