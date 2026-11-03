-- --host
-- What the server half publishes, from the entities and nothing else: no `ai/nav` is here at all.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("DebugWorldSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/carrier"] = {}, ["ai/debug/world"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["zz/region"] = { name = "a" }, ["ai/nav/region"] = { min_x = 0, max_x = 4, min_z = 0, max_z = 4, y = 1 }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/region"] = { name = "b" }, ["ai/nav/region"] = { min_x = 4, max_x = 8, min_z = 0, max_z = 4, y = 1 }, ["core/net/sync"] = false })
    commands:spawn({
        ["ai/nav/link"] = { from = { x = 1, y = 1, z = 1 }, to = { x = 20, y = 1, z = 1 }, x = 10, y = 1, z = 1 },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/volume"] = {},
        ["ai/nav/volume"] = { hx = 2, hy = 1, hz = 3 },
        Transform = { translation = { x = 10, y = 5, z = 20 } },
        ["core/net/sync"] = false,
    })
end)

local function world_of(world)
    return world:query({ with = { "zz/carrier", "ai/debug/world" } })[1]:get("ai/debug/world")
end

local writes = 0
app:add_systems(Update, {
    Query[{
        changed = { "ai/debug/world" },
        with = { "zz/carrier" },
    }],
}, function(changed)
    for _ in ipairs(changed:iter()) do
        writes = writes + 1
    end
end):in_set("zz/debug_world_suite_writes")

local function region(world, name)
    for _, e in ipairs(world:query({ with = { "zz/region" } })) do
        if e:get("zz/region").name == name then
            return e
        end
    end
end

local phase, clock = "published", 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "published" and clock > 0.5 then
        local w = world_of(world)
        suite.assert_test("W1_it_lists_the_regions", #w.regions == 2 and w.regions[1].max_x == 4 and w.regions[1].y == 1, "")
        suite.assert_test("W2_and_links", #w.links == 1 and w.links[1].to.x == 20 and w.links[1].x == 10, "")
        suite.assert_test("W3_regions_that_touch_add_no_link", #w.links == 1, "")
        suite.assert_test("W4_and_volumes_where_they_stand",
            #w.volumes == 1 and w.volumes[1].min_x == 8 and w.volumes[1].max_x == 12 and w.volumes[1].min_y == 4 and w.volumes[1].max_z == 23,
            w.volumes[1] and tostring(w.volumes[1].min_x) or "none")
        writes = 0
        step("standing")

    elseif phase == "standing" and clock > 0.5 then
        suite.assert_test("W5_a_level_that_stands_still_writes_nothing", writes == 0, "writes " .. writes)
        region(world, "a"):patch({ ["ai/nav/region"] = { max_x = 3 } })
        step("changed")

    elseif phase == "changed" and clock > 0.2 then
        suite.assert_test("W6_a_changed_region_shows", world_of(world).regions[1].max_x == 3, "")
        commands:entity(region(world, "b"):id()):despawn()
        step("region gone")

    elseif phase == "region gone" and clock > 0.2 then
        suite.assert_test("W7_a_region_gone_goes_and_the_list_closes_up", #world_of(world).regions == 1, "regions " .. #world_of(world).regions)
        commands:entity(world:query({ with = { "ai/nav/link" } })[1]:id()):despawn()
        step("link gone")

    elseif phase == "link gone" and clock > 0.2 then
        suite.assert_test("W8_a_link_gone_goes", #world_of(world).links == 0, "")
        commands:entity(world:query({ with = { "zz/volume" } })[1]:id()):despawn()
        step("volume gone")

    elseif phase == "volume gone" and clock > 0.2 then
        suite.assert_test("W9_a_volume_gone_goes", #world_of(world).volumes == 0, "")
        -- A box spawns its volume in First, a frame before anything has worked out where it stands.
        commands:spawn({
            ["ai/nav/volumes"] = { sample = false },
            ["ai/nav/volumes/box"] = { hx = 3, hz = 3 },
            Transform = { translation = { x = 50, y = 0, z = 0 } },
            ["core/net/sync"] = false,
        })
        step("box")

    elseif phase == "box" and clock > 2.5 then
        local v = world_of(world).volumes[1]
        suite.assert_test("W10_a_box_is_drawn_where_it_stands", v ~= nil and v.min_x == 47, v and tostring(v.min_x) or "none")
        commands:spawn({ ["zz/late"] = {}, ["ai/debug/world"] = {}, ["core/net/sync"] = false })
        step("late carrier")

    -- Long enough after the box that nothing else is arriving.
    elseif phase == "late carrier" and clock > 0.3 then
        local late = world:query({ with = { "zz/late", "ai/debug/world" } })[1]:get("ai/debug/world")
        suite.assert_test("W11_a_new_carrier_is_told", #(late.volumes or {}) == 1, tostring(#(late.volumes or {})))
        phase = "done"
        suite.finish("DebugWorldSuite")
    end

    if phase ~= "done" and clock > 8 then
        suite.assert_test("W0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 8 s")
        phase = "done"
        suite.finish("DebugWorldSuite")
    end
end):in_set("zz/debug_world_suite")
