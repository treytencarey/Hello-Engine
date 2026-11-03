-- --host (windowed: a headless run has no gizmos, so its draw systems report errors)
-- What crosses over a real connection, and what the client makes of it: an isolated server world
-- has a real agent, its drawn ground and a region, and this VM is a client of it.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("DebugNetSuite")

local PORT = 15178

local DEFAULTS = { srv_ready = false, drop_patrol = false, take_off = false }
local ts = helpers.shared_state("DebugNetState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_debug_net_vm1.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("DebugNetState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzdebug", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzdebug", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 100, hy = 0.5, hz = 100 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/agent"] = {},
        ["ai/agent"] = { think_hz = 10 },
        ["ai/behavior/patrol"] = { speed = 0 },
        ["ai/nav"] = {},
        ["ai/steering"] = { stall_timeout = 1000 },
        ["ai/perception"] = {},
        ["ai/debug"] = {},
        Transform = { translation = { x = 0, y = 1, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        ["core/net/sync"] = {
            Transform = { authority = "server", reliable = false },
            ["zz/agent"] = { authority = "server" },
        },
    })
    commands:spawn({ ["zz/ground"] = {}, ["ai/debug/world"] = {}, ["core/net/sync"] = { ["zz/ground"] = { authority = "server" } } })
    commands:spawn({ ["ai/nav/region"] = { min_x = -10, max_x = 10, min_z = -10, max_z = 10, y = 0 }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/second"] = {}, ["ai/nav/region"] = { min_x = 10, max_x = 20, min_z = -10, max_z = 10, y = 0 }, ["core/net/sync"] = false })
end)
app:add_systems(Update, {
    Query[{ with = { "zz/agent", "ai/debug" } }],
    Query[{ with = { "zz/ground", "ai/debug/world" } }],
    Query[{ with = { "zz/second" } }],
    Commands,
}, function(agents, grounds, seconds, commands)
    ts.srv_ready = true
    if ts.drop_patrol then
        for _, e in ipairs(seconds:iter()) do
            commands:entity(e:id()):despawn()
        end
    end
    for _, e in ipairs(agents:iter()) do
        if ts.take_off then
            commands:entity(e:id()):despawn()
        elseif ts.drop_patrol then
            commands:entity(e:id()):try_remove("ai/behavior/patrol")
        end
    end
    if ts.take_off then
        for _, e in ipairs(grounds:iter()) do
            commands:entity(e:id()):despawn()
        end
    end
end):in_set("zz/debug_net_server")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_debug_net_vm1.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })

local function agent(world)
    return world:query({
        with = { "zz/agent" },
        optional = { "ai/debug", "ai/debug/labels", "ai/agent", "ai/agent/memory", "ai/nav/request", "ai/perception", "ai/steering" },
    })[1]
end

local function ground(world)
    return world:query({
        with = { "zz/ground" },
        optional = { "ai/debug/world", "ai/debug/world/slabs" },
    })[1]
end

local phase, t, mark = "wait_srv", 0, 0
local local_debug, local_world

app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    local function step(next_phase) phase, mark = next_phase, t end
    local since = t - mark

    if phase == "wait_srv" and ts.srv_ready then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzdebug_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzdebug_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        step("connecting")

    elseif phase == "connecting" and agent(world) ~= nil and ground(world) ~= nil and agent(world):has("ai/debug") then
        step("drawn")

    elseif phase == "drawn" and since > 1.5 then
        local a = agent(world)
        local d = a:get("ai/debug")
        suite.assert_test("DN1_what_it_thinks_crosses_on_its_own_component", d.chosen == "patrol" and d.vision_range == 18, tostring(d.chosen))
        suite.assert_test("DN2_and_nothing_else_of_an_agent",
            not a:has("ai/agent") and not a:has("ai/agent/memory") and not a:has("ai/nav/request") and not a:has("ai/perception") and not a:has("ai/steering"), "")
        local labels = world:query({ iter_many = a:get("ai/debug/labels") or {}, with = { "ai/debug/label", "Text" } })
        suite.assert_test("DN3_it_has_one_label_naming_the_chosen_option",
            #labels == 1 and tostring(labels[1]:get("Text")):find("patrol", 1, true) ~= nil, "labels " .. #labels)
        local w = ground(world):get("ai/debug/world")
        suite.assert_test("DN4_the_ground_crosses_too", #(w.regions or {}) == 2, "regions " .. #(w.regions or {}))
        suite.assert_test("DN5_with_nothing_of_the_nav_entities", #world:query({ with = { "ai/nav/region" } }) == 0, "")
        suite.assert_test("DN6_a_region_is_a_slab", #(ground(world):get("ai/debug/world/slabs") or {}) == 2,
            "slabs " .. #(ground(world):get("ai/debug/world/slabs") or {}))
        -- Local ones, as a removal on the server stays on its copies.
        local_debug = commands:spawn({
            ["ai/debug"] = { chosen = "local" },
            Transform = {},
            ["core/net/sync"] = false,
        }):id()
        local_world = commands:spawn({
            ["ai/debug/world"] = { regions = { { min_x = 0, max_x = 1, min_z = 0, max_z = 1, y = 0 } }, region_count = 1 },
            ["core/net/sync"] = false,
        }):id()
        ts.drop_patrol = true
        step("dropped")

    elseif phase == "dropped" and since > 1 then
        local a = agent(world)
        local labels = world:query({ iter_many = a:get("ai/debug/labels") or {}, with = { "ai/debug/label", "Text" } })
        suite.assert_test("DN7_the_label_follows_what_is_chosen",
            #labels == 1 and tostring(labels[1]:get("Text")):find("nothing", 1, true) ~= nil, labels[1] and tostring(labels[1]:get("Text")) or "")
        local shown = ground(world):get("ai/debug/world").region_count
        suite.assert_test("DN7b_a_region_gone_on_the_server_goes_here", shown == 1, "regions " .. tostring(shown))
        suite.assert_test("DN8_a_local_one_has_its_label_too", #world:query({ with = { "ai/debug/label" } }) == 2, "")
        suite.assert_test("DN9_and_its_slab", #world:query({ with = { "ai/debug/world/slab" } }) == 2, "slabs " .. #world:query({ with = { "ai/debug/world/slab" } }))
        commands:entity(local_debug):remove("ai/debug")
        commands:entity(local_world):remove("ai/debug/world")
        step("removed here")

    elseif phase == "removed here" and since > 0.3 then
        suite.assert_test("DN10_taken_off_its_label_goes", #world:query({ with = { "ai/debug/label" } }) == 1, "")
        suite.assert_test("DN11_and_its_slab", #world:query({ with = { "ai/debug/world/slab" } }) == 1, "")
        ts.take_off = true
        step("taken off")

    elseif phase == "taken off" and since > 1 then
        suite.assert_test("DN12_an_agent_gone_takes_its_label", #world:query({ with = { "ai/debug/label" } }) == 0, "")
        suite.assert_test("DN13_a_carrier_gone_takes_its_slabs", #world:query({ with = { "ai/debug/world/slab" } }) == 0, "")
        phase = "done"
        suite.finish("DebugNetSuite")
    end

    if phase ~= "done" and since > 20 then
        suite.assert_test("DN0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        phase = "done"
        suite.finish("DebugNetSuite")
    end
end):in_set("zz/debug_net_client")
