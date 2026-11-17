-- --host
-- This client's own player is held until its copy of the map is ready: it stays kinematic, as the
-- server sends it, until the scene holding its claimed point has its colliders. The scene is the
-- spawner's fixture, one node at (2, 0, -3) the suite marks as a point, over a plain floor, and
-- the suite writes `collider/status` on its root itself, as `collider` would.
--
--   H1 with no status, then while "building", the local player stays kinematic and still
--   H2 "done" makes it dynamic, and it stands on the floor
--   H3 "building" again makes it kinematic; "done" again frees it where it stands
--   H4 a point outside any scene is ready at once; a remote player is never switched; a local
--      player with no claim (one handed over before a point was ready) is dynamic at once
--   H5 the server's kind written over a freed body again frees it again where it stands
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local AssetServer = require("bevy::asset::AssetServer")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerHoldSuite")
local T = suite.assert_test

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/scene"] = {},
        SceneRoot = asset_server:load("modules/player/spawner/tests/fixtures/zz_scene.gltf#Scene0"),
        Transform = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/floor"] = {},
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 20, hy = 0.5, hz = 20 } },
        ["core/net/sync"] = false,
    })
end)

-- A player as the server sends it: kinematic, with its collider, `lift` above its point.
local function arrive(commands, name, claim, at, owned)
    commands:spawn({
        ["zz/name"] = { name = name },
        player = { client_id = #name, spawn_point = claim },
        movement = {},
        Transform = { translation = at },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        camera = { yaw = 0 },
        ["core/net/local"] = owned and {} or nil,
        ["core/net/sync"] = false,
    })
end

local function named(world, name)
    for _, e in ipairs(world:query({ with = { "zz/name" }, optional = { "RigidBody3d" } })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function body(world, name)
    local e = named(world, name)
    return e and e:get("RigidBody3d")
end

local function at(world, name)
    local e = named(world, name)
    return e and world:get_entity(e:id()).GlobalTransform:compute_transform().translation
end

local function point(world, name)
    for _, e in ipairs(world:query({ with = { "Name" } })) do
        if e:get("Name").name == name then
            return e
        end
    end
end

local function near(a, b) return math.abs(a - b) < 0.05 end

local function where(p) return p and string.format("%.2f %.2f %.2f", p.x, p.y, p.z) or "none" end

-- Standing on the floor: the capsule's centre is 0.9 m above its feet.
local function stands_at(p, x, z) return p ~= nil and near(p.x, x) and near(p.y, 0.9) and near(p.z, z) end

local function status(world, commands, state)
    commands:entity(world:query({ with = { "zz/scene" } })[1]:id()):insert({ ["collider/status"] = { state = state } })
end

local phase, clock = "scene", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "scene" and point(world, "zz_scene_point") ~= nil then
        commands:entity(point(world, "zz_scene_point"):id()):insert({ ["player/spawner/point"] = {} })
        arrive(commands, "me", "zz_scene_point", { x = 2, y = 1, z = -3 }, true)
        step("absent")

    elseif phase == "absent" and clock > 0.5 then
        T("H1_with_no_status_the_local_player_stays_kinematic_and_still",
            body(world, "me") == "KinematicPositionBased" and near(at(world, "me").y, 1),
            tostring(body(world, "me")) .. " at " .. where(at(world, "me")))
        status(world, commands, "building")
        step("building")

    elseif phase == "building" and clock > 0.5 then
        T("H1_while_building_the_local_player_stays_kinematic_and_still",
            body(world, "me") == "KinematicPositionBased" and near(at(world, "me").y, 1),
            tostring(body(world, "me")) .. " at " .. where(at(world, "me")))
        status(world, commands, "done")
        step("done")

    elseif phase == "done" and clock > 1.5 then
        T("H2_done_makes_it_dynamic_standing_on_the_floor",
            body(world, "me") == "Dynamic" and stands_at(at(world, "me"), 2, -3),
            tostring(body(world, "me")) .. " at " .. where(at(world, "me")))
        status(world, commands, "building")
        step("rebuild")

    elseif phase == "rebuild" and clock > 0.3 then
        T("H3_building_again_makes_it_kinematic", body(world, "me") == "KinematicPositionBased",
            tostring(body(world, "me")))
        commands:entity(named(world, "me"):id()):insert({ Transform = { translation = { x = 6, y = 1, z = 4 } } })
        step("moved")

    elseif phase == "moved" and clock > 0.3 then
        status(world, commands, "done")
        step("freed")

    elseif phase == "freed" and clock > 1.5 then
        T("H3_done_again_frees_it_where_it_stands",
            body(world, "me") == "Dynamic" and stands_at(at(world, "me"), 6, 4),
            tostring(body(world, "me")) .. " at " .. where(at(world, "me")))
        commands:spawn({
            Name = "zz_free",
            Transform = { translation = { x = -5, y = 0, z = 5 } },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
        arrive(commands, "b", "zz_free", { x = -5, y = 1, z = 5 }, true)
        arrive(commands, "other", "zz_scene_point", { x = 2, y = 1, z = -3 }, false)
        arrive(commands, "h", nil, { x = 8, y = 1, z = 8 }, true)
        step("outside")

    elseif phase == "outside" and clock > 1.5 then
        T("H4_a_point_outside_any_scene_is_ready_at_once",
            body(world, "b") == "Dynamic" and stands_at(at(world, "b"), -5, 5),
            tostring(body(world, "b")) .. " at " .. where(at(world, "b")))
        T("H4_a_remote_player_is_never_switched", body(world, "other") == "KinematicPositionBased",
            tostring(body(world, "other")))
        T("H4_a_local_player_with_no_claim_is_dynamic_at_once",
            body(world, "h") == "Dynamic" and stands_at(at(world, "h"), 8, 8),
            tostring(body(world, "h")) .. " at " .. where(at(world, "h")))
        -- As the net client applies the server's second copy of a new owner's values: whole, over
        -- what this client set.
        world:get_entity(named(world, "h"):id()):set({ RigidBody3d = "KinematicPositionBased" })
        world:get_entity(named(world, "b"):id()):set({ RigidBody3d = "KinematicPositionBased" })
        step("rewritten")

    elseif phase == "rewritten" and clock > 1 then
        T("H5_the_server_s_kind_over_a_freed_body_frees_it_again_where_it_stands",
            body(world, "h") == "Dynamic" and stands_at(at(world, "h"), 8, 8)
                and body(world, "b") == "Dynamic" and stands_at(at(world, "b"), -5, 5),
            tostring(body(world, "h")) .. " " .. tostring(body(world, "b")))
        phase = "done_all"
        suite.finish("PlayerHoldSuite")
    end

    if phase ~= "done_all" and clock > 10 then
        T("H0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done_all"
        suite.finish("PlayerHoldSuite")
    end
end):in_set("zz/player_hold")
