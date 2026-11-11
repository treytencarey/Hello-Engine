-- --host
-- What the placing ray meets, headless, on a client: this client's player points with a ray, as
-- the VR pointer's comes, at a ground that is only a collider. A shelf that is only a mesh stands
-- halfway along it; its top is at y = 0.85.
--
--   R1 with nothing else in the way it lands on the collider
--   R2 a visible mesh with no collider in the way is hit: it lands on the mesh
--   R3 a mesh that is not pickable (`Pickable.is_hoverable = false`) is passed: it lands behind it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local Cuboid = require("bevy::math::primitives::Cuboid")
local Vec3 = require("bevy::math::Vec3")

local suite = helpers.create_suite("PlacementRaysSuite")
local T = suite.assert_test

local HAND = { x = 0, y = 1.5, z = 0 }
local GROUND = { x = 0, y = 0, z = -1.5 }
local SHELF = { x = 0, y = 0.85, z = -0.65 }

app:add_systems(Startup, { ResMut[Assets[Mesh]], Commands }, function(meshes, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    -- Off the ray until R2 moves it onto it.
    commands:spawn({
        ["zz/pr/shelf"] = {},
        Mesh3d = meshes:add(Cuboid.new(2, 0.2, 2)),
        Transform = { translation = { x = 50, y = 0.75, z = -0.75 } },
        Visibility = "Inherited",
        -- What a window's visibility and `calculate_bounds` systems give it; a ray is culled by both.
        InheritedVisibility = true,
        Aabb = { center = { x = 0, y = 0, z = 0 }, half_extents = { x = 1, y = 0.1, z = 1 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        Collider3d = { cuboid = { hx = 50, hy = 0.5, hz = 50 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/pr/me"] = {},
        input = {},
        ["core/net/local"] = {},
        ["vr/pointer/ray"] = { origin = HAND, direction = Vec3.normalize(Vec3.sub(GROUND, HAND)) },
        Transform = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/pr/placed"] = {},
        placement = {},
        ["core/net/local"] = {},
        Transform = { translation = { x = 5, y = 0, z = 5 } },
        ["core/net/sync"] = false,
    })
end)

local function at(world)
    local e = world:query({ with = { "zz/pr/placed" }, optional = { "Transform" } })[1]
    return e and e:get("Transform").translation
end

local function near(p, q)
    return p ~= nil and Vec3.distance(p, q) < 0.05
end

local function show(p)
    return p and string.format("%.2f %.2f %.2f", p.x, p.y, p.z) or "none"
end

local phase, clock = "ground", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "ground" and (near(at(world), GROUND) or clock > 5) then
        T("R1_with_nothing_else_in_the_way_it_lands_on_the_collider", near(at(world), GROUND), show(at(world)))
        local shelf = world:query({ with = { "zz/pr/shelf" } })[1]
        commands:entity(shelf:id()):insert({ Transform = { translation = { x = 0, y = 0.75, z = -0.75 } } })
        step("shelf")

    elseif phase == "shelf" and (near(at(world), SHELF) or clock > 5) then
        T("R2_a_visible_mesh_with_no_collider_in_the_way_is_hit", near(at(world), SHELF), show(at(world)))
        local shelf = world:query({ with = { "zz/pr/shelf" } })[1]
        commands:entity(shelf:id()):insert({ Pickable = { is_hoverable = false, should_block_lower = false } })
        step("unpickable")

    elseif phase == "unpickable" and (near(at(world), GROUND) or clock > 5) then
        T("R3_a_mesh_that_is_not_pickable_is_passed", near(at(world), GROUND), show(at(world)))
        phase = "done"
        suite.finish("PlacementRaysSuite")
    end
end):in_set("zz/placement_rays")
