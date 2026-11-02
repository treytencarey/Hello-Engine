-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader
local Quat = require("bevy::math::Quat")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("SceneSuite")

local function node(commands, parent, tag, name, transform)
    commands:spawn({
        ["zz/node"] = { tag = tag },
        Name = { name = name },
        Transform = transform,
        ChildOf = parent,
    })
end

-- A source doubled in size, so a node's half extents must come from its world scale.
local function source(commands, name, x, cfg)
    return commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav/volumes/scene"] = cfg,
        ["ai/nav/volumes"] = { sample = false },
        Transform = { translation = { x = x, y = 0, z = 0 }, scale = { x = 2, y = 2, z = 2 } },
    }):id()
end

local authored, undecided, doomed

app:add_systems(Startup, { Commands, Res[AssetServer] }, function(commands, assets)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    -- A real scene: its names are as the engine gives them.
    commands:spawn({
        ["zz/name"] = { name = "glb" },
        ["ai/nav/volumes/scene"] = { include = "Armature" },
        ["ai/nav/volumes"] = { sample = false },
        Transform = { translation = { x = 500, y = 0, z = 0 } },
        SceneRoot = assets:load("Placeholder-Character/Model.glb#Scene0"),
    })
    -- Nodes with no source above them, and a source whose nodes are here before it.
    commands:spawn({ ["zz/node"] = { tag = "outside" }, Name = { name = "stray_nav" }, Transform = {} })
    undecided = commands:spawn({
        ["zz/name"] = { name = "undecided" },
        Transform = { translation = { x = 800, y = 0, z = 0 } },
    }):id()
    node(commands, undecided, "older", "room_nav", { scale = { x = 3, y = 1, z = 3 } })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/volumes", "ai/nav/volumes/scene", "Children" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function tagged(world, tag)
    for _, e in ipairs(world:query({
        with = { "zz/node" },
        optional = { "ai/nav/volume" },
    })) do
        if e:get("zz/node").tag == tag then
            return e
        end
    end
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

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 1e-3) end

local function has_volume(e) return e ~= nil and e:has("ai/nav/volume") end

-- Writes to volumes: a reload must tag nothing again.
local tags_written = 0
app:add_systems(Update, {
    Query[{
        changed = { "ai/nav/volume" },
        with = { "zz/node" },
    }],
}, function(added)
    for _ in ipairs(added:iter()) do
        tags_written = tags_written + 1
    end
end):in_set("zz/scene_suite_count")

-- The watcher says when it saw the mod's file change: this is how a case knows the reload ran.
local refills = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/nav/volumes/scene/server/init.lua", 1, true) then
            refills = refills + 1
        end
    end
end):in_set("zz/scene_suite_refills")

local phase, clock = "spawn", 0
local tags_before, refills_before = 0, 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" and clock > 0.2 then
        -- As a scene's do: they land after First, so propagation has run by this mod's next First.
        authored = source(commands, "authored", 100, {})
        node(commands, authored, "floor", "floor_nav", { translation = { x = 1, y = 0, z = 0 }, scale = { x = 5, y = 1, z = 4 } })
        node(commands, authored, "turned", "turned_nav", {
            translation = { x = 10, y = 0, z = 0 },
            rotation = Quat.from_rotation_y(math.pi / 2),
            scale = { x = 5, y = 1, z = 1 },
        })
        node(commands, authored, "wall", "wall", { scale = { x = 5, y = 1, z = 4 } })
        doomed = source(commands, "doomed", 300, {})
        node(commands, doomed, "doomed", "x_nav_y", { scale = { x = 1, y = 1, z = 1 } })
        -- a volume somebody else put there
        commands:spawn({
            ["zz/node"] = { tag = "handmade" },
            ["ai/nav/volume"] = { hx = 1, hy = 0, hz = 1 },
            Transform = {},
            ChildOf = doomed,
        })
        commands:spawn({
            ["zz/name"] = { name = "alone" },
            ["ai/nav/volumes/scene"] = {},
            Transform = { translation = { x = 900, y = 0, z = 0 } },
        })
        commands:spawn({
            ["zz/node"] = { tag = "itself" },
            ["zz/name"] = { name = "itself" },
            Name = { name = "own_nav" },
            ["ai/nav/volumes/scene"] = {},
            ["ai/nav/volumes"] = { sample = false },
            Transform = { translation = { x = 700, y = 0, z = 0 } },
        })
        step("tagged")

    elseif phase == "tagged" and has_volume(tagged(world, "floor")) and #regions_of(world, "authored") >= 2 then
        suite.assert_test("SC1b_it_brings_its_base", named(world, "alone"):has("ai/nav/volumes"), "")
        suite.assert_test("SC1_include_defaults_to_nav",
            named(world, "authored"):get("ai/nav/volumes/scene").include == "_nav", "")
        local v = tagged(world, "floor"):get("ai/nav/volume")
        suite.assert_test("SC2_a_matching_nodes_half_extents_are_its_world_scale",
            near(v.hx, 10) and near(v.hy, 2) and near(v.hz, 8),
            string.format("%s %s %s", tostring(v.hx), tostring(v.hy), tostring(v.hz)))
        local turned = tagged(world, "turned"):get("ai/nav/volume")
        suite.assert_test("SC3_a_turned_nodes_box_is_the_axis_aligned_one_around_it",
            near(turned.hx, 2) and near(turned.hz, 10), string.format("%s %s", tostring(turned.hx), tostring(turned.hz)))
        suite.assert_test("SC4_a_name_that_does_not_match_gets_none", not has_volume(tagged(world, "wall")), "")
        suite.assert_test("SC5_a_name_with_it_anywhere_matches", has_volume(tagged(world, "doomed")), "")
        suite.assert_test("SC6_a_node_under_no_source_gets_none", not has_volume(tagged(world, "outside")), "")
        suite.assert_test("SC7_the_source_itself_counts", has_volume(tagged(world, "itself")), "")
        local found = false
        for _, r in ipairs(regions_of(world, "authored")) do
            found = found or (near(r.min_x, 102 - 10) and near(r.max_x, 102 + 10) and near(r.min_z, -8) and near(r.max_z, 8))
        end
        suite.assert_test("SC8_it_bakes_where_the_node_is_in_the_world", found, "regions " .. #regions_of(world, "authored"))
        commands:entity(undecided):insert({
            ["ai/nav/volumes/scene"] = {},
            ["ai/nav/volumes"] = { sample = false },
        })
        step("older")

    elseif phase == "older" and has_volume(tagged(world, "older")) then
        suite.assert_test("SC9_nodes_older_than_the_source_are_found", tagged(world, "older"):get("ai/nav/volume").hx == 3, "")
        node(commands, authored, "late", "late_nav", { scale = { x = 1, y = 1, z = 1 } })
        step("late")

    elseif phase == "late" and has_volume(tagged(world, "late")) then
        suite.assert_test("SC10_a_node_arriving_later_is_found", true, "")
        step("real scene")

    elseif phase == "real scene" and #regions_of(world, "glb") > 0 then
        local r = regions_of(world, "glb")
        suite.assert_test("SC11_a_real_scenes_node_is_found_by_its_name",
            #r == 1 and r[1].min_x < 500 and r[1].max_x > 500, "regions " .. #r)
        tags_before = tags_written
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/nav/volumes/scene/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        step("after reload")

    elseif phase == "after reload" and clock > 1 then
        suite.assert_test("SC12_a_reload_tags_nothing_again", tags_written == tags_before,
            "tagged " .. (tags_written - tags_before))
        suite.assert_test("SC13_a_reload_keeps_the_tags", has_volume(tagged(world, "floor")), "")
        commands:entity(doomed):remove("ai/nav/volumes/scene")
        step("removed")

    -- The base stays, as it was given, and bakes once the settle is over.
    elseif phase == "removed" and clock > 0.8 then
        local d = tagged(world, "doomed")
        suite.assert_test("SC14_removing_it_takes_the_tags_and_leaves_the_nodes", d ~= nil and not has_volume(d), "")
        suite.assert_test("SC14b_a_volume_it_did_not_add_stays", has_volume(tagged(world, "handmade")), "")
        suite.assert_test("SC16_the_others_keep_theirs", has_volume(tagged(world, "floor")), "")
        phase = "done"
        suite.finish("SceneSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("SC0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("SceneSuite")
    end
end):in_set("zz/scene_suite")
