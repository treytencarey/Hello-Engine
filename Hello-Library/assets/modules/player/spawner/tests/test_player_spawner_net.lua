-- --host
-- The player spawner over a real connection: an isolated worker hosts the server with a spawner
-- and, at first, no spawn point; this VM is the client. What this client holds of its player in the
-- frame the player arrives is what the spawn carried, as the owning client keeps its own
-- Transform and camera from then on.
--
--   N1 with no point on the server, the client gets no player
--   N2 a point added there: the player arrives here on it, `lift` above, turned to its facing, in
--      the frame it arrives
require("modules/core/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local suite = helpers.create_suite("PlayerSpawnerNetSuite")
local T = suite.assert_test

local PORT = 15561
local DEFAULTS = { srv_ready = false, add_point = false }
local ts = helpers.shared_state("PlayerSpawnerNetState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_player_spawner_net_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("PlayerSpawnerNetState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpsn", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzpsn", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
end)

local added = false
app:add_systems(Update, { World, Commands }, function(world, commands)
    if not ts.srv_ready and #Net.nets(world, "server", true) == 1 then ts.srv_ready = true end
    if ts.add_point and not added then
        added = true
        -- A quarter turn about +y, so it faces -x.
        commands:spawn({
            Name = "zz_net",
            Transform = {
                translation = { x = 4, y = 0, z = -2 },
                rotation = { x = 0, y = 0.70710677, z = 0, w = 0.70710677 },
            },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
    end
end):in_set("zz/player_spawner_net_server")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_player_spawner_net_server.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })

-- Each player as it is in the frame it arrives here.
local seen = {}
app:add_systems(Update, {
    Query[{
        added = { "player" },
        optional = { "Transform", "camera" },
    }],
}, function(arrived)
    for _, p in ipairs(arrived:iter()) do
        local t = p:get("Transform")
        local camera = p:get("camera")
        seen[#seen + 1] = { at = t and t.translation, yaw = camera and camera.yaw }
    end
end):in_set("zz/player_spawner_net_seen")

local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-2 end

local phase, clock = "wait_srv", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "wait_srv" and (ts.srv_ready or clock > 15) then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzpsn", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzpsn", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        step("wait_conn")

    elseif phase == "wait_conn" then
        for _, e in ipairs(world:query({ with = { "core/net", "core/net/state" } })) do
            if (e:get("core/net/state") or {}).client_id ~= nil then step("no_point") end
        end

    elseif phase == "no_point" and clock > 1.5 then
        T("N1_with_no_point_on_the_server_the_client_gets_no_player", #seen == 0, #seen .. " players")
        ts.add_point = true
        step("arrive")

    elseif phase == "arrive" and #seen > 0 then
        local first = seen[1]
        local at = first.at or {}
        T("N2_the_player_arrives_on_the_point_lift_above_turned_to_its_facing_in_its_first_frame",
            near(at.x, 4) and near(at.y, 1) and near(at.z, -2) and near(first.yaw, math.pi / 2),
            string.format("at %s %s %s yaw %s", tostring(at.x), tostring(at.y), tostring(at.z), tostring(first.yaw)))
        phase = "done"
        suite.finish("PlayerSpawnerNetSuite")
    end

    if phase ~= "done" and clock > 20 then
        T("N0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        phase = "done"
        suite.finish("PlayerSpawnerNetSuite")
    end
end):in_set("zz/player_spawner_net_suite")
