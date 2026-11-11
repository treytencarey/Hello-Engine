-- `collider/bb`: a box collider per mesh primitive, with no transform math in Lua.
--
-- Fixture: gltf/mod_registry's markers.glb. `fx_box` is a 2 x 0.5 x 1 m box (half extents 1, .25,
-- .5 in glTF axes) on a node at (2, 1, -3), turned 30 degrees about Y and scaled 1.5 on X, carrying
-- `collider/bb`. Server side, which also shows the glTF loader gives a primitive its Aabb headless.
--
-- B1 one shape, marked `collider/bb/shape`, a child of the box's mesh primitive, and the carrier's
--    `collider.built` turns true
-- B2 the shape sits at the box's centre in world space: Rapier and Bevy compose the node's turn and
--    scale
-- B3 a dynamic body dropped on the box lands on its top
-- B4 a changed config, and a reload of the mod's file, each build it again exactly once
-- B5 removing `collider/bb` takes the shape and the base
-- B6 put on an entity that carries a loaded SceneRoot, it boxes every primitive of that scene
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")
local Collider = require("bevy_rapier3d::geometry::Collider")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("ColliderBbSuite")
local T = suite.assert_test

local FIXTURE = "modules/gltf/mod_registry/tests/fixtures/markers.glb#Scene0"

local root, direct, ball

app:add_systems(Startup, { Commands, Res[AssetServer] }, function(commands, asset_server)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    root = commands:spawn({
        SceneRoot = asset_server:load(FIXTURE),
        Transform = {},
        ["gltf/mod_registry"] = {},
    }):id()
    direct = commands:spawn({
        SceneRoot = asset_server:load(FIXTURE),
        Transform = { translation = { x = 50, y = 0, z = 0 } },
    }):id()
end)

local function box_node(world)
    for _, e in ipairs(world:query({
        iter_many = world:descendants(root),
        with = { "Name", "GltfExtras" },
        optional = { "collider", "collider/bb" },
    })) do
        if e:get("Name").name == "fx_box" then
            return e
        end
    end
end

local function shapes_under(world, id)
    return world:query({
        iter_many = world:descendants(id),
        with = { "collider/bb/shape", "Collider3d", "ChildOf" },
    })
end

local function built(e)
    local c = e and e:get("collider")
    return c ~= nil and c.built == true
end

local function near(a, b) return math.abs(a - b) < 1e-3 end

local function centred(world, shape)
    local t = world:get_entity(shape:id()).GlobalTransform:compute_transform().translation
    return near(t.x, 2) and near(t.y, 1) and near(t.z, -3), string.format("at %.3f %.3f %.3f", t.x, t.y, t.z)
end

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("collider/bb/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/bb_suite_reloads")

local phase, clock, frames = "built", 0, 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    if phase == "built" then
        local box = box_node(world)
        -- A few frames for transform propagation after the first shape.
        if built(box) and #shapes_under(world, box:id()) > 0 and frames > 10 then
            local shapes = shapes_under(world, box:id())
            T("B1_one_shape_under_the_box", #shapes == 1, "shapes " .. #shapes)
            local parent = world:query({ iter_many = { shapes[1]:get("ChildOf") }, with = { "Mesh3d", "Aabb" } })[1]
            T("B1_a_child_of_its_mesh_primitive", parent ~= nil, "parent has no Mesh3d and Aabb")
            T("B1_built_turns_true", true, "")
            T("B2_at_the_box_centre_in_world_space", centred(world, shapes[1]))
            ball = commands:spawn({
                Transform = { translation = { x = 2, y = 4, z = -3 } },
                RigidBody3d = "Dynamic",
                Collider3d = Collider.ball(0.25),
            }):id()
            step("landing")
        end

    elseif phase == "landing" and clock > 3 then
        local y = world:get_entity(ball).GlobalTransform:compute_transform().translation.y
        T("B3_a_dropped_body_lands_on_the_box", math.abs(y - 1.5) < 0.15, string.format("ball y %.3f", y))
        commands:entity(ball):despawn()
        commands:entity(box_node(world):id()):insert({ ["collider/bb"] = {} })
        step("rewritten")

    elseif phase == "rewritten" and clock > 1 then
        local box = box_node(world)
        T("B4_a_changed_config_builds_exactly_once", #shapes_under(world, box:id()) == 1 and built(box),
            "shapes " .. #shapes_under(world, box:id()) .. " built " .. tostring(built(box)))
        local path = "assets/modules/collider/bb/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloading")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloading" and reloads > 0 then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local box = box_node(world)
        local shapes = shapes_under(world, box:id())
        T("B4_a_reload_builds_exactly_once", #shapes == 1 and built(box),
            "shapes " .. #shapes .. " built " .. tostring(built(box)))
        T("B4_still_at_the_box_centre", shapes[1] ~= nil and centred(world, shapes[1]))
        commands:entity(box:id()):remove("collider/bb")
        step("removed")

    elseif phase == "removed" and clock > 1 then
        local box = box_node(world)
        T("B5_removing_it_takes_the_shape", #shapes_under(world, root) == 0, "shapes " .. #shapes_under(world, root))
        T("B5_and_the_base", not box:has("collider"), "collider stays")
        commands:entity(direct):insert({ ["collider/bb"] = {} })
        step("direct")

    elseif phase == "direct" then
        local row = world:query({ iter_many = { direct }, with = { "collider" } })[1]
        if built(row) and clock > 1 then
            local prims = world:query({ iter_many = world:descendants(direct), with = { "Mesh3d", "Aabb" } })
            local shapes = shapes_under(world, direct)
            T("B6_a_scene_carrier_boxes_every_primitive", #prims == 2 and #shapes == #prims,
                "shapes " .. #shapes .. " primitives " .. #prims)
            phase = "done"
            suite.finish("ColliderBbSuite")
        end
    end

    if phase ~= "done" and clock > 15 then
        T("B0_reached_" .. phase, false, "stuck for 15 s")
        phase = "done"
        suite.finish("ColliderBbSuite")
    end
end):in_set("zz/bb_suite")
