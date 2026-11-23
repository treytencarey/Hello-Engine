-- --host
-- A player's mirror outlives nothing its world doesn't. Two server worlds, A and B, each in its own
-- VM; A links to B (as a portal's link does), and B's spawner has a player whose share A mirrors.
-- Then A's link goes, as it does when B's world stops or its process dies, and this VM joins A as
-- a fresh client.
--
--   MD1 A holds B's player as a mirror over the link
--   MD2 the link gone, A holds no body of B's player: no mirror of it, nothing with its collider
--   MD3 a client joining A afterwards is sent no body of it
require("modules/core/init.lua")
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local suite = helpers.create_suite("PlayerMirrorLinkDropSuite")
local T = suite.assert_test
local reg = helpers.peer_registry()

local A_PORT, B_PORT = 15951, 15953
local DEFAULTS = { a_mirror = false, a_bodies = -1, a_linked = false, drop = false, dropped = false, b_player = false }
local ts = helpers.shared_state("ZzMirrorDropState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_mirror_drop_a.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("ZzMirrorDropState", boot.DEFAULTS)
app:add_systems(Startup, { World, Commands }, function(world, commands)
    Net.declare_ownership(world, commands)
    commands:spawn({ ["core/world/net"] = { mode = "server", name = "zzmd_a", port = boot.A_PORT },
        ["core/net"] = { mode = "server", name = "zzmd_a", port = boot.A_PORT }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zzmd_a_peer", port = boot.A_PORT + 1, scope_key = "zz:md:a",
        world_port = boot.A_PORT }, ["core/net/peer"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/link"] = { name = "zzmd_a_to_b", port = boot.B_PORT + 1, scope_key = "zz:md:b",
        server_addr = "127.0.0.1" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/peer/accept"] = { components = "all" },
        ["core/net/sync"] = false })
end)
local gone = false
app:add_systems(Update, { World, Commands }, function(world, commands)
    local l = world:query({ with = { "core/net/peer/link", "core/net/peer/link/state" } })[1]
    ts.a_linked = l ~= nil and l:get("core/net/peer/link/state").welcomed == true
    local mirrors = 0
    for _, m in ipairs(world:query({ with = { "core/net/peer/mirror" } })) do
        if m:get("core/net/peer/mirror").stable_id == "player_7" then mirrors = mirrors + 1 end
    end
    ts.a_mirror = mirrors > 0
    ts.a_bodies = #world:query({ with = { "Collider3d", "movement" } })
    if ts.drop and not gone and l ~= nil then
        gone = true
        commands:entity(l:id()):despawn()
        ts.dropped = true
    end
end):in_set("zz/md_a")
]=])

helpers.make_fixture("modules/test_fixtures/gen_mirror_drop_b.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("ZzMirrorDropState", boot.DEFAULTS)
app:add_systems(Startup, { World, Commands }, function(world, commands)
    Net.declare_ownership(world, commands)
    local wn = commands:spawn({ ["core/world/net"] = { mode = "server", name = "zzmd_b", port = boot.B_PORT },
        ["core/net"] = { mode = "server", name = "zzmd_b", port = boot.B_PORT }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zzmd_b_peer", port = boot.B_PORT + 1, scope_key = "zz:md:b",
        world_port = boot.B_PORT }, ["core/net/peer"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/peer/accept"] = { components = "all" },
        ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({ Name = "zz_md", Transform = {}, ["player/spawner/point"] = {}, ["core/net/sync"] = false })
    -- A client playing here, as one handed in is.
    commands:spawn({ ["core/net/connection"] = { client_id = 7, observer = false }, ["core/net/sync"] = false, ChildOf = wn:id() })
end)
app:add_systems(Update, { World }, function(world)
    ts.b_player = #world:query({ with = { "player", "core/net/peer/share" } }) > 0
end):in_set("zz/md_b")
]=])

local DATA = { DEFAULTS = DEFAULTS, A_PORT = A_PORT, B_PORT = B_PORT }
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_mirror_drop_b.lua", DATA, { headless = true }), "zz:md:b")
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_mirror_drop_a.lua", DATA, { headless = true }), "zz:md:a")

local phase, clock = "linking", 0
app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    if phase == "linking" and ((ts.a_linked and ts.b_player and ts.a_mirror and clock > 1) or clock > 20) then
        T("MD1_a_holds_b_s_player_as_a_mirror_over_the_link", ts.a_mirror and ts.a_bodies >= 1,
            string.format("linked=%s b_player=%s mirror=%s bodies=%s", tostring(ts.a_linked), tostring(ts.b_player),
                tostring(ts.a_mirror), tostring(ts.a_bodies)))
        ts.drop = true
        step("dropped")
    elseif phase == "dropped" and ts.dropped and clock > 1.5 then
        T("MD2_the_link_gone_a_holds_no_body_of_b_s_player", not ts.a_mirror and ts.a_bodies == 0,
            string.format("mirror=%s bodies=%s", tostring(ts.a_mirror), tostring(ts.a_bodies)))
        commands:spawn({ ["core/world/net"] = { mode = "client", name = "zzmd_c", ip = "127.0.0.1", port = A_PORT },
            ["core/net"] = { mode = "client", name = "zzmd_c", ip = "127.0.0.1", port = A_PORT }, ["core/net/sync"] = false })
        step("joined")
    elseif phase == "joined" and clock > 3 then
        local bodies = world:query({ with = { "Collider3d", "movement" }, optional = { "player" } })
        T("MD3_a_client_joining_a_is_sent_no_body_of_it", #bodies == 0, "bodies here=" .. #bodies)
        phase = "done"
        suite.finish("PlayerMirrorLinkDropSuite")
    end
    if phase ~= "done" and clock > 30 then
        T("MD0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("PlayerMirrorLinkDropSuite")
    end
end):in_set("zz/md_suite")
