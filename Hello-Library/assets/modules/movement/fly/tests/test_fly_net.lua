-- --host
-- `movement/fly` over a real connection: an isolated server world spawns this client's player and
-- gives it flight, as a world's server half does, and this VM is its client.
--
--   FN1 the owner's client turns flight and no-clip on, and the server's copy has them
--   FN2 the server's copy keeps its gravity and its collider: flight acts only on the owner's client,
--       where its own body loses gravity and becomes a sensor
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("FlyNetSuite")

local PORT = 15179

local DEFAULTS = { srv_ready = false, srv_fly = false, srv_on = false, srv_noclip = false, srv_scale = false, srv_sensor = false }
local ts = helpers.shared_state("FlyNetState", DEFAULTS)

local GROUND = {
    Transform = { translation = { x = 0, y = -0.5, z = 0 } },
    RigidBody3d = "Fixed",
    Collider3d = { cuboid = { hx = 100, hy = 0.5, hz = 100 } },
    ["core/net/sync"] = false,
}

helpers.make_fixture("modules/test_fixtures/gen_fly_net_vm1.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("FlyNetState", boot.DEFAULTS)
app:add_systems(Startup, { World, Commands }, function(world, commands)
    -- declared first, as the net does when it starts: an owner stored before it gets no owner edge
    Net.declare_ownership(world, commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzfly", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzfly", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn(boot.GROUND)
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_start",
        Transform = { translation = { x = 3, y = 0, z = 0 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
end)
-- The world's server half gives its players flight.
app:add_systems(First, { Query[{ added = { "player" } }], Commands }, function(players, commands)
    for _, e in ipairs(players:iter()) do
        commands:entity(e:id()):insert_if_new({ ["movement/fly"] = {} })
    end
end):in_set("zz/fly_net_give")
-- What the server's copy holds.
app:add_systems(Update, { Query[{ with = { "player" }, optional = { "movement/fly", "GravityScale3d", "Sensor3d" } }] }, function(players)
    for _, e in ipairs(players:iter()) do
        local fly = e:get("movement/fly")
        ts.srv_fly = fly ~= nil
        ts.srv_on = fly ~= nil and fly.on == true
        ts.srv_noclip = fly ~= nil and fly.noclip == true
        ts.srv_scale = e:has("GravityScale3d") and e:get("GravityScale3d") or false
        ts.srv_sensor = e:has("Sensor3d")
    end
    ts.srv_ready = true
end):in_set("zz/fly_net_server")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_fly_net_vm1.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
    GROUND = GROUND,
}, { headless = true })

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn(GROUND)
    -- This client's copy of the map's point: the player's body waits for the point it claims here.
    commands:spawn({
        Name = "zz_start",
        Transform = { translation = { x = 3, y = 0, z = 0 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
end)

--- This client's player: the one in its net entity's `core/net/owns`.
local function mine(world)
    for _, n in ipairs(world:query({ with = { "core/net", "core/net/owns" } })) do
        local p = world:query({
            with = { "player" },
            optional = { "movement/fly", "GravityScale3d", "Sensor3d" },
            iter_many = n:get("core/net/owns"),
        })[1]
        if p ~= nil then return p end
    end
end

local phase, t, mark = "wait_srv", 0, 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    local function step(next_phase) phase, mark = next_phase, t end
    local since = t - mark

    if phase == "wait_srv" and ts.srv_ready then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzfly_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzfly_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        step("connecting")

    elseif phase == "connecting" and mine(world) ~= nil and mine(world):has("movement/fly") and ts.srv_fly then
        step("settling")

    elseif phase == "settling" and since > 1.0 then
        -- What the F key and the menu's No-clip item write on the owner's client.
        commands:entity(mine(world):id()):insert({ ["movement/fly"] = { on = true, noclip = true } })
        step("toggled")

    elseif phase == "toggled" and ts.srv_on and since > 0.5 then
        local me = mine(world)
        suite.assert_test("FN1_flight_turned_on_by_the_owner_reaches_the_server", ts.srv_on and ts.srv_noclip,
            string.format("on %s noclip %s", tostring(ts.srv_on), tostring(ts.srv_noclip)))
        suite.assert_test("FN2_the_server_s_copy_keeps_its_gravity_and_its_collider",
            ts.srv_scale ~= 0 and ts.srv_sensor == false
                and me:get("GravityScale3d") == 0 and me:has("Sensor3d"),
            string.format("server scale %s sensor %s, owner scale %s sensor %s", tostring(ts.srv_scale),
                tostring(ts.srv_sensor), tostring(me:get("GravityScale3d")), tostring(me:has("Sensor3d"))))
        phase = "done"
        suite.finish("FlyNetSuite")
    end

    if phase ~= "done" and since > 20 then
        suite.assert_test("FN0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        phase = "done"
        suite.finish("FlyNetSuite")
    end
end):in_set("zz/fly_net_client")
