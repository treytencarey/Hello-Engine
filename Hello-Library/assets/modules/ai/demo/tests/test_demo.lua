-- --host
-- The whole stack on the real map: real wanderers from a real spawner, walking and chasing a decoy
-- through the ring of regions.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("DemoSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["map/default"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/name"] = { name = "demo" },
        ["ai/demo"] = { regions = true, decoy = true },
        ["core/net/sync"] = false,
    })
    -- Another of them, so the mod stays loaded when the first is taken off.
    commands:spawn({ ["zz/keeper"] = {}, ["ai/demo"] = { count = 0 }, ["core/net/sync"] = false })
end)

local function demo(world)
    return world:query({
        with = { "zz/name" },
        optional = { "ai/demo", "ai/demo/decoys", "ai/debug/world", "Children" },
    })[1]
end

local function bodies(world)
    return world:query({
        with = { "ai/spawner/agent", "Transform" },
        optional = {
            "ai/archetype/backrooms_wanderer",
            "ai/agent/options",
            "ai/agent/memory",
            "ai/nav/request",
            "ai/nav/path",
            "ai/steering/state",
            "ai/debug",
        },
    })
end

local function decoy_at(world)
    local d = world:query({ with = { "ai/demo/decoy", "Transform" } })[1]
    return d and d:get("Transform").translation
end

local function chosen_name(world, body)
    local o = world:query({
        iter_many = body:get("ai/agent/options") or {},
        with = { "ai/agent/chosen", "Name" },
    })[1]
    return o and tostring(o:get("Name").name)
end

local changes = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/demo/server/init.lua", 1, true) then
            changes = changes + 1
        end
    end
end):in_set("zz/demo_suite_reload")

-- What the wanderers did, as it happened.
local trace = {
    started = {},
    walked = 0,
    chose_patrol = false,
    chose_chase = false,
    chose_investigate = false,
    asked_chase = false,
    heard = false,
    saw_decoy = false,
    nearest = 1000,
    two_regions = false,
    fell = false,
}
local decoy_before = nil

app:add_systems(Update, { World }, function(world)
    local decoy = decoy_at(world)
    for _, b in ipairs(bodies(world)) do
        local at = b:get("Transform").translation
        local id = tostring(b:id())
        trace.started[id] = trace.started[id] or at
        local from = trace.started[id]
        trace.walked = math.max(trace.walked, math.sqrt((at.x - from.x) ^ 2 + (at.z - from.z) ^ 2))
        trace.fell = trace.fell or at.y < 0
        local name = chosen_name(world, b) or ""
        if name:find("patrol", 1, true) then
            trace.chose_patrol = true
        elseif name:find("investigate", 1, true) then
            trace.chose_investigate = true
        elseif name:find("chase", 1, true) then
            trace.chose_chase = true
            if decoy ~= nil then
                trace.nearest = math.min(trace.nearest, math.sqrt((at.x - decoy.x) ^ 2 + (at.z - decoy.z) ^ 2))
            end
        end
        local memory = b:get("ai/agent/memory")
        if memory ~= nil then
            trace.heard = trace.heard or #memory.sound > 0
            trace.saw_decoy = trace.saw_decoy or #memory.seen > 0
        end
        local request = b:get("ai/nav/request")
        trace.asked_chase = trace.asked_chase or (request ~= nil and request.chase ~= nil)
        local path = b:get("ai/nav/path")
        trace.two_regions = trace.two_regions or (path ~= nil and path.regions ~= nil and #path.regions >= 2)
    end
end):in_set("zz/demo_suite_trace")

local phase, clock, before = "built", 0, 0
local first_body

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "built" and clock > 1 then
        local list = bodies(world)
        suite.assert_test("D1_it_makes_the_wanderers_it_was_told", #list == 2, "bodies " .. #list)
        suite.assert_test("D2_each_a_wanderer", list[1] ~= nil and list[1]:has("ai/archetype/backrooms_wanderer"), "")
        suite.assert_test("D2b_not_drawn_unless_asked", list[1] ~= nil and not list[1]:has("ai/debug") and not demo(world):has("ai/debug/world"), "")
        suite.assert_test("D3_the_ring_is_four_regions", #world:query({ with = { "ai/demo/region", "ai/nav/region" } }) == 4, "")
        suite.assert_test("D4_and_one_decoy", #world:query({ with = { "ai/demo/decoy", "ai/perception/target", "ai/noisemaker" } }) == 1, "")
        decoy_before = decoy_at(world)
        step("watching")

    elseif phase == "watching" and trace.chose_chase and trace.nearest < 4 and trace.walked > 3 and trace.heard then
        step("seen enough")

    elseif phase == "watching" and clock > 45 then
        step("seen enough")

    elseif phase == "seen enough" then
        local now = decoy_at(world)
        suite.assert_test("D5_the_decoy_circles", now.x ~= decoy_before.x or now.z ~= decoy_before.z, "")
        suite.assert_test("D6_a_real_wanderer_walks", trace.walked > 3, string.format("walked %.1f", trace.walked))
        suite.assert_test("D7_it_stays_on_the_ground", not trace.fell, "")
        suite.assert_test("D8_it_hears_the_decoy", trace.heard, "")
        suite.assert_test("D9_it_sees_the_decoy", trace.saw_decoy, "")
        suite.assert_test("D10_seeing_it_chooses_to_chase", trace.chose_chase, "")
        suite.assert_test("D11_and_asks_for_the_way", trace.asked_chase, "")
        suite.assert_test("D12_and_closes_on_it", trace.nearest < 4, string.format("nearest %.1f", trace.nearest))
        before = changes
        first_body = bodies(world)[1]:id()
        local path = "assets/modules/ai/demo/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloading")

    elseif phase == "reloading" and changes > before then
        step("reloaded")

    elseif phase == "reloaded" and clock > 0.5 then
        suite.assert_test("D13_a_reload_builds_nothing_twice",
            #bodies(world) == 2 and world:get_entity(first_body) ~= nil and #world:query({ with = { "ai/demo/spawner" } }) == 2
                and #world:query({ with = { "ai/demo/region" } }) == 4 and #world:query({ with = { "ai/demo/decoy" } }) == 1,
            string.format("bodies %d", #bodies(world)))
        commands:entity(demo(world):id()):remove("ai/demo")
        step("taken off")

    elseif phase == "taken off" and clock > 0.5 then
        suite.assert_test("D14_taken_off_everything_it_built_goes",
            #bodies(world) == 0 and #world:query({ with = { "ai/demo/spawner" } }) == 1
                and #world:query({ with = { "ai/demo/region" } }) == 0 and #world:query({ with = { "ai/demo/decoy" } }) == 0,
            string.format("bodies %d", #bodies(world)))
        commands:entity(demo(world):id()):patch({ ["ai/demo"] = { count = 1, debug = true } })
        step("debugging")

    elseif phase == "debugging" and clock > 0.5 then
        local list = bodies(world)
        suite.assert_test("D15_debug_draws_its_wanderers", #list == 1 and list[1]:has("ai/debug"), "bodies " .. #list)
        suite.assert_test("D16_and_its_ground", demo(world):has("ai/debug/world"), "")
        suite.assert_test("D17_no_ring_and_no_decoy_unless_asked",
            #world:query({ with = { "ai/demo/region" } }) == 0 and #world:query({ with = { "ai/demo/decoy" } }) == 0, "")
        commands:entity(demo(world):id()):remove("ai/demo")
        step("debug off")

    elseif phase == "debug off" and clock > 0.5 then
        suite.assert_test("D18_taken_off_it_stops_drawing_its_ground", not demo(world):has("ai/debug/world"), "")
        phase = "done"
        suite.finish("DemoSuite")
    end

    if phase ~= "done" and phase ~= "watching" and clock > 12 then
        suite.assert_test("D0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s")
        phase = "done"
        suite.finish("DemoSuite")
    end
end):in_set("zz/demo_suite")
