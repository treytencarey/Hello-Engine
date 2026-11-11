-- --host
-- `movement` copies over a real connection: an isolated server world holds a body that is dynamic
-- there and walks, another client's player, and this client's own, and this VM is a client of it.
-- Each side has the ground, as a map gives each side its ground.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("MovementNetSuite")

local PORT = 15177

local DEFAULTS = { srv_ready = false, stop = false, flip = false }
local ts = helpers.shared_state("MovementNetState", DEFAULTS)

local GROUND = {
    Transform = { translation = { x = 0, y = -0.5, z = 0 } },
    RigidBody3d = "Fixed",
    Collider3d = { cuboid = { hx = 100, hy = 0.5, hz = 100 } },
    ["core/net/sync"] = false,
}

-- A body as `ai/spawner` makes one, or another client's player as `player/spawner` makes one.
local function body(extra)
    local b = {
        movement = {},
        Transform = { translation = { x = extra.x, y = 1, z = 0 } },
        RigidBody3d = extra.type,
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        ["zz/copy"] = { name = extra.name },
        ["core/net/sync"] = {
            Transform = { authority = "server", reliable = false },
            RigidBody3d = { authority = "server" },
            Collider3d = { authority = "server" },
            LockedAxes3d = { authority = "server" },
            ["zz/copy"] = { authority = "server" },
        },
    }
    return b
end

helpers.make_fixture("modules/test_fixtures/gen_movement_net_vm1.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("MovementNetState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzmove", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzmove", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn(boot.GROUND)
    commands:spawn(boot.WALKER)
    commands:spawn(boot.OTHER)
    commands:spawn(boot.FLIPS)
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_start",
        Transform = { translation = { x = 3, y = 0, z = 0 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
end)
-- It walks along x, as steering would make it.
app:add_systems(Update, { Query[{ with = { "zz/copy", Mut["Velocity3d"], Mut["RigidBody3d"] } }] }, function(bodies)
    for _, e in ipairs(bodies:iter_mut()) do
        local name = e:get("zz/copy").name
        if name == "walker" then
            e:patch({ Velocity3d = { linvel = { x = ts.stop and 0 or 2 } } })
        elseif name == "flips" and ts.flip and e:get("RigidBody3d") ~= "Dynamic" then
            e:set({ RigidBody3d = "Dynamic" })
        end
    end
    ts.srv_ready = true
end):in_set("zz/movement_net_server")
-- What sends the server's value again: a write of it, here its own tuning field.
app:add_systems(Update, { Query[{ with = { "player", Mut["camera/third_person"] } }] }, function(players)
    if not ts.flip then return end
    for _, e in ipairs(players:iter_mut()) do
        if e:get("camera/third_person").zoom_step ~= 0.75 then
            e:patch({ ["camera/third_person"] = { zoom_step = 0.75 } })
        end
    end
end):in_set("zz/movement_net_resend")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_movement_net_vm1.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
    GROUND = GROUND,
    WALKER = body({ name = "walker", type = "Dynamic", x = 10 }),
    OTHER = body({ name = "other", type = "KinematicPositionBased", x = 20 }),
    FLIPS = body({ name = "flips", type = "KinematicPositionBased", x = 30 }),
}, { headless = true })

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn(GROUND)
end)

local function copy(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/copy" },
        optional = { "RigidBody3d", "core/net/sync/Transform", "Velocity3d", "core/net/local" },
    })) do
        if e:get("zz/copy").name == name then
            return e
        end
    end
end

local function mine(world)
    return world:query({
        with = { "player", "core/net/local" },
        optional = { "RigidBody3d", "Velocity3d", "movement/grounded" },
    })[1]
end

local function at(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform().translation
end

local phase, t, mark = "wait_srv", 0, 0
local x_before, other_changes = 0, 0

-- How many times the other client's copy changed type, once it has arrived. Nothing writes it.
app:add_systems(PostUpdate, {
    Query[{
        changed = { "RigidBody3d" },
        with = { "zz/copy" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        if e:get("zz/copy").name == "other" then
            other_changes = other_changes + 1
        end
    end
end):in_set("zz/movement_net_edges")

app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    local function step(next_phase) phase, mark = next_phase, t end
    local since = t - mark

    if phase == "wait_srv" and ts.srv_ready then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzmove_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzmove_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        step("connecting")

    elseif phase == "connecting" and copy(world, "walker") ~= nil and copy(world, "other") ~= nil and mine(world) ~= nil then
        step("settling")

    elseif phase == "settling" and since > 1.5 then
        local walker = copy(world, "walker")
        suite.assert_test("MN1_a_copy_dynamic_on_the_server_is_kinematic_here", walker:get("RigidBody3d") == "KinematicPositionBased",
            tostring(walker:get("RigidBody3d")))
        local p = at(world, walker)
        suite.assert_test("MN2_it_rests_where_the_server_has_it_not_where_gravity_would", math.abs(p.y - 0.9) < 0.3, "y " .. p.y)
        x_before = p.x
        suite.assert_test("MN3_another_clients_player_stays_kinematic_written_once",
            copy(world, "other"):get("RigidBody3d") == "KinematicPositionBased" and other_changes == 1, "changes " .. other_changes)
        local me = mine(world)
        suite.assert_test("MN4_this_clients_own_player_turns_dynamic", me:get("RigidBody3d") == "Dynamic", tostring(me:get("RigidBody3d")))
        suite.assert_test("MN5_and_stands_on_the_ground", me:has("movement/grounded"), "")
        step("walking")

    elseif phase == "walking" and since > 1.5 then
        local x = at(world, copy(world, "walker")).x
        suite.assert_test("MN6_the_copy_follows_the_server_as_it_walks", x > x_before + 1, string.format("%.2f to %.2f", x_before, x))
        ts.stop = true
        step("stopped")

    elseif phase == "stopped" and since > 1.0 then
        x_before = at(world, copy(world, "walker")).x
        step("stood")

    elseif phase == "stood" and since > 0.5 then
        local x = at(world, copy(world, "walker")).x
        suite.assert_test("MN7_and_stands_when_it_stands", math.abs(x - x_before) < 0.1, string.format("%.2f to %.2f", x_before, x))
        ts.flip = true
        step("flipped")

    elseif phase == "flipped" and since > 1.5 then
        local flips = copy(world, "flips")
        suite.assert_test("MN8_a_body_that_turns_dynamic_later_stays_kinematic_here", flips:get("RigidBody3d") == "KinematicPositionBased",
            tostring(flips:get("RigidBody3d")))
        -- A value is whole: what crossed has every field the look system reads, and a server's write reaches it.
        local tuning = world:get_entity(mine(world):id()):get("camera/third_person")
        suite.assert_test("MN9_the_cameras_tuning_crosses_whole", tuning ~= nil and tuning.sensitivity == 0.003 and tuning.max_distance == 20,
            tuning and tostring(tuning.sensitivity) or "none")
        suite.assert_test("MN10_a_servers_write_of_it_arrives", tuning ~= nil and tuning.zoom_step == 0.75, tuning and tostring(tuning.zoom_step) or "none")
        local look = world:get_entity(mine(world):id()):get("camera")
        suite.assert_test("MN11_the_owners_camera_keeps_what_it_holds", look ~= nil and look.yaw ~= nil and look.distance ~= nil,
            look and tostring(look.yaw) or "none")
        phase = "done"
        suite.finish("MovementNetSuite")
    end

    if phase ~= "done" and since > 20 then
        suite.assert_test("MN0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        phase = "done"
        suite.finish("MovementNetSuite")
    end
end):in_set("zz/movement_net_client")
