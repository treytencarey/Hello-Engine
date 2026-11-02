-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("BoxSuite")

-- As a map: a fixed ground with the box on the same entity, top at y = 0.
local function map(commands, name, x, box)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav/volumes/box"] = box,
        Transform = { translation = { x = x, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 30, hy = 0.5, hz = 30 } },
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    map(commands, "plain", 0, { hx = 5, hz = 4, y = 0.5 })
    map(commands, "offset", 200, { hx = 2, hz = 2, hy = 1, x = 10, y = 1.5, z = -6 })
    map(commands, "unsized", 400, { hz = 4 })
    map(commands, "doomed", 600, { hx = 2, hz = 2, y = 0.5 })
    commands:spawn({ ["zz/name"] = { name = "scout" }, ["ai/nav"] = {} })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/volumes", "ai/nav/volumes/box", "Children" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function volumes_of(world, name)
    return world:query({
        iter_many = named(world, name):get("Children") or {},
        with = { "ai/nav/volumes/box/volume", "ai/nav/volume", "Transform" },
    })
end

local function regions_of(world, name)
    local out = {}
    for _, r in ipairs(world:query({
        iter_many = named(world, name):get("Children") or {},
        with = { "ai/nav/region" },
    })) do
        out[#out + 1] = r:get("ai/nav/region")
    end
    return out
end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 0.01) end

-- The watcher says when it saw the mod's file change: this is how a case knows the reload ran.
local refills = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/nav/volumes/box/server/init.lua", 1, true) then
            refills = refills + 1
        end
    end
end):in_set("zz/box_suite_refills")

local phase, clock = "baked", 0
local refills_before, child_before = 0, nil

app:add_systems(Update, { World, Res[Time], Res["ai/nav/graph"], Commands }, function(world, time, graph, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "baked" and #regions_of(world, "plain") > 0 and #regions_of(world, "offset") > 0 then
        local plain = named(world, "plain")
        local cfg = plain:get("ai/nav/volumes/box")
        suite.assert_test("B1_missing_fields_get_defaults", cfg.hy == 0 and cfg.x == 0 and cfg.z == 0 and cfg.y == 0.5, "")
        suite.assert_test("B2_it_brings_the_base_with_its_defaults",
            plain:has("ai/nav/volumes") and plain:get("ai/nav/volumes").cell == 1, "")
        local children = volumes_of(world, "plain")
        local volume = children[1]:get("ai/nav/volume")
        suite.assert_test("B3_one_child_holds_the_volume_of_its_size",
            #children == 1 and volume.hx == 5 and volume.hz == 4 and volume.hy == 0, "children " .. #children)
        local r = regions_of(world, "plain")
        suite.assert_test("B4_it_bakes_to_a_region_of_its_size_on_the_ground",
            #r == 1 and r[1].min_x == -5 and r[1].max_x == 5 and r[1].min_z == -4 and r[1].max_z == 4 and near(r[1].y, 0),
            "regions " .. #r)
        -- entity at x = 200, box 10 along and 6 back from it, half size 2; floor at its bottom
        local o = regions_of(world, "offset")
        suite.assert_test("B5_it_sits_where_it_says_relative_to_its_entity",
            #o == 1 and o[1].min_x == 208 and o[1].max_x == 212 and o[1].min_z == -8 and o[1].max_z == -4 and near(o[1].y, 0),
            "regions " .. #o .. string.format(" x %s..%s", tostring(o[1] and o[1].min_x), tostring(o[1] and o[1].max_x)))
        suite.assert_test("B6_without_its_size_there_is_no_child",
            #volumes_of(world, "unsized") == 0 and #regions_of(world, "unsized") == 0, "")
        local ok, g = pcall(function() return graph:get() end)
        local seen = false
        for _, region in ipairs(ok and g.regions or {}) do
            seen = seen or (region.min_x == 208 and region.max_x == 212)
        end
        suite.assert_test("B7_its_region_reaches_the_graph", seen, "")
        child_before = children[1]:id()
        plain:patch({ ["ai/nav/volumes/box"] = { hx = 8 } })
        step("resized")

    elseif phase == "resized" and #regions_of(world, "plain") == 1 and regions_of(world, "plain")[1].max_x == 8 then
        local children = volumes_of(world, "plain")
        suite.assert_test("B8_a_change_moves_the_same_child_and_rebakes",
            #children == 1 and children[1]:id() == child_before and children[1]:get("ai/nav/volume").hx == 8, "")
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/nav/volumes/box/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        step("after reload")

    elseif phase == "after reload" and clock > 1.5 then
        local children = volumes_of(world, "plain")
        local r = regions_of(world, "plain")
        suite.assert_test("B9_after_a_reload_it_has_one_child_and_one_region_as_given",
            #children == 1 and children[1]:get("ai/nav/volume").hx == 8 and #r == 1 and r[1].max_x == 8,
            string.format("children %d regions %d", #children, #r))
        commands:entity(named(world, "doomed"):id()):remove("ai/nav/volumes/box")
        step("removed")

    elseif phase == "removed" and clock > 0.5 then
        suite.assert_test("B10_removing_it_takes_its_child_its_base_and_its_regions",
            #volumes_of(world, "doomed") == 0 and #regions_of(world, "doomed") == 0
                and not named(world, "doomed"):has("ai/nav/volumes"),
            string.format("volumes %d regions %d", #volumes_of(world, "doomed"), #regions_of(world, "doomed")))
        suite.assert_test("B11_the_others_keep_theirs", #regions_of(world, "plain") == 1, "")
        phase = "done"
        suite.finish("BoxSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("B0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("BoxSuite")
    end
end):in_set("zz/box_suite")
