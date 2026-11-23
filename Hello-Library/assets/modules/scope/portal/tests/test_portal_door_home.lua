-- --host
-- A player coming home through a door, with real physics: two worlds, each its own VM, as two worlds
-- of one process are in production, each world's door linking to the other's at a named node. The
-- player walks through the source's door into the target, then back through the target's door that
-- has no target, the way back; the source re-promotes the body it kept, which stood in its door
-- while the player stood in the way back. Both worlds accept everything, as a world's boot does,
-- and run the real `cooldown`, `scope/portal` and `player/spawner`.
--
--   DH1 walking through the door hands the player to the target
--   DH2 walking through the way back hands it home, re-promoted in place
--   DH3 ...and it stays home: it is not handed straight back through the door it arrives in
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ScopePortalDoorHomeSuite")
local T = suite.assert_test

local Shared = require("modules/core/world/shared.lua")
local GATEWAY_PEER = 15611
local reg = helpers.peer_registry({ gateway_peer = "127.0.0.1:" .. GATEWAY_PEER })
helpers.make_fixture("modules/test_fixtures/gen_portal_dh_gateway.lua", string.format([=[
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zz_gateway_peer", port = %d, scope_key = %q, world_port = %d },
        ["core/net/peer"] = {}, ["core/net/sync"] = false })
end)
]=], GATEWAY_PEER, Shared.LOCAL_GATEWAY_SCOPE, GATEWAY_PEER + 1))
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_portal_dh_gateway.lua", nil, { headless = true }), Shared.LOCAL_GATEWAY_SCOPE)

local HERE = "github:zzportaldh/here:main"
local OTHER = "github:zzportaldh/other:main"

local DEFAULTS = {
    s_hosted = false, s_home = false, s_mirror = false, s_switches = 0, s_cooling = false, s_at = "",
    t_owned = false, t_cooling = false, t_back = false, walk = false, walk_back = false,
}
local ts = helpers.shared_state("ScopePortalDoorHomeState", DEFAULTS)

-- Both worlds: the client's connection watches while it owns no player here, until a hand-over
-- brings a new place in its `synced_state`, as the client's own net leaves it.
local WATCH = [=[
local function place_of(state)
    local t = state and state.Transform and state.Transform.translation
    return t and string.format("%.2f,%.2f,%.2f", t.x, t.y, t.z) or ""
end
local had, seen = false, ""
local function watch(commands, c, owned)
    local connection = c:get("core/net/connection")
    local now = place_of(connection.synced_state)
    local observe = connection.observer
    if owned ~= nil then
        had, observe = true, false
    elseif had then
        had, seen, observe = false, now, true
    elseif observe and now ~= "" and now ~= seen then
        observe = false
    end
    if observe ~= connection.observer then
        commands:entity(c:id()):entry("core/net/connection"):and_modify(function(conn) conn.observer = observe end)
    end
end
]=]

-- A world: its net, the client's connection, its listener, its rows, its spawner and its door.
local WORLD = [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("ScopePortalDoorHomeState", boot.DEFAULTS)
]=] .. WATCH .. [=[

app:add_systems(Startup, { World, Commands }, function(world, commands)
    Net.declare_ownership(world, commands)
    local wn = commands:spawn({
        ["core/world/net"] = { mode = "server", name = boot.NAME, port = boot.PORT },
        ["core/net"] = { mode = "server", name = boot.NAME, port = boot.PORT },
        ["core/net/sync"] = false,
    })
    local c31 = commands:spawn({ ["core/net/connection"] = { client_id = 31, observer = not boot.HOME },
        ["core/net/sync"] = false, ChildOf = wn:id(), ["zz/dh/connection"] = {} }):id()
    commands:spawn({
        ["core/net/peer/listen"] = { name = boot.NAME .. "_peer", port = boot.PORT + 1, scope_key = boot.SCOPE,
            world_port = boot.PORT },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/peer/accept"] = { components = "all" },
        ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.SCOPE, mode = "server", status = "ready",
            ports = { world = boot.PORT, peer = boot.PORT + 1 }, peer_endpoint = "127.0.0.1:" .. (boot.PORT + 1) },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.OTHER_SCOPE, mode = "server", status = "ready",
            ports = { world = boot.OTHER_PORT, peer = boot.OTHER_PORT + 1 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["scope/portal"] = boot.DOOR, Name = boot.DOOR_NAME,
        Transform = { translation = boot.DOOR_AT }, ["core/net/sync"] = false, ["zz/dh/door"] = {} })
    if boot.HOME then
        commands:spawn({
            player = { client_id = 31, spawn_index = 0 },
            Transform = { translation = { x = 0, y = 0, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            ["core/net/owner"] = c31,
            ["core/net/peer/share"] = { stable_id = "player_31" },
            ["core/net/sync"] = { Transform = { authority = "server", reliable = false } },
            ["core/script/owner"] = false,
        })
    end
end)

local walked, waited, was_mirror = 0, 0, true
app:add_systems(Update, {
    World,
    Query[{ with = { "zz/dh/connection", "core/net/connection" } }],
    Query[{ with = { "zz/dh/door" }, optional = { "scope/portal/hosted", "CollidingEntities3d" } }],
    Query[{ with = { "player", "Transform" }, optional = { "core/net/peer/mirror", "core/net/owner", "scope/portal/cooling" } }],
    Commands,
}, function(world, connections, doors, players, commands)
    local c, door = connections:iter()[1], doors:iter()[1]
    local owned, mirror = nil, false
    for _, p in ipairs(players:iter()) do
        if c ~= nil and p:get("core/net/owner") == c:id() and not p:has("core/net/peer/mirror") then owned = p end
        mirror = mirror or p:has("core/net/peer/mirror")
    end
    if c ~= nil then watch(commands, c, owned) end
    if boot.HOME then
        ts.s_hosted = door ~= nil and door:has("scope/portal/hosted") and door:has("CollidingEntities3d")
        ts.s_home, ts.s_mirror = owned ~= nil, mirror
        -- Each time the player here goes from its own to handed away.
        if owned == nil and not was_mirror and mirror then ts.s_switches = ts.s_switches + 1 end
        was_mirror = owned == nil
        if owned ~= nil then
            local at = owned:get("Transform").translation
            ts.s_at = string.format("%.2f,%.2f,%.2f", at.x, at.y, at.z)
            ts.s_cooling = world:get_entity(owned:id()):has("scope/portal/cooling")
        end
    else
        ts.t_owned = owned ~= nil
        local timers = owned ~= nil and world:get_entity(owned:id()):get("cooldown") or {}
        ts.t_cooling = owned ~= nil and (world:get_entity(owned:id()):has("scope/portal/cooling") or timers["scope/portal/cooling"] ~= nil)
    end
    -- Walking in: the body moved out of the door, then into it, which Rapier reports. A player handed
    -- in arrives standing in the door it came out of.
    local go = boot.HOME and ts.walk or ts.walk_back
    if go and walked > 0 then waited = waited + world:delta_time() end
    if go and walked < 2 and owned ~= nil and door ~= nil and (walked == 0 or waited > 0.5) then
        walked = walked + 1
        local d = boot.DOOR_AT
        local to = walked == 1 and { x = d.x + 6, y = d.y, z = d.z + 6 } or d
        -- Its shadow too, as its owner's updates land there: the server eases the body toward it.
        commands:entity(owned:id()):insert({ Transform = { translation = to }, ["core/net/sync/Transform"] = { translation = to,
            rotation = { x = 0, y = 0, z = 0, w = 1 }, scale = { x = 1, y = 1, z = 1 } } })
    end
end):in_set("zz/dh_world")
]=]
helpers.make_fixture("modules/test_fixtures/gen_portal_dh_world.lua", WORLD)

-- The source's door leads to the target's `zz_e`; the target's has no target, and leads back.
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_portal_dh_world.lua", {
    DEFAULTS = DEFAULTS, NAME = "zzdh_t", PORT = 15604, SCOPE = OTHER, OTHER_SCOPE = HERE, OTHER_PORT = 15601,
    DOOR = { at = "zz_d" }, DOOR_NAME = "zz_e", DOOR_AT = { x = 0, y = 0, z = -6 },
}, { headless = true }), OTHER)
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_portal_dh_world.lua", {
    DEFAULTS = DEFAULTS, NAME = "zzdh_s", PORT = 15601, SCOPE = HERE, OTHER_SCOPE = OTHER, OTHER_PORT = 15604, HOME = true,
    DOOR = { target = OTHER, at = "zz_e" }, DOOR_NAME = "zz_d", DOOR_AT = { x = 5, y = 0, z = 0 },
}, { headless = true }), HERE)

local function said()
    return string.format("home=%s mirror=%s switches=%d at=%s cooling=%s | target owned=%s cooling=%s",
        tostring(ts.s_home), tostring(ts.s_mirror), ts.s_switches, ts.s_at, tostring(ts.s_cooling), tostring(ts.t_owned),
        tostring(ts.t_cooling))
end

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end
local function after(seconds) return function() return t - mark > seconds end end

step(within(20, function() return ts.s_hosted and ts.s_home end), function() end)
step(after(0.5), function() ts.walk = true end)
step(within(10, function() return ts.t_owned end), function()
    T("DH1_walking_through_the_door_hands_the_player_to_the_target", ts.t_owned and not ts.s_home, said())
end)
-- The target's way back links once the player names it; its cooling runs out first.
step(within(40, function() return ts.t_owned and not ts.t_cooling end), function() end)
step(after(2), function() ts.walk_back = true end)
step(within(40, function() return ts.s_home end), function()
    T("DH2_walking_through_the_way_back_hands_it_home", ts.s_home and ts.s_switches == 1, said())
end)
step(after(6), function()
    T("DH3_it_stays_home_not_handed_straight_back", ts.s_home and ts.s_switches == 1 and not ts.t_owned, said())
end)

local done = false
app:add_systems(Update, { World }, function(world)
    t = t + world:delta_time()
    if done then return end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("ScopePortalDoorHomeSuite")
    elseif s.ready(world) then
        s.act(world)
        at, mark = at + 1, t
    elseif t - mark > 30 then
        T("DH0_stuck_at_step_" .. at, false, said())
        done = true
        suite.finish("ScopePortalDoorHomeSuite")
    end
end):in_set("zz/dh_drive")
