-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader
local Graph = require("modules/ai/nav/server/graph.lua")

local suite = helpers.create_suite("NavGraphSuite")

local function box(min_x, max_x, min_z, max_z)
    return { min_x = min_x, max_x = max_x, min_z = min_z, max_z = max_z }
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    -- All of these are here before any agent brings `ai/nav`.
    commands:spawn({ ["zz/name"] = { name = "west" }, ["ai/nav/region"] = box(-24, -8, -24, 24) })
    commands:spawn({ ["zz/name"] = { name = "north" }, ["ai/nav/region"] = box(-8, 8, 8, 24) })
    commands:spawn({ ["zz/name"] = { name = "east" }, ["ai/nav/region"] = box(8, 24, -24, 24) })
    commands:spawn({ ["zz/name"] = { name = "south" }, ["ai/nav/region"] = box(-8, 8, -24, -8) })
    -- not filled in yet, which a provider may do
    commands:spawn({ ["zz/name"] = { name = "unfilled" }, ["ai/nav/region"] = { y = 1 } })
end)

-- The warnings a link end can cause.
local warnings = 0
local real_print = print
print = function(...)
    local first = ...
    if type(first) == "string" and first:find("[ai/nav]", 1, true) then
        warnings = warnings + 1
    end
    real_print(...)
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav", "ai/nav/path", "ai/nav/region" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

-- A point in each region, and whether one's edges reach another's.
local POINTS = {
    west = { -16, 0 },
    north = { 0, 16 },
    east = { 16, 0 },
    island = { 205, 205 },
    baked = { 505, 0 },
}

local function index_at(graph, name)
    return Graph.locate(graph.regions, POINTS[name][1], 0, POINTS[name][2])
end

local function joined(graph, from, to, kind)
    local a, b = index_at(graph, from), index_at(graph, to)
    for _, e in ipairs(a and graph.edges[a] or {}) do
        if e.to == b and (kind == nil or e.kind == kind) then
            return true
        end
    end
    return false
end

local function has_kind(graph, from, kind)
    for _, e in ipairs(graph.edges[index_at(graph, from)] or {}) do
        if e.kind == kind then
            return true
        end
    end
    return false
end

-- The watcher says when it saw the mod's file change: this is how a case knows the reload ran.
local refills = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/nav/server/init.lua", 1, true) then
            refills = refills + 1
        end
    end
end):in_set("zz/nav_graph_suite_refills")

local phase, clock = "before", 0
local refills_before = 0
local baked_region = nil

app:add_systems(Update, {
    World,
    Res[Time],
    Res["ai/nav/graph"],
    Query[{ with = { "ai/nav/volumes/region" } }],
    Commands,
}, function(world, time, res, baked_regions, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local ok, graph = pcall(function() return res:get() end)
    local count = ok and #graph.regions or -1

    if phase == "before" and clock > 0.5 then
        suite.assert_test("G1_no_graph_before_an_agent_brings_the_mod", not ok, "regions " .. count)
        commands:spawn({
            ["zz/name"] = { name = "scout" },
            ["ai/nav"] = { capabilities = { crawl = true } },
        })
        commands:spawn({ ["zz/name"] = { name = "plain" }, ["ai/nav"] = {} })
        step("built")

    elseif phase == "built" and count >= 0 and count > 0 then
        suite.assert_test("G2_the_graph_holds_regions_older_than_the_mod", count == 4, "regions " .. count)
        suite.assert_test("G3_their_edges_are_built",
            joined(graph, "west", "north") and joined(graph, "north", "east")
                and not joined(graph, "west", "east"), "")
        suite.assert_test("G4_capabilities_default_to_none_and_stay_as_given",
            next(named(world, "plain"):get("ai/nav").capabilities) == nil
                and named(world, "scout"):get("ai/nav").capabilities.crawl == true, "")
        local west = graph.regions[index_at(graph, "west")]
        suite.assert_test("G5_a_region_defaults_its_height_and_cost",
            west.y == 0 and west.cost == 1 and west.center.x == -16, tostring(west.center.x))
        commands:spawn({ ["zz/name"] = { name = "island" }, ["ai/nav/region"] = box(200, 210, 200, 210) })
        step("added")

    elseif phase == "added" and count == 5 then
        suite.assert_test("G6_a_new_region_joins_the_graph", true, "")
        commands:spawn({
            ["zz/name"] = { name = "vent" },
            ["ai/nav/link"] = {
                from = { x = -16, y = 0, z = 0 },
                to = { x = 205, y = 0, z = 205 },
                kind = "vent",
                capability = "crawl",
            },
        })
        step("linked")

    elseif phase == "linked" and joined(graph, "west", "island", "vent") then
        suite.assert_test("G7_a_link_joins_the_regions_at_its_positions",
            joined(graph, "island", "west", "vent"), "")
        named(world, "north"):patch({ ["ai/nav/region"] = box(-8, 7, 8, 24) })
        step("moved")

    elseif phase == "moved" and not joined(graph, "north", "east") then
        suite.assert_test("G8_a_changed_region_changes_its_edges", joined(graph, "west", "north"), "")
        commands:entity(named(world, "island"):id()):despawn()
        step("despawned")

    elseif phase == "despawned" and count == 4 then
        suite.assert_test("G9_a_link_with_no_region_at_an_end_makes_no_edge", not has_kind(graph, "west", "vent"), "")
        suite.assert_test("G9c_and_warns", warnings == 1, "warnings " .. warnings)
        commands:spawn({ ["zz/name"] = { name = "spare" }, ["ai/nav/region"] = box(400, 410, 400, 410) })
        step("spare")

    elseif phase == "spare" and count == 5 then
        commands:entity(named(world, "spare"):id()):despawn()
        step("spare gone")

    -- No link names this one, so only its own removal can change the graph.
    elseif phase == "spare gone" and count == 4 then
        suite.assert_test("G9b_a_gone_region_leaves_the_graph", true, "")
        suite.assert_test("G9d_a_rebuild_does_not_warn_of_it_again", warnings == 1, "warnings " .. warnings)
        commands:entity(named(world, "vent"):id()):despawn()
        -- A bake's regions: changing the volume respawns them, and a link from them still works.
        commands:spawn({
            ["zz/name"] = { name = "bake" },
            ["ai/nav/volumes/box"] = { hx = 5, hz = 5 },
            ["ai/nav/volumes"] = { sample = false },
            Transform = { translation = { x = 505, y = 0, z = 0 } },
        })
        commands:spawn({
            ["zz/name"] = { name = "hatch" },
            ["ai/nav/link"] = {
                from = { x = -16, y = 0, z = 0 },
                to = { x = 505, y = 0, z = 0 },
                kind = "hatch",
            },
        })
        step("baked")

    elseif phase == "baked" and count == 5 and has_kind(graph, "west", "hatch") then
        baked_region = baked_regions:iter()[1]:id()
        suite.assert_test("G16_a_link_reaches_a_baked_region", joined(graph, "west", "baked", "hatch"), "")
        named(world, "bake"):patch({ ["ai/nav/volumes/box"] = { hx = 6 } })
        step("rebaking")

    elseif phase == "rebaking" and baked_regions:iter()[1] and baked_regions:iter()[1]:id() ~= baked_region and clock > 0.2 then
        suite.assert_test("G17_a_bake_respawning_its_region_keeps_the_link",
            count == 5 and joined(graph, "west", "baked", "hatch") and joined(graph, "baked", "west", "hatch"), "")
        step("settled")

    -- Anything left over from the bake is over by now.
    elseif phase == "settled" and clock > 0.5 then
        commands:entity(named(world, "hatch"):id()):despawn()
        step("unhatched")

    -- No region changes, so only the link's own removal can change the graph.
    elseif phase == "unhatched" and not has_kind(graph, "west", "hatch") then
        suite.assert_test("G17b_a_gone_link_leaves_the_graph", true, "")
        commands:entity(named(world, "bake"):id()):despawn()
        step("unbaked")

    elseif phase == "unbaked" and count == 4 then
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/nav/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        step("after reload")

    elseif phase == "after reload" and clock > 0.3 then
        suite.assert_test("G10_a_reload_keeps_the_graph", count == 4 and joined(graph, "west", "north"),
            "regions " .. count)
        suite.assert_test("G11_a_reload_keeps_the_capabilities_given",
            named(world, "scout"):get("ai/nav").capabilities.crawl == true, "")
        commands:entity(named(world, "scout"):id()):remove("ai/nav")
        step("left")

    elseif phase == "left" and not named(world, "scout"):has("ai/nav") and not named(world, "scout"):has("ai/nav/request") then
        suite.assert_test("G12_the_request_goes_with_ai_nav", true, "")
        suite.assert_test("G13_the_graph_stays_while_an_agent_has_it", count == 4, "regions " .. count)
        commands:entity(named(world, "plain"):id()):despawn()
        step("unloaded")

    -- The mod unloads with its last agent: the graph goes, and its regions are swept, wherever they are.
    elseif phase == "unloaded" and clock > 0.3 then
        suite.assert_test("G14_the_graph_goes_with_the_last_agent", count == -1, "regions " .. count)
        suite.assert_test("G14_and_the_regions_are_swept", not named(world, "west"):has("ai/nav/region"), "")
        commands:spawn({ ["zz/name"] = { name = "unseen" }, ["ai/nav/region"] = box(300, 310, 300, 310) })
        step("unwatched")

    elseif phase == "unwatched" and clock > 0.5 then
        suite.assert_test("G14_nothing_watches_a_region_added_meanwhile", count == -1, "regions " .. count)
        commands:spawn({ ["zz/name"] = { name = "back" }, ["ai/nav"] = {} })
        -- As the mods that add them do, on `ai/nav`'s `added` edge.
        commands:entity(named(world, "west"):id()):insert({ ["ai/nav/region"] = box(-24, -8, -24, 24) })
        commands:entity(named(world, "north"):id()):insert({ ["ai/nav/region"] = box(-8, 7, 8, 24) })
        commands:entity(named(world, "east"):id()):insert({ ["ai/nav/region"] = box(8, 24, -24, 24) })
        commands:entity(named(world, "south"):id()):insert({ ["ai/nav/region"] = box(-8, 8, -24, -8) })
        step("returned")

    elseif phase == "returned" and count == 5 then
        suite.assert_test("G15_the_next_agent_builds_it_again_from_what_is_there",
            joined(graph, "west", "north"), "regions " .. count)
        phase = "done"
        suite.finish("NavGraphSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("G0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s, regions " .. count)
        phase = "done"
        suite.finish("NavGraphSuite")
    end
end):in_set("zz/nav_graph_suite")
