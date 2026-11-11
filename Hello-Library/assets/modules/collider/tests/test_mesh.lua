-- `collider/mesh`: a static trimesh from the carrier's own geometry, which a body lands on.
--
-- Fixture: a copy of gltf/mod_registry's markers.glb, through `gltf/mod_registry`. `fx_floor` is a
-- 4 x 4 x 0.2 m slab, its top at y = 0, centred on x = 10, carrying `collider/mesh`. Server side.
--
-- M1 the slab gets one shape, marked `collider/mesh/shape`, a child of its mesh primitive, and
--    the carrier's `collider.built` turns true
-- M2 a dynamic ball dropped onto it comes to rest on it
-- M3 a changed config, and a reload of the mod's file, each build it again exactly once: one
--    shape, built, the ball still on it
-- M4 a re-export builds the new slab: one shape in all, on the new node, the ball still on it
-- M5 removing `collider/mesh` takes the shape and the base: the ball falls through, the mesh stays
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")
local Collider = require("bevy_rapier3d::geometry::Collider")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("ColliderMeshSuite")
local T = suite.assert_test

local SOURCE = read_file_bytes("assets/modules/gltf/mod_registry/tests/fixtures/markers.glb")
local COPY = "modules/collider/tests/zz_mesh_copy.glb"
write_file_bytes("assets/" .. COPY, SOURCE)

local root, ball

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function floor_node(world)
    for _, e in ipairs(world:query({
        iter_many = world:descendants(root),
        with = { "Name", "GltfExtras" },
        optional = { "collider", "collider/mesh" },
    })) do
        if e:get("Name").name == "fx_floor" then
            return e
        end
    end
end

local function shapes_under(world, e)
    return world:query({
        iter_many = world:descendants(e:id()),
        with = { "collider/mesh/shape", "Collider3d", "ChildOf" },
    })
end

local function built(e)
    local c = e and e:get("collider")
    return c ~= nil and c.built == true
end

local function ball_y(world)
    return world:get_entity(ball).GlobalTransform:compute_transform().translation.y
end

local function resting(world)
    return math.abs(ball_y(world) - 0.25) < 0.15
end

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("collider/mesh/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/mesh_suite_reloads")

local phase, clock, frames = "wait", 0, 0
local first_floor

app:add_systems(Update, { World, Commands, Res[AssetServer] }, function(world, commands, asset_server)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    -- Bevy's watcher reports the copy's creation a moment later, and a scene loaded by then
    -- would respawn once.
    if phase == "wait" and clock > 1.5 then
        root = commands:spawn({
            SceneRoot = asset_server:load(COPY .. "#Scene0"),
            Transform = {},
            ["gltf/mod_registry"] = {},
        }):id()
        step("built")

    elseif phase == "built" then
        local floor = floor_node(world)
        if built(floor) and #shapes_under(world, floor) > 0 and frames > 10 then
            local shapes = shapes_under(world, floor)
            T("M1_one_shape_under_the_slab", #shapes == 1, "shapes " .. #shapes)
            local parent = world:query({ iter_many = { shapes[1]:get("ChildOf") }, with = { "Mesh3d" } })[1]
            T("M1_a_child_of_its_mesh_primitive", parent ~= nil, "parent has no Mesh3d")
            T("M1_built_turns_true", true, "")
            first_floor = floor:id()
            ball = commands:spawn({
                Transform = { translation = { x = 10, y = 3, z = 0 } },
                RigidBody3d = "Dynamic",
                Collider3d = Collider.ball(0.25),
            }):id()
            step("dropped")
        end

    elseif phase == "dropped" and clock > 3 then
        T("M2_a_dropped_body_rests_on_the_slab", resting(world), string.format("ball y %.3f", ball_y(world)))
        commands:entity(floor_node(world):id()):insert({ ["collider/mesh"] = {} })
        step("rewritten")

    elseif phase == "rewritten" and clock > 1 then
        local floor = floor_node(world)
        T("M3_a_changed_config_builds_exactly_once", #shapes_under(world, floor) == 1 and built(floor),
            "shapes " .. #shapes_under(world, floor) .. " built " .. tostring(built(floor)))
        local path = "assets/modules/collider/mesh/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloading")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloading" and reloads > 0 then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local floor = floor_node(world)
        T("M3_a_reload_builds_exactly_once", #shapes_under(world, floor) == 1 and built(floor),
            "shapes " .. #shapes_under(world, floor) .. " built " .. tostring(built(floor)))
        T("M3_the_ball_stays_on_it", resting(world), string.format("ball y %.3f", ball_y(world)))
        -- Same length, so the binary chunk's offsets stay right.
        write_file_bytes("assets/" .. COPY, (SOURCE:gsub("fx/json", "fx/nosj")))
        step("reexported")

    elseif phase == "reexported" then
        local floor = floor_node(world)
        if floor and floor:id() ~= first_floor and built(floor) and clock > 2 then
            T("M4_a_reexport_builds_the_new_slab",
                #shapes_under(world, floor) == 1 and #world:query({ with = { "collider/mesh/shape" } }) == 1,
                "shapes " .. #world:query({ with = { "collider/mesh/shape" } }))
            T("M4_the_ball_stays_on_it", resting(world), string.format("ball y %.3f", ball_y(world)))
            commands:entity(floor:id()):remove("collider/mesh")
            step("removed")
        end

    elseif phase == "removed" and (ball_y(world) < -2 or clock > 5) then
        local floor = floor_node(world)
        T("M5_removing_it_takes_the_shape", #world:query({ with = { "collider/mesh/shape" } }) == 0,
            "shapes " .. #world:query({ with = { "collider/mesh/shape" } }))
        T("M5_and_the_base", floor ~= nil and not floor:has("collider"), "collider stays")
        T("M5_the_ball_falls_through", ball_y(world) < -2, string.format("ball y %.3f", ball_y(world)))
        T("M5_the_mesh_stays", #world:query({ iter_many = world:descendants(floor:id()), with = { "Mesh3d" } }) == 1,
            "mesh gone")
        os.remove("assets/" .. COPY)
        phase = "done"
        suite.finish("ColliderMeshSuite")
    end

    if phase ~= "done" and clock > 15 then
        T("M0_reached_" .. phase, false, "stuck for 15 s")
        os.remove("assets/" .. COPY)
        phase = "done"
        suite.finish("ColliderMeshSuite")
    end
end):in_set("zz/mesh_suite")
