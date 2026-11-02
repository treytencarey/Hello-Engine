-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

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

-- Which region index an entity has, and whether its edges reach another.
local function index_of(graph, entity)
    for i, r in ipairs(graph.regions) do
        if r.entity == entity then
            return i
        end
    end
end

local function joined(graph, world, from, to, kind)
    local a, b = index_of(graph, named(world, from):id()), index_of(graph, named(world, to):id())
    for _, e in ipairs(a and graph.edges[a] or {}) do
        if e.to == b and (kind == nil or e.kind == kind) then
            return true
        end
    end
    return false
end

-- A reload refills `ai/nav`, which is how a case knows it ran.
local refills = 0
app:add_systems(Update, {
    Query[{
        changed = { "ai/nav" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        if e:get("zz/name").name == "scout" then
            refills = refills + 1
        end
    end
end):in_set("zz/nav_graph_suite_refills")

local phase, clock = "before", 0
local refills_before = 0

app:add_systems(Update, { World, Res[Time], Res["ai/nav/graph"], Commands }, function(world, time, res, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local ok, graph = pcall(function() return res:get() end)
    local count = ok and #graph.regions or -1

    if phase == "before" and clock > 0.5 then
        suite.assert_test("G1_no_graph_before_an_agent_brings_the_mod", not ok, "regions " .. count)
        commands:spawn({
            ["zz/name"] = { name = "scout" },
            ["ai/nav"] = { capabilities = { crawl = true } },
            ["ai/nav/path"] = { solved_id = 1, status = "ready", path = {}, regions = {} },
        })
        commands:spawn({ ["zz/name"] = { name = "plain" }, ["ai/nav"] = {} })
        step("built")

    elseif phase == "built" and count >= 0 and count > 0 then
        suite.assert_test("G2_the_graph_holds_regions_older_than_the_mod", count == 4, "regions " .. count)
        suite.assert_test("G3_their_edges_are_built",
            joined(graph, world, "west", "north") and joined(graph, world, "north", "east")
                and not joined(graph, world, "west", "east"), "")
        suite.assert_test("G4_capabilities_default_to_none_and_stay_as_given",
            next(named(world, "plain"):get("ai/nav").capabilities) == nil
                and named(world, "scout"):get("ai/nav").capabilities.crawl == true, "")
        local west = graph.regions[index_of(graph, named(world, "west"):id())]
        suite.assert_test("G5_a_region_defaults_its_height_and_cost",
            west.y == 0 and west.cost == 1 and west.center.x == -16, tostring(west.center.x))
        commands:spawn({ ["zz/name"] = { name = "island" }, ["ai/nav/region"] = box(200, 210, 200, 210) })
        step("added")

    elseif phase == "added" and count == 5 then
        suite.assert_test("G6_a_new_region_joins_the_graph", true, "")
        commands:spawn({
            ["zz/name"] = { name = "vent" },
            ["ai/nav/link"] = {
                from = named(world, "west"):id(),
                to = named(world, "island"):id(),
                kind = "vent",
                capability = "crawl",
            },
        })
        step("linked")

    elseif phase == "linked" and joined(graph, world, "west", "island", "vent") then
        suite.assert_test("G7_a_link_joins_regions_by_their_entities",
            joined(graph, world, "island", "west", "vent"), "")
        named(world, "north"):patch({ ["ai/nav/region"] = box(-8, 7, 8, 24) })
        step("moved")

    elseif phase == "moved" and not joined(graph, world, "north", "east") then
        suite.assert_test("G8_a_changed_region_changes_its_edges", joined(graph, world, "west", "north"), "")
        commands:entity(named(world, "island"):id()):despawn()
        step("despawned")

    elseif phase == "despawned" and count == 4 then
        suite.assert_test("G9_a_link_loses_a_region_that_goes", not joined(graph, world, "west", "east", "vent"), "")
        commands:entity(named(world, "vent"):id()):despawn()
        commands:spawn({ ["zz/name"] = { name = "spare" }, ["ai/nav/region"] = box(400, 410, 400, 410) })
        step("spare")

    elseif phase == "spare" and count == 5 then
        commands:entity(named(world, "spare"):id()):despawn()
        step("spare gone")

    -- No link names this one, so only its own removal can change the graph.
    elseif phase == "spare gone" and count == 4 then
        suite.assert_test("G9b_a_gone_region_leaves_the_graph", true, "")
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/nav/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        step("after reload")

    elseif phase == "after reload" and clock > 0.3 then
        suite.assert_test("G10_a_reload_keeps_the_graph", count == 4 and joined(graph, world, "west", "north"),
            "regions " .. count)
        suite.assert_test("G11_a_reload_keeps_the_capabilities_given",
            named(world, "scout"):get("ai/nav").capabilities.crawl == true, "")
        commands:entity(named(world, "scout"):id()):remove("ai/nav")
        step("left")

    elseif phase == "left" and not named(world, "scout"):has("ai/nav") and not named(world, "scout"):has("ai/nav/path") then
        suite.assert_test("G12_the_path_goes_with_ai_nav", true, "")
        suite.assert_test("G13_the_graph_stays_while_an_agent_has_it", count == 4, "regions " .. count)
        commands:entity(named(world, "plain"):id()):despawn()
        step("unloaded")

    -- The mod unloads with its last agent, so nothing is watching the regions now.
    elseif phase == "unloaded" and clock > 0.3 then
        commands:spawn({ ["zz/name"] = { name = "unseen" }, ["ai/nav/region"] = box(300, 310, 300, 310) })
        step("unwatched")

    elseif phase == "unwatched" and clock > 0.5 then
        suite.assert_test("G14_nothing_watches_the_regions_once_the_last_agent_left", count == 4, "regions " .. count)
        commands:spawn({ ["zz/name"] = { name = "back" }, ["ai/nav"] = {} })
        step("returned")

    elseif phase == "returned" and count == 5 then
        suite.assert_test("G15_the_next_agent_builds_it_again_from_what_is_there",
            joined(graph, world, "west", "north"), "regions " .. count)
        phase = "done"
        suite.finish("NavGraphSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("G0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s, regions " .. count)
        phase = "done"
        suite.finish("NavGraphSuite")
    end
end):in_set("zz/nav_graph_suite")
