-- --host
-- A headset tracks from the moment the engine starts, so poses are arriving before this client's
-- player does, and before the sync of its `vr/active`. Every step of joining has them already.
--
--   PB1 the server hears `vr/active` all the same, and the camera swaps on both sides
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("PlayerVrBootSuite")

local PORT = 15378

local DEFAULTS = { srv_ready = false }
local ts = helpers.shared_state("PlayerVrBootState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_player_vr_boot_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PlayerVrBootState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzvrb", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzvrb", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_start",
        Transform = { translation = { x = 3, y = 0, z = 0 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
end)

app:add_systems(Update, { World }, function(world)
    ts.srv_ready = true
    local me = world:query({
        with = { "player", "core/net/owner" },
        optional = { "vr/active", "camera/vr", "camera/third_person" },
    })[1]
    if me ~= nil then
        ts.s_active = me:has("vr/active")
        ts.s_camera_vr = me:has("camera/vr")
        ts.s_third = me:has("camera/third_person")
    end
end):in_set("zz/player_vr_boot_server")
]=])

helpers.make_fixture("modules/test_fixtures/gen_player_vr_boot_client.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PlayerVrBootState", boot.DEFAULTS)

local joined = false
app:add_systems(Update, { World, Commands }, function(world, commands)
    if ts.srv_ready and not joined then
        joined = true
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzvrb_c", ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzvrb_c", ip = "127.0.0.1", port = boot.PORT },
            ["core/net/sync"] = false,
        })
    end
    local me = world:query({
        with = { "player", "core/net/local" },
        optional = { "vr/active", "camera/vr", "camera/third_person" },
    })[1]
    if me ~= nil then
        ts.c_active = me:has("vr/active")
        ts.c_camera_vr = me:has("camera/vr")
        ts.c_third = me:has("camera/third_person")
    end
end):in_set("zz/player_vr_boot_client")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_player_vr_boot_server.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_player_vr_boot_client.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })

local t, done = 0, false
app:add_systems(Update, { World, bevy.MessageWriter[VrPoseInput] }, function(world, poses)
    t = t + world:delta_time()
    poses:write({ hmd_position = { x = 0, y = 1.6, z = 0 } })
    if done then
        return
    end
    if ts.c_active and ts.s_camera_vr and ts.c_camera_vr then
        suite.assert_test("PB1_the_server_hears_it", ts.s_active == true, "")
        suite.assert_test("PB1_the_camera_swaps_on_both_sides", ts.s_third == false, "")
        done = true
        suite.finish("PlayerVrBootSuite")
    elseif t > 20 then
        suite.assert_test("PB0_it_never_swapped", false, string.format("client active %s, server active %s, server camera/vr %s, client camera/vr %s",
            tostring(ts.c_active), tostring(ts.s_active), tostring(ts.s_camera_vr), tostring(ts.c_camera_vr)))
        done = true
        suite.finish("PlayerVrBootSuite")
    end
end):in_set("zz/player_vr_boot_drive")
