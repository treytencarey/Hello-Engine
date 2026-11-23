-- --host
-- Back with no handover. A server world, A, in its own VM, with a spawner and a client playing. Its
-- player is demoted as a crossing demotes it (a `was_source` mirror of the world it went to), and
-- that world's updates carry it to where it stood there, with its camera and its scale. Then the
-- world it went to is gone (no connection reaches it) and the client plays in A again, as a client
-- whose world died walks back through its history.
--
--   WB1 A's player, demoted, is a mirror and nobody's body here
--   WB2 the client back, it has one body here, not a second
--   WB3 that body is the one it left, its own again, where the far world last had it
--   WB4 it is framed as A frames an arrival: the look it had there, A's scale, none of the far camera
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local suite = helpers.create_suite("PlayerWalkBackSuite")
local T = suite.assert_test
local reg = helpers.peer_registry()

local A_PORT = 15961
local DEFAULTS = { players = -1, owned = -1, mirrors = -1, demote = false, demoted = false, back = false,
    x = 0, scale = 0, pitch = 0, distance = 0, height = false, tag = false }
local ts = helpers.shared_state("ZzWalkBackState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_walk_back_a.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("ZzWalkBackState", boot.DEFAULTS)
app:add_systems(Startup, { World, Commands }, function(world, commands)
    Net.declare_ownership(world, commands)
    local wn = commands:spawn({ ["core/world/net"] = { mode = "server", name = "zzwb_a", port = boot.A_PORT },
        ["core/net"] = { mode = "server", name = "zzwb_a", port = boot.A_PORT }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zzwb_a_peer", port = boot.A_PORT + 1, scope_key = "zz:wb:a",
        world_port = boot.A_PORT }, ["core/net/peer"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/peer/accept"] = { components = "all" },
        ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({ Name = "zz_wb", Transform = {}, ["player/spawner/point"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/connection"] = { client_id = 7, observer = false }, ["core/net/sync"] = false, ChildOf = wn:id() })
end)
local done = false
app:add_systems(Update, { World, Commands }, function(world, commands)
    local c = world:query({ with = { "core/net/connection" } })[1]
    local players = world:query({ with = { "player", "Transform" },
        optional = { "core/net/owner", "core/net/peer/mirror", "camera", "zz/wb/left" } })
    ts.players = #players
    local owned, mirrors = 0, 0
    for _, p in ipairs(players) do
        if p:get("core/net/owner") then owned = owned + 1 end
        if p:get("core/net/peer/mirror") then mirrors = mirrors + 1 end
        if ts.back and p:get("core/net/owner") then
            local t, cam = p:get("Transform"), p:get("camera") or {}
            ts.x, ts.scale = t.translation.x, t.scale.x
            ts.pitch, ts.distance, ts.height = cam.pitch or 0, cam.distance or 0, cam.height ~= nil
            ts.tag = p:get("zz/wb/left") ~= nil
        end
    end
    ts.owned, ts.mirrors = owned, mirrors
    -- As core's crossing demotes it, then as the far world's updates write its mirror.
    if ts.demote and not done and #players == 1 and c then
        done = true
        local p = world:get_entity(players[1]:id())
        p:remove("core/net/owner")
        p:patch({
            ["core/net/peer/mirror"] = { stable_id = "player_7", source_peer = "zz:wb:b", was_source = true,
                via = "out:zzwb_gone", owner = { client = 7, connection = c:id() } },
            ["core/net/peer/share"] = { source_scope = "zz:wb:b" },
        })
        p:set({
            Transform = { translation = { x = 5, y = 2, z = -3 }, rotation = { x = 0, y = 0, z = 0, w = 1 },
                scale = { x = 2, y = 2, z = 2 } },
            camera = { yaw = 0.5, pitch = -0.3, distance = 6, height = 9 },
            ["zz/wb/left"] = {},
        })
        ts.demoted = true
    end
end):in_set("zz/wb_a")
-- Where a client's presence lands: in `First`, as the world net's inbound applies it.
app:add_systems(First, { World, Commands }, function(world, commands)
    local c = world:query({ with = { "core/net/connection" } })[1]
    local watching = ts.demoted and not ts.back
    if c and c:get("core/net/connection").observer ~= watching then
        commands:entity(c:id()):entry("core/net/connection"):and_modify(function(nc) nc.observer = watching end)
    end
end):in_set("zz/wb_presence"):before("core/net/peer/client_inbound")
]=])

local DATA = { DEFAULTS = DEFAULTS, A_PORT = A_PORT }
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_walk_back_a.lua", DATA, { headless = true }), "zz:wb:a")

local phase, clock = "spawning", 0
app:add_systems(Update, { World }, function(world)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    if phase == "spawning" and (ts.owned == 1 or clock > 15) and clock > 0.5 then
        ts.demote = true
        step("demoting")
    elseif phase == "demoting" and ts.demoted and clock > 1 then
        T("WB1_a_s_player_demoted_is_a_mirror_and_nobody_s_body_here", ts.players == 1 and ts.mirrors == 1 and ts.owned == 0,
            string.format("players=%d mirrors=%d owned=%d", ts.players, ts.mirrors, ts.owned))
        ts.back = true
        step("back")
    elseif phase == "back" and clock > 1.5 then
        T("WB2_the_client_back_it_has_one_body_here", ts.players == 1 and ts.owned == 1 and ts.mirrors == 0,
            string.format("players=%d owned=%d mirrors=%d", ts.players, ts.owned, ts.mirrors))
        T("WB3_that_body_is_the_one_it_left_where_the_far_world_last_had_it", ts.tag and math.abs(ts.x - 5) < 1e-3,
            string.format("the one it left=%s x=%s", tostring(ts.tag), tostring(ts.x)))
        T("WB4_it_is_framed_as_a_frames_an_arrival",
            ts.scale == 1 and math.abs(ts.pitch + 0.3) < 1e-3 and ts.distance == 6 and not ts.height,
            string.format("scale=%s pitch=%s distance=%s far height kept=%s", tostring(ts.scale), tostring(ts.pitch),
                tostring(ts.distance), tostring(ts.height)))
        phase = "done"
        suite.finish("PlayerWalkBackSuite")
    end
    if phase ~= "done" and clock > 20 then
        T("WB0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("PlayerWalkBackSuite")
    end
end):in_set("zz/wb_suite")
