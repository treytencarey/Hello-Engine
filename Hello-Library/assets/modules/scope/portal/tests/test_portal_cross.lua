-- --host
-- A crossing between two worlds, each its own isolated VM, as two worlds of one process are in
-- production: the source world's portal links to the target world's peer listener, a player walks
-- into it, and core's peer switch hands the player over. The target's client is a connection that
-- only watches until the handover lands, as core's switch leaves it; its `player/spawner` is real.
--
--   X1 the crossing timer the portal puts in `transfer_data` reaches the target world, which accepts
--      `cooldown`
--   X2 the player spawned there from the handover is cooling, the timer synced to its owner
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ScopePortalCrossSuite")
local T = suite.assert_test

local HERE = "github:zzportalx/here:main"
local OTHER = "github:zzportalx/other:main"
-- What the target world accepts from a peer, as a world's boot declares it.
local ACCEPT = { "Transform", "cooldown" }

local DEFAULTS = {
    s_hosted = false, s_handed = false, s_dbg = "", walk = false,
    t_timer = -1, t_cooling = false, t_synced = false,
}
local ts = helpers.shared_state("ScopePortalCrossState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_portal_cross_source.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("ScopePortalCrossState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpx_s", port = 15495 },
        ["core/net"] = { mode = "server", name = "zzpx_s", port = 15495 },
        ["core/net/sync"] = false,
    })
    -- A world states its scope to a peer through its own listener.
    commands:spawn({
        ["core/net/peer/listen"] = { name = "zzpx_s_peer", port = 15498, scope_key = boot.HERE, world_port = 15495 },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.OTHER, mode = "server", status = "ready",
            ports = { world = 15496, peer = 15497 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal"] = { target = boot.OTHER }, ["core/net/sync"] = false, ["zz/px/portal"] = {} })
    commands:spawn({
        player = { client_id = 31, spawn_index = 0 },
        Transform = { translation = { x = 2, y = 0, z = 1 } },
        ["core/net/owner"] = { client_id = 31 },
        ["core/net/peer/share"] = { stable_id = "player_31" },
        ["core/net/sync"] = { Transform = { authority = "server", reliable = false } },
        ["core/script/owner"] = false,
        ["zz/px/player"] = {},
    })
end)

local walked = false
app:add_systems(Update, {
    Query[{
        with = { "zz/px/portal" },
        optional = { "scope/portal/hosted", "CollidingEntities3d" },
    }],
    Query[{
        with = { "zz/px/player" },
        optional = { "core/net/peer/mirror" },
    }],
    Commands,
}, function(portals, players, commands)
    local portal, player = portals:iter()[1], players:iter()[1]
    ts.s_hosted = portal ~= nil and portal:has("scope/portal/hosted") and portal:has("CollidingEntities3d")
    ts.s_handed = player ~= nil and player:has("core/net/peer/mirror")
    ts.s_dbg = "portal=" .. tostring(portal ~= nil) .. " hosted=" .. tostring(portal and portal:has("scope/portal/hosted")) .. " ce=" .. tostring(portal and portal:has("CollidingEntities3d"))
    if ts.walk and not walked and portal ~= nil and player ~= nil then
        walked = true
        commands:entity(portal:id()):insert({
            collision_trigger = { entered = { player:id() }, exited = {}, inside = { player:id() } },
        })
    end
end):in_set("zz/px_source")
]=])

helpers.make_fixture("modules/test_fixtures/gen_portal_cross_target.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("ScopePortalCrossState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpx_t", port = 15496 },
        ["core/net"] = { mode = "server", name = "zzpx_t", port = 15496 },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/net/peer/listen"] = { name = "zzpx_t_peer", port = 15497, scope_key = boot.OTHER, world_port = 15496 },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/accept"] = { components = boot.ACCEPT }, ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        ["core/net/connection"] = { client_id = 31, observer = true },
        ["core/net/sync"] = false,
        ["zz/px/connection"] = {},
    })
end)

app:add_systems(Update, {
    Query[{ with = { "zz/px/connection", "core/net/connection" } }],
    Query[{
        with = { "player", "core/net/owner" },
        optional = { "scope/portal/cooling", "cooldown", "core/net/sync" },
    }],
    Commands,
}, function(connections, players, commands)
    local c = connections:iter()[1]
    local connection = c and c:get("core/net/connection")
    local state = connection and connection.synced_state
    local timers = state and state.cooldown or {}
    local timer = timers["scope/portal/cooling"]
    if timer ~= nil and ts.t_timer < 0 then
        ts.t_timer = timer.remaining or 0
        commands:entity(c:id()):entry("core/net/connection"):and_modify(function(conn) conn.observer = false end)
    end
    for _, p in ipairs(players:iter()) do
        if p:get("core/net/owner").client_id == 31 then
            local sync = p:get("core/net/sync")
            ts.t_cooling = p:has("scope/portal/cooling")
            ts.t_synced = type(sync) == "table" and sync.cooldown ~= nil and sync.cooldown.target == "owner"
        end
    end
end):in_set("zz/px_target")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_portal_cross_target.lua",
    { DEFAULTS = DEFAULTS, OTHER = OTHER, ACCEPT = ACCEPT }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_portal_cross_source.lua",
    { DEFAULTS = DEFAULTS, HERE = HERE, OTHER = OTHER }, { headless = true })

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end
local function after(seconds) return function() return t - mark > seconds end end

step(within(20, function() return ts.s_hosted end), function() end)
step(after(0.5), function() ts.walk = true end)
step(within(10, function() return ts.t_timer >= 0 end), function()
    T("X1_the_crossing_timer_reaches_the_target_world_that_accepts_cooldown", ts.t_timer == 3,
        string.format("%s hosted=%s handed=%s timer=%s", ts.s_dbg, tostring(ts.s_hosted), tostring(ts.s_handed), tostring(ts.t_timer)))
end)
step(within(5, function() return ts.t_cooling and ts.t_synced end), function()
    T("X2_the_player_spawned_there_is_cooling_the_timer_synced_to_its_owner", ts.t_cooling and ts.t_synced,
        string.format("cooling=%s synced=%s", tostring(ts.t_cooling), tostring(ts.t_synced)))
end)

local done = false
app:add_systems(Update, { World }, function(world)
    t = t + world:delta_time()
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("ScopePortalCrossSuite")
    elseif s.ready(world) then
        s.act(world)
        at, mark = at + 1, t
    elseif t - mark > 30 then
        T("X0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("ScopePortalCrossSuite")
    end
end):in_set("zz/px_drive")
