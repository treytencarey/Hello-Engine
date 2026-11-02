-- --host
-- The ring a demo scene publishes: four corridors around an unwalkable centre. A route from west
-- to east must go around, which a straight line would not.
--
--   +-------------------------------+
--   |       |     north     |       |
--   |       +---------------+       |
--   | west  |   (nothing)   |  east |
--   |       +---------------+       |
--   |       |     south     |       |
--   +-------------------------------+
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Graph = require("modules/ai/nav/server/graph.lua")

local suite = helpers.create_suite("NavSearchSuite")

local function region(entity, min_x, max_x, min_z, max_z, cost)
    return {
        entity = entity,
        min_x = min_x,
        max_x = max_x,
        min_z = min_z,
        max_z = max_z,
        y = 0,
        cost = cost or 1,
        center = { x = (min_x + max_x) * 0.5, y = (min_z + max_z) * 0.5 },
    }
end

local WEST, NORTH, EAST, SOUTH = 1, 2, 3, 4

local function ring()
    return {
        region("west", -24, -8, -24, 24),
        region("north", -8, 8, 8, 24),
        region("east", 8, 24, -24, 24),
        region("south", -8, 8, -24, -8),
    }
end

local function has_edge(edges, from, to)
    for _, e in ipairs(edges[from] or {}) do
        if e.to == to then
            return e
        end
    end
end

local function solve(regions, edges, from, to, capabilities)
    local center = regions[to].center
    local job = Graph.new_job(from, to, { x = center.x, y = 0, z = center.y }, capabilities)
    while not Graph.step(job, regions, edges, 100) do end
    return job
end

local finished = false

app:add_systems(Update, {}, function()
    if finished then return end
    finished = true

    local regions = ring()
    local edges = Graph.build_edges(regions, {})
    suite.assert_test("NS1_touching_regions_are_joined",
        has_edge(edges, WEST, NORTH) and has_edge(edges, NORTH, WEST) and has_edge(edges, NORTH, EAST)
            and has_edge(edges, EAST, SOUTH) and has_edge(edges, SOUTH, WEST), "")
    suite.assert_test("NS2_regions_apart_are_not", not has_edge(edges, WEST, EAST), "")

    local crossing = has_edge(edges, WEST, NORTH)
    suite.assert_test("NS3_an_edge_crosses_on_the_shared_border",
        math.abs(crossing.x + 8) < 0.5 and crossing.z >= 8 and crossing.z <= 24 and crossing.kind == "walk",
        string.format("x=%s z=%s", tostring(crossing.x), tostring(crossing.z)))
    suite.assert_test("NS4_an_edge_costs_its_distance_times_its_regions_cost", (function()
        local dear = { region("a", 0, 10, 0, 10, 3), region("b", 10, 20, 0, 10, 1) }
        local e = has_edge(Graph.build_edges(dear, {}), 1, 2)
        return math.abs(e.cost - 20) < 1e-3
    end)(), "")

    local corner = { region("a", 0, 10, 0, 10), region("b", 10, 20, 10, 20) }
    suite.assert_test("NS5_a_corner_does_not_join", not has_edge(Graph.build_edges(corner, {}), 1, 2), "")
    local near_corner = { region("a", 0, 10, 0, 10), region("b", 10.2, 20, 10.2, 20) }
    suite.assert_test("NS5b_nor_a_corner_with_a_hairline_gap", not has_edge(Graph.build_edges(near_corner, {}), 1, 2), "")
    local short = { region("a", 0, 10, 0, 10), region("b", 10, 20, 9.8, 20) }
    suite.assert_test("NS5c_nor_a_border_too_short_to_cross", not has_edge(Graph.build_edges(short, {}), 1, 2), "")
    local door = { region("a", 0, 10, 0, 10), region("b", 10, 20, 9.5, 20) }
    local through_door = has_edge(Graph.build_edges(door, {}), 1, 2)
    suite.assert_test("NS5d_half_a_metre_of_border_joins",
        through_door ~= nil and through_door.x == 10 and through_door.z == 9.75, "")
    local gap = { region("a", 0, 10, 0, 10), region("b", 10.2, 20, 0, 10) }
    suite.assert_test("NS6_a_hairline_gap_still_joins", has_edge(Graph.build_edges(gap, {}), 1, 2) ~= nil, "")
    local apart = { region("a", 0, 10, 0, 10), region("b", 11, 20, 0, 10) }
    suite.assert_test("NS7_a_real_gap_does_not", not has_edge(Graph.build_edges(apart, {}), 1, 2), "")

    suite.assert_test("NS8_a_point_inside_locates_its_region",
        Graph.locate(regions, -16, 0, 8) == WEST and Graph.locate(regions, 16, 0, 8) == EAST, "")
    suite.assert_test("NS9_a_point_off_the_graph_snaps_to_the_nearest",
        Graph.locate(regions, -7, 0, 8) == WEST, tostring(Graph.locate(regions, -7, 0, 8)))
    suite.assert_test("NS10_a_point_too_far_locates_nothing", Graph.locate(regions, 500, 500, 8) == nil, "")
    local nested = { region("big", -100, 100, -100, 100), region("small", 40, 60, 40, 60) }
    suite.assert_test("NS11_overlapping_regions_pick_the_nearest_centre", Graph.locate(nested, 50, 50, 8) == 2, "")

    local sliced = Graph.new_job(WEST, EAST, { x = 16, y = 2, z = 0 }, {})
    local slices = 0
    while not Graph.step(sliced, regions, edges, 1) and slices < 50 do
        slices = slices + 1
    end
    suite.assert_test("NS12_a_budget_of_one_takes_several_slices", sliced.done and slices >= 2, "slices " .. slices)
    local waypoints, sequence = Graph.extract_path(sliced)
    suite.assert_test("NS13_the_route_goes_around",
        sliced.result == "found" and #sequence == 3 and sequence[1] == WEST and sequence[3] == EAST
            and (sequence[2] == NORTH or sequence[2] == SOUTH), "route length " .. #(sequence or {}))
    local last = waypoints[#waypoints]
    suite.assert_test("NS14_waypoints_are_the_crossings_then_the_goal",
        #waypoints == 3 and last.x == 16 and last.y == 2 and last.z == 0 and last.kind == "goal"
            and math.abs(math.abs(waypoints[1].z) - 16) < 1 and math.abs(waypoints[1].x + 8) < 0.5,
        "waypoints " .. #waypoints)

    -- north is cheap and south dear, whichever the heuristic would take first
    local priced = ring()
    priced[SOUTH].cost, priced[NORTH].cost = 50, 1
    local _, cheap = Graph.extract_path(solve(priced, Graph.build_edges(priced, {}), WEST, EAST))
    suite.assert_test("NS15_it_takes_the_cheapest_route", cheap[2] == NORTH, "through " .. tostring(cheap[2]))

    local vent = {
        { from = "west", to = "east", x = 0, y = 1, z = 0, cost = 1, kind = "vent", capability = "crawl", behavior = "squeeze" },
    }
    local gated = Graph.build_edges(regions, vent)
    local _, walker = Graph.extract_path(solve(regions, gated, WEST, EAST, { walk = true }))
    suite.assert_test("NS16_a_link_is_closed_without_its_capability", #walker == 3, "route " .. #walker)
    local through, crawler = Graph.extract_path(solve(regions, gated, WEST, EAST, { crawl = true }))
    suite.assert_test("NS17_a_link_is_open_with_its_capability", #crawler == 2, "route " .. #crawler)
    suite.assert_test("NS18_a_links_waypoint_says_what_it_is",
        through[1].kind == "vent" and through[1].behavior == "squeeze" and through[1].y == 1, tostring(through[1].kind))

    local both = Graph.build_edges(regions, { { from = "west", to = "east" } })
    local one = Graph.build_edges(regions, { { from = "west", to = "east", one_way = true } })
    suite.assert_test("NS19_a_link_runs_both_ways_unless_one_way",
        has_edge(both, EAST, WEST) ~= nil and has_edge(one, WEST, EAST) ~= nil and not has_edge(one, EAST, WEST), "")
    suite.assert_test("NS20_a_link_with_a_gone_end_is_no_edge",
        not has_edge(Graph.build_edges(regions, { { from = "west" } }), WEST, EAST), "")

    local island = ring()
    island[5] = region("island", 200, 210, 200, 210)
    local doomed = solve(island, Graph.build_edges(island, {}), WEST, 5)
    suite.assert_test("NS21_a_region_nothing_reaches_is_unreachable",
        doomed.result == "unreachable" and Graph.extract_path(doomed) == nil, tostring(doomed.result))

    -- Reached first by a dear link, then more cheaply through a third region.
    local apart3 = { region("a", 0, 10, 0, 10), region("b", 100, 110, 0, 10), region("c", 200, 210, 0, 10) }
    local dear = Graph.build_edges(apart3, {
        { from = "a", to = "b", cost = 1000, kind = "dear" },
        { from = "a", to = "c", cost = 1, kind = "cheap" },
        { from = "c", to = "b", cost = 1, kind = "cheap" },
    })
    local _, better = Graph.extract_path(solve(apart3, dear, 1, 2))
    suite.assert_test("NS23_a_cheaper_way_to_a_region_replaces_a_dearer_one", #better == 3, "route " .. #better)

    -- A line of six from its third: heading for the end, it never looks the other way.
    local line = {}
    for i = 1, 6 do
        line[i] = region("line" .. i, (i - 1) * 10, i * 10, 0, 10)
    end
    local straight = solve(line, Graph.build_edges(line, {}), 3, 6)
    suite.assert_test("NS22_it_heads_for_the_goal_first", straight.result == "found" and not straight.closed[1],
        "looked at the far end: " .. tostring(straight.closed[1]))

    suite.finish("NavSearchSuite")
end):in_set("zz/nav_search_suite")
