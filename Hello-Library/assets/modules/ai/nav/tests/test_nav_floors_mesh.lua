-- --host
-- The building of test_nav_floors.lua, its slabs real meshes with rapier's colliders from them, baked
-- and walked. Closed, every part a box of triangles; open, the floors single-sided planes; value, a
-- closed one by `Collider.from_bevy_mesh`; and the cuboids to compare. A trimesh is only a surface:
-- it has no inside, so a ray from within goes on to the next face it finds, and one from below or
-- above hits a plane alike. So it is its sides that keep the ground under a wall from being a floor,
-- and those are looked at here too: a wall too thin for a cell's centre to land in it.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")
local Time = require("bevy::time::Time")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local Cuboid = require("bevy::math::primitives::Cuboid")
local Plane3d = require("bevy::math::primitives::Plane3d")
local Collider = require("bevy_rapier3d::geometry::Collider")
local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")

local suite = helpers.create_suite("NavFloorsMeshSuite")

local SLOPE = math.atan(0.4)
local RAMP_LENGTH = math.sqrt(116)
local UP = { x = 0, y = 1, z = 0 }

local function volume(commands, name, at, hx, hz, hy, y)
    commands:spawn({
        ["zz/name"] = { name = name, at = at },
        ["ai/nav/volumes/box"] = { hx = hx, hz = hz, hy = hy, y = y },
        Transform = { translation = { x = at, y = 0, z = 0 } },
    })
end

local function agent(commands, name, x, y, z)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav"] = {},
        ["ai/steering"] = { speed = 4 },
        Transform = { translation = { x = x, y = y, z = z } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
    })
end

local function people(commands, name, at)
    agent(commands, name .. " climber", at, 1, 4)
    agent(commands, name .. " descender", at - 5, 5, -3)
end

-- A part of a building, as each kind makes it.
local function box_maker(commands, meshes, extra)
    return function(x, y, z, hx, hy, hz, rotation)
        local bundle = {
            Transform = { translation = { x = x, y = y, z = z }, rotation = rotation },
            RigidBody3d = "Fixed",
            Mesh3d = meshes:add(Cuboid.new(hx * 2, hy * 2, hz * 2)),
        }
        for k, v in pairs(extra) do
            bundle[k] = v
        end
        commands:spawn(bundle)
    end
end

local function building(part, at)
    part(at, -0.5, 0, 35, 0.5, 25)
    part(at, 3.9, 0, 10, 0.1, 6)
    part(at + 15 - 0.1 * math.sin(SLOPE), 2 - 0.1 * math.cos(SLOPE), 0, RAMP_LENGTH / 2, 0.1, 2, Quat.from_rotation_z(-SLOPE))
    part(at + 15, 3, 2.5, 5, 3, 0.5)
    part(at + 15, 3, -2.5, 5, 3, 0.5)
    part(at - 20, 2, 0, 5, 0.5, 5)
end

-- Only upward-facing planes, as a floor modelled single-sided: nothing has an underside at all.
local function plane_building(commands, meshes, at)
    local function plane(x, y, z, hx, hz, rotation)
        commands:spawn({
            Transform = { translation = { x = x, y = y, z = z }, rotation = rotation },
            RigidBody3d = "Fixed",
            Mesh3d = meshes:add(Plane3d.new(UP, { x = hx, y = hz })),
            AsyncCollider = "TriMesh",
        })
    end
    plane(at, 0, 0, 35, 25)
    plane(at, 4, 0, 10, 6)
    plane(at + 15, 2, 0, RAMP_LENGTH / 2, 2, Quat.from_rotation_z(-SLOPE))
    plane(at - 20, 1.5, 0, 5, 5)
    -- Walls stand edge-on to a ray straight down, so they are boxes: a capsule cannot climb a ramp's bare side.
    box_maker(commands, meshes, { AsyncCollider = "TriMesh" })(at + 15, 3, 2.5, 5, 3, 0.5)
    box_maker(commands, meshes, { AsyncCollider = "TriMesh" })(at + 15, 3, -2.5, 5, 3, 0.5)
end

local value_parts = {}

app:add_systems(Startup, { Commands, ResMut[Assets[Mesh]] }, function(commands, meshes)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })

    building(box_maker(commands, meshes, { AsyncCollider = "TriMesh" }), 0)
    volume(commands, "closed", 0, 30, 20, 3, 3)
    people(commands, "closed", 0)

    plane_building(commands, meshes, 200)
    volume(commands, "open", 200, 30, 20, 3, 3)
    people(commands, "open", 200)

    -- The collider is a value, once its mesh is there, as a mod inserts it.
    building(function(x, y, z, hx, hy, hz, rotation)
        local mesh = meshes:add(Cuboid.new(hx * 2, hy * 2, hz * 2))
        local e = commands:spawn({
            Transform = { translation = { x = x, y = y, z = z }, rotation = rotation },
            RigidBody3d = "Fixed",
            Mesh3d = mesh,
        }):id()
        value_parts[#value_parts + 1] = { entity = e, mesh = mesh }
    end, 400)
    volume(commands, "value", 400, 30, 20, 3, 3)
    people(commands, "value", 400)

    building(function(x, y, z, hx, hy, hz, rotation)
        commands:spawn({
            Transform = { translation = { x = x, y = y, z = z }, rotation = rotation },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = hx, hy = hy, hz = hz } },
        })
    end, 600)
    volume(commands, "cuboid", 600, 30, 20, 3, 3)

    -- A block as tall as a room, standing on the ground, each kind of collider.
    for _, kind in ipairs({
        { "closed block", 800, { AsyncCollider = "TriMesh" } },
        { "hull block", 900, { AsyncCollider = "ConvexHull" } },
        { "cuboid block", 1000, { Collider3d = { cuboid = { hx = 3, hy = 1.5, hz = 3 } } } },
    }) do
        local at = kind[2]
        box_maker(commands, meshes, kind[3])(at, 1.5, 0, 3, 1.5, 3)
        commands:spawn({
            Transform = { translation = { x = at, y = -0.5, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 12, hy = 0.5, hz = 12 } },
        })
        volume(commands, kind[1], at, 8, 8, 3, 3)
    end

    agent(commands, "outside the block", 806, 1, 0)

    -- A wall across the ground with a way round each end, too thin for any cell's centre to be inside it,
    -- 0.2 m beyond one row of centres. And a kerb a step can't climb, too low for the wall look to see.
    local function ground(at)
        commands:spawn({
            Transform = { translation = { x = at, y = -0.5, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 12, hy = 0.5, hz = 12 } },
        })
    end
    ground(1200)
    commands:spawn({
        Transform = { translation = { x = 1200, y = 1.5, z = 0.3 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 4, hy = 1.5, hz = 0.1 } },
    })
    commands:spawn({
        Transform = { translation = { x = 1205.3, y = 0.15, z = 5 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 0.1, hy = 0.15, hz = 2 } },
    })
    volume(commands, "thin wall", 1200, 8, 8, 3, 3)
    agent(commands, "round the wall", 1200, 1, -3)
    ground(1300)
    commands:spawn({
        Transform = { translation = { x = 1300, y = 1.5, z = 0.3 }, rotation = Quat.from_rotation_x(math.pi / 2) },
        RigidBody3d = "Fixed",
        Mesh3d = meshes:add(Plane3d.new(UP, { x = 4, y = 1.5 })),
        AsyncCollider = "TriMesh",
    })
    volume(commands, "sheet", 1300, 8, 8, 3, 3)
    agent(commands, "round the sheet", 1300, 1, -3)
    -- Something loose standing in a cell while it bakes is no wall.
    ground(1400)
    commands:spawn({
        Transform = { translation = { x = 1400.3, y = 1, z = 0.5 } },
        RigidBody3d = "Dynamic",
        Collider3d = { cuboid = { hx = 0.1, hy = 1, hz = 0.1 } },
        LockedAxes3d = "ROTATION_LOCKED",
    })
    volume(commands, "crate", 1400, 8, 8, 3, 3)
    -- A short wall 0.2 m off a cell's centre, one on each side of its own centre.
    ground(1500)
    for _, wall in ipairs({ { -5.3, -5.5, 0.1, 0.45 }, { 5.3, -5.5, 0.1, 0.45 }, { -5.5, 5.7, 0.45, 0.1 }, { 5.5, 5.3, 0.45, 0.1 } }) do
        commands:spawn({
            Transform = { translation = { x = 1500 + wall[1], y = 1.5, z = wall[2] } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = wall[3], hy = 1.5, hz = wall[4] } },
        })
    end
    volume(commands, "four walls", 1500, 8, 8, 3, 3)
    -- A thin wall under a roof: a cell beside it still has its neighbour's ground to step to, though the
    -- roof's top is the only other floor over there.
    ground(1600)
    commands:spawn({
        Transform = { translation = { x = 1600, y = 3.05, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 10, hy = 0.05, hz = 10 } },
    })
    commands:spawn({
        Transform = { translation = { x = 1600, y = 1.5, z = 0.3 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 4, hy = 1.5, hz = 0.1 } },
    })
    volume(commands, "roofed wall", 1600, 8, 8, 3, 3)
end)

app:add_systems(First, { Commands }, function(commands)
    for i = #value_parts, 1, -1 do
        local part = value_parts[i]
        local collider = Collider.from_bevy_mesh(part.mesh, "TriMesh")
        if collider ~= nil then
            commands:entity(part.entity):insert({ Collider3d = collider })
            table.remove(value_parts, i)
        end
    end
end):in_set("zz/nav_floors_mesh_suite_values")

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/request", "ai/nav/path", "ai/nav/volumes/due", "ai/nav/volumes/job", "ai/steering/state", "Transform", "Children" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function regions_of(world, name)
    return world:query({
        iter_many = named(world, name):get("Children") or {},
        with = { "ai/nav/volumes/region", "ai/nav/region" },
    })
end

local function baked(world, name)
    local e = named(world, name)
    return e ~= nil and not e:has("ai/nav/volumes/due") and not e:has("ai/nav/volumes/job") and #regions_of(world, name) > 0
end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 0.05) end

-- The floor at a height over a point of one building.
local function floor_at(world, name, x, z, y, tolerance)
    for _, r in ipairs(regions_of(world, name)) do
        local v = r:get("ai/nav/region")
        if x > v.min_x and x < v.max_x and z > v.min_z and z < v.max_z and near(v.y, y, tolerance or 0.3) then
            return v
        end
    end
end

local function ask(commands, world, name, x, y, z)
    commands:entity(named(world, name):id()):patch({ ["ai/nav/request"] = { go = { to = { x = x, y = y, z = z } } } })
end

local function status_of(world, name)
    return (named(world, name):get("ai/steering/state") or {}).status
end

-- The heights a ray straight down finds at a point, each from just under the last.
local function heights(rapier, x, z, from, solid)
    local found = {}
    local y = from
    while #found < 8 do
        local hit = rapier:cast_ray({ x = x, y = y, z = z }, { x = 0, y = -1, z = 0 }, y + 3, solid, { flags = "ONLY_FIXED" })
        if hit == nil then
            break
        end
        found[#found + 1] = y - hit.toi
        y = y - hit.toi - 0.01
    end
    return found
end

local function same_heights(found, want)
    if #found ~= #want then
        return false
    end
    for i, y in ipairs(want) do
        if not near(found[i], y, 0.02) then
            return false
        end
    end
    return true
end

local function shown(found)
    local parts = {}
    for i, y in ipairs(found) do
        parts[i] = string.format("%.2f", y)
    end
    return table.concat(parts, " ")
end

-- A building's regions, written the same wherever it stands.
local function layout(world, name, at)
    local rows = {}
    for _, r in ipairs(regions_of(world, name)) do
        local v = r:get("ai/nav/region")
        rows[#rows + 1] = string.format("%g %g %g %g %.1f", v.min_x - at, v.max_x - at, v.min_z, v.max_z, math.abs(v.y))
    end
    table.sort(rows)
    return table.concat(rows, "|")
end

local BUILDINGS = { "closed", "open", "value", "cuboid" }
local MESHES = { "closed", "open", "value" }
local reach = { closed = 0, open = 0, value = 0 }
local AT = { closed = 0, open = 200, value = 400 }

app:add_systems(Update, {
    Query[{ with = { "zz/name", "ai/steering/state", "Transform" } }],
}, function(agents)
    for _, e in ipairs(agents:iter()) do
        local name = e:get("zz/name").name
        for _, kind in ipairs(MESHES) do
            if name == kind .. " climber" then
                reach[kind] = math.max(reach[kind], e:get("Transform").translation.x - AT[kind])
            end
        end
    end
end):in_set("zz/nav_floors_mesh_suite_reach")

local phase, clock = "baking", 0

app:add_systems(Update, { World, Res[Time], ReadRapierContext, Commands }, function(world, time, rapier, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    local function all_baked()
        for _, name in ipairs(BUILDINGS) do
            if not baked(world, name) then
                return false
            end
        end
        return baked(world, "closed block") and baked(world, "hull block") and baked(world, "cuboid block")
            and baked(world, "thin wall") and baked(world, "sheet") and baked(world, "crate")
            and baked(world, "four walls") and baked(world, "roofed wall")
    end

    if phase == "baking" and clock > 1 and all_baked() then
        -- Past the slab's edge the ramp's side wall would come first, so the rays are at the building's middle.
        local closed = heights(rapier, 0, 3, 8, true)
        suite.assert_test("M1_rays_a_closed_trimesh_has_a_top_and_an_underside_and_no_inside",
            same_heights(closed, { 4, 3.8, 0, -1 }), shown(closed))
        local open = heights(rapier, 200, 3, 8, true)
        suite.assert_test("M2_rays_a_single_sided_floor_is_one_height", same_heights(open, { 4, 0 }), shown(open))
        local value = heights(rapier, 400, 3, 8, true)
        suite.assert_test("M3_rays_a_collider_made_as_a_value_is_the_same", same_heights(value, { 4, 3.8, 0, -1 }), shown(value))
        local inside = rapier:cast_ray({ x = 0, y = 3.9, z = 3 }, { x = 0, y = -1, z = 0 }, 1, true, { flags = "ONLY_FIXED" })
        suite.assert_test("M4_rays_a_solid_ray_inside_a_trimesh_does_not_stop_where_it_starts", inside ~= nil and near(inside.toi, 0.1, 0.01), "")
        local cuboid = rapier:cast_ray({ x = 600, y = 3.9, z = 3 }, { x = 0, y = -1, z = 0 }, 1, true, { flags = "ONLY_FIXED" })
        suite.assert_test("M5_rays_a_solid_ray_inside_a_cuboid_does", cuboid ~= nil and near(cuboid.toi, 0, 0.001), "")
        local back = rapier:cast_ray({ x = 200, y = 2, z = 3 }, { x = 0, y = 1, z = 0 }, 4, true, { flags = "ONLY_FIXED" })
        suite.assert_test("M6_rays_a_single_sided_floor_is_hit_from_below_too", back ~= nil and near(back.toi, 2, 0.01), "")

        for _, name in ipairs(MESHES) do
            local at = AT[name]
            local ground, upper = floor_at(world, name, at, 0, 0), floor_at(world, name, at, 0, 4)
            suite.assert_test("M7_" .. name .. "_each_storey_is_a_region_over_the_same_point", ground ~= nil and upper ~= nil, "")
            suite.assert_test("M8_" .. name .. "_no_floor_at_a_slabs_underside", floor_at(world, name, at, 0, 3.8, 0.1) == nil, "")
            suite.assert_test("M9_" .. name .. "_a_lid_too_low_leaves_no_floor_under_it", floor_at(world, name, at - 20, 0, 0) == nil, "")
            suite.assert_test("M10_" .. name .. "_the_ground_runs_on_past_the_slab",
                ground ~= nil and ground.max_z > 6, "")
            local spans_ok = true
            for _, r in ipairs(regions_of(world, name)) do
                local v = r:get("ai/nav/region")
                spans_ok = spans_ok and v.min_y <= v.y and v.y <= v.max_y and v.max_y - v.min_y <= 0.46
            end
            suite.assert_test("M11_" .. name .. "_each_region_is_a_step_apart_at_most", spans_ok, "")
        end

        local counts = {}
        for _, name in ipairs(BUILDINGS) do
            counts[name] = #regions_of(world, name)
        end
        suite.assert_test("M12_a_closed_trimesh_bakes_what_the_cuboids_bake", counts.closed == counts.cuboid, counts.closed .. " and " .. counts.cuboid)
        suite.assert_test("M12b_region_for_region", layout(world, "closed", 0) == layout(world, "cuboid", 600), "")
        suite.assert_test("M13_a_value_bakes_the_same", layout(world, "value", 400) == layout(world, "cuboid", 600), "")
        suite.assert_test("M13b_single_sided_floors_bake_as_many", counts.open == counts.cuboid, counts.open .. " and " .. counts.cuboid)

        suite.assert_test("M14_a_hull_block_leaves_no_floor_inside_it", floor_at(world, "hull block", 900, 0, 0) == nil, "")
        suite.assert_test("M15_nor_does_a_cuboid_block", floor_at(world, "cuboid block", 1000, 0, 0) == nil, "")
        -- A surface has no inside, so its underside is a floor with all the room in the world over it.
        suite.assert_test("M16_a_closed_trimesh_block_reads_its_underside_as_a_floor", floor_at(world, "closed block", 800, 0, 0) ~= nil, "")
        suite.assert_test("M16b_but_its_sides_cut_that_off_from_the_ground_outside",
            floor_at(world, "closed block", 802.5, 0, 0) == nil and floor_at(world, "closed block", 804.5, 0, 0) ~= nil, "")
        ask(commands, world, "outside the block", 800, 0, 0)

        suite.assert_test("M20_a_thin_wall_takes_the_cells_it_passes_through", floor_at(world, "thin wall", 1200, 0.5, 0) == nil, "")
        suite.assert_test("M21_and_only_those", floor_at(world, "thin wall", 1200, -0.5, 0) ~= nil and floor_at(world, "thin wall", 1200, 1.5, 0) ~= nil, "")
        suite.assert_test("M22_a_single_sided_sheet_does_the_same", floor_at(world, "sheet", 1300, 0.5, 0) == nil
            and floor_at(world, "sheet", 1300, -0.5, 0) ~= nil, "")
        suite.assert_test("M21b_and_under_a_roof_too", floor_at(world, "roofed wall", 1600, 0.5, 0, 0.1) == nil
            and floor_at(world, "roofed wall", 1600, -0.5, 0, 0.1) ~= nil and floor_at(world, "roofed wall", 1600, 1.5, 0, 0.1) ~= nil, "")
        suite.assert_test("M22b_whichever_side_of_the_centre_it_is",
            floor_at(world, "four walls", 1494.5, -5.5, 0) == nil and floor_at(world, "four walls", 1505.5, -5.5, 0) == nil
                and floor_at(world, "four walls", 1494.5, 5.5, 0) == nil and floor_at(world, "four walls", 1505.5, 5.5, 0) == nil
                and floor_at(world, "four walls", 1494.5, -4.5, 0) ~= nil and floor_at(world, "four walls", 1505.5, 4.5, 0) ~= nil, "")
        suite.assert_test("M23_ground_runs_on_past_the_ends_of_the_wall", floor_at(world, "thin wall", 1205, 0.5, 0) ~= nil, "")
        suite.assert_test("M24_what_a_step_could_climb_is_no_wall", floor_at(world, "thin wall", 1205.5, 5.5, 0) ~= nil, "")
        suite.assert_test("M25_something_loose_is_no_wall", floor_at(world, "crate", 1400.5, 0.5, 0) ~= nil, "")
        ask(commands, world, "round the wall", 1200, 0, 3)
        ask(commands, world, "round the sheet", 1300, 0, 3)

        for _, name in ipairs(MESHES) do
            ask(commands, world, name .. " climber", AT[name], 4, 4)
        end
        step("climbing")

    elseif phase == "climbing" then
        local arrived = true
        for _, name in ipairs(MESHES) do
            arrived = arrived and status_of(world, name .. " climber") == "arrived"
        end
        if arrived or clock > 25 then
            for _, name in ipairs(MESHES) do
                local at = named(world, name .. " climber"):get("Transform").translation
                suite.assert_test("M17_" .. name .. "_asked_for_the_point_straight_above_it_walks_round_by_the_ramp", reach[name] > 12, "reach " .. reach[name])
                suite.assert_test("M18_" .. name .. "_and_arrives_on_the_upper_floor",
                    at.y > 4.5 and at.y < 5.5 and near(at.x, AT[name], 1.2) and near(at.z, 4, 1.2),
                    string.format("%s at %.2f %.2f %.2f", tostring(status_of(world, name .. " climber")), at.x, at.y, at.z))
                ask(commands, world, name .. " descender", AT[name] - 5, 0, -3)
            end
            step("descending")
        end

    elseif phase == "descending" then
        local arrived = true
        for _, name in ipairs(MESHES) do
            arrived = arrived and status_of(world, name .. " descender") == "arrived"
        end
        if arrived or clock > 25 then
            suite.assert_test("M16c_so_nothing_outside_finds_a_way_in", named(world, "outside the block"):get("ai/nav/path").status == "unreachable", "")
            for _, kind in ipairs({ { "round the wall", 1200 }, { "round the sheet", 1300 } }) do
                local at = named(world, kind[1]):get("Transform").translation
                suite.assert_test("M26_" .. kind[1] .. "_gets_to_the_other_side", near(at.x, kind[2], 1.2) and near(at.z, 3, 1.2),
                    string.format("%s at %.2f %.2f", tostring(status_of(world, kind[1])), at.x, at.z))
            end
            for _, name in ipairs(MESHES) do
                local at = named(world, name .. " descender"):get("Transform").translation
                suite.assert_test("M19_" .. name .. "_asked_for_the_point_straight_below_it_walks_down_and_arrives_there",
                    at.y > 0.5 and at.y < 1.5 and near(at.x, AT[name] - 5, 1.2) and near(at.z, -3, 1.2),
                    string.format("%s at %.2f %.2f %.2f", tostring(status_of(world, name .. " descender")), at.x, at.y, at.z))
            end
            phase = "done"
            suite.finish("NavFloorsMeshSuite")
        end
    end

    if phase == "baking" and clock > 60 then
        suite.assert_test("M0_baked", false, "still baking after 60 s")
        phase = "done"
        suite.finish("NavFloorsMeshSuite")
    end
end):in_set("zz/nav_floors_mesh_suite")
