-- --host
-- Crossings between two worlds, each its own isolated VM, as two worlds of one process are in
-- production: each world's portals link to the other's peer listener, a player walks into one, and
-- core's peer switch hands the player over. A client's connection in a world it is not in only
-- watches, until a hand-over lands there, as the client's own net leaves it; each world's
-- `player/spawner` is real. The target's door the player comes out of has no target of its own,
-- and leads the player back.
--
--   X1 the crossing timer the portal puts in `transfer_data` reaches the target world, which accepts
--      `cooldown`
--   X2 the player spawned there from the handover is cooling, the timer synced to its owner
--   X3 ...and it has `scope/portal/from`: the world it came from and the door it came out of, synced
--      to its owner
--   X4 the door it came out of, which has no target, links back to that world at its own `at`
--   X5 walking into that door hands the player back, arriving at the door it left by, where it
--      stood at the other door, with the `from` it had here (an earlier arrival, from a third world)
--   X6 ...and the link back stays while the player that world kept names it, back another way too
--   X7 crossing through portals that are not doors carries no `from`: each world the player comes
--      back to keeps the one it had
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ScopePortalCrossSuite")
local T = suite.assert_test

-- The registry and this process's Gateway world, as production has them: every link names only its
-- world, asks root for a ticket, and finds where that world takes peers through the Gateway world,
-- which answers from each world's row (`peer_endpoint`). Root's registry calls are answered here,
-- with a throwaway key.
local Shared = require("modules/core/world/shared.lua")
local GATEWAY_PEER = 15491
local reg = helpers.peer_registry({ gateway_peer = "127.0.0.1:" .. GATEWAY_PEER })
helpers.make_fixture("modules/test_fixtures/gen_portal_cross_gateway.lua", string.format([=[
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zz_gateway_peer", port = %d, scope_key = %q, world_port = %d },
        ["core/net/peer"] = {}, ["core/net/sync"] = false })
end)
]=], GATEWAY_PEER, Shared.LOCAL_GATEWAY_SCOPE, GATEWAY_PEER + 1))
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_portal_cross_gateway.lua", nil, { headless = true }), Shared.LOCAL_GATEWAY_SCOPE)

local HERE = "github:zzportalx/here:main"
local OTHER = "github:zzportalx/other:main"
-- What each world accepts from a peer, as a world's boot declares it.
local ACCEPT = { "Transform", "cooldown", "scope/portal/from" }

local DEFAULTS = {
    s_hosted = false, s_handed = false, s_dbg = "", walk = false,
    t_timer = -1, t_cooling = false, t_synced = false,
    t_from = "", t_from_synced = false, t_back = false, t_links = -1, t_owned = false, move = false, walk_back = false,
    s_back = false, s_at = "", s_from = "", s_cooling = false, s_plain = false, walk_plain = false,
    t_plain = false, walk_home = false,
}
local ts = helpers.shared_state("ScopePortalCrossState", DEFAULTS)

-- Shared by both worlds' fixtures: the client's connection watches while it owns no player here,
-- until a hand-over brings a new place in its `synced_state`.
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

helpers.make_fixture("modules/test_fixtures/gen_portal_cross_source.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("ScopePortalCrossState", boot.DEFAULTS)
]=] .. WATCH .. [=[

app:add_systems(Startup, { World, Commands }, function(world, commands)
    -- declared first, as the net does when it starts: an owner stored before it gets no owner edge
    Net.declare_ownership(world, commands)
    local wn = commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpx_s", port = 15495 },
        ["core/net"] = { mode = "server", name = "zzpx_s", port = 15495 },
        ["core/net/sync"] = false,
    })
    -- The client's connection, as the world net spawns one: it owns what the client owns here.
    local c31 = commands:spawn({ ["core/net/connection"] = { client_id = 31 }, ["core/net/sync"] = false, ChildOf = wn:id(),
        ["zz/px/connection"] = {} }):id()
    -- A world states its scope to a peer through its own listener.
    commands:spawn({
        ["core/net/peer/listen"] = { name = "zzpx_s_peer", port = 15498, scope_key = boot.HERE, world_port = 15495 },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/accept"] = { components = boot.ACCEPT }, ["core/net/sync"] = false })
    -- This world's own row, which names it to its portals.
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.HERE, mode = "server", status = "ready", ports = { world = 15495, peer = 15498 },
            peer_endpoint = "127.0.0.1:15498" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.OTHER, mode = "server", status = "ready",
            ports = { world = 15496, peer = 15497 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["scope/portal"] = { target = boot.OTHER }, Transform = { translation = { x = -6, y = 0, z = 0 } },
        ["core/net/sync"] = false, ["zz/px/portal"] = {} })
    -- A map's door, leading to the target's door `zz_e`.
    commands:spawn({ ["scope/portal"] = { target = boot.OTHER, at = "zz_e" }, Name = "zz_d",
        Transform = { translation = { x = 5, y = 0, z = 0 } }, ["core/net/sync"] = false, ["zz/px/door"] = {} })
    commands:spawn({
        player = { client_id = 31, spawn_index = 0 },
        Transform = { translation = { x = 2, y = 0, z = 1 } },
        ["core/net/owner"] = c31,
        ["core/net/peer/share"] = { stable_id = "player_31" },
        -- An earlier arrival here, from a third world.
        ["scope/portal/from"] = { target = "zz:px:third", door = "zz_x" },
        ["core/net/sync"] = { Transform = { authority = "server", reliable = false } },
        ["core/script/owner"] = false,
    })
end)

local walked, walked_plain = false, false
app:add_systems(Update, {
    Query[{ with = { "zz/px/connection", "core/net/connection" } }],
    Query[{
        with = { "zz/px/door" },
        optional = { "scope/portal/hosted", "CollidingEntities3d" },
    }],
    Query[{
        with = { "zz/px/portal" },
        optional = { "scope/portal/hosted", "CollidingEntities3d" },
    }],
    Query[{
        with = { "player", "Transform" },
        optional = { "core/net/peer/mirror", "core/net/owner", "scope/portal/from", "scope/portal/cooling" },
    }],
    Commands,
}, function(connections, doors, portals, players, commands)
    local c = connections:iter()[1]
    local door, portal = doors:iter()[1], portals:iter()[1]
    local player, any = nil, nil
    for _, p in ipairs(players:iter()) do
        any = any or p
        if c ~= nil and p:get("core/net/owner") == c:id() and not p:has("core/net/peer/mirror") then player = p end
    end
    if c ~= nil then watch(commands, c, player) end
    ts.s_hosted = door ~= nil and door:has("scope/portal/hosted") and door:has("CollidingEntities3d")
    ts.s_plain = portal ~= nil and portal:has("scope/portal/hosted") and portal:has("CollidingEntities3d")
    ts.s_handed = player == nil and any ~= nil
    ts.s_dbg = "door=" .. tostring(door ~= nil) .. " hosted=" .. tostring(door and door:has("scope/portal/hosted")) .. " ce=" .. tostring(door and door:has("CollidingEntities3d"))
    ts.s_back = player ~= nil
    if player ~= nil then
        local at = player:get("Transform").translation
        local from = player:get("scope/portal/from")
        ts.s_at = string.format("%.2f,%.2f,%.2f", at.x, at.y, at.z)
        ts.s_from = from and (tostring(from.target) .. "|" .. tostring(from.door)) or ""
        ts.s_cooling = player:has("scope/portal/cooling")
    end
    if ts.walk and not walked and door ~= nil and player ~= nil then
        walked = true
        commands:entity(door:id()):insert({
            collision_trigger = { entered = { player:id() }, exited = {}, inside = { player:id() } },
        })
    end
    if ts.walk_plain and not walked_plain and portal ~= nil and player ~= nil then
        walked_plain = true
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
]=] .. WATCH .. [=[

app:add_systems(Startup, { Commands }, function(commands)
    local wn = commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpx_t", port = 15496 },
        ["core/net"] = { mode = "server", name = "zzpx_t", port = 15496 },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/net/peer/listen"] = { name = "zzpx_t_peer", port = 15497, scope_key = boot.OTHER, world_port = 15496 },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/accept"] = { components = boot.ACCEPT }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.OTHER, mode = "server", status = "ready", ports = { world = 15496, peer = 15497 },
            peer_endpoint = "127.0.0.1:15497" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.HERE, mode = "server", status = "ready",
            ports = { world = 15495, peer = 15498 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        ["core/net/connection"] = { client_id = 31, observer = true },
        ["core/net/sync"] = false,
        ["zz/px/connection"] = {},
        ChildOf = wn:id(),
    })
    -- The door the source's door leads to: no target of its own, and `at` naming the source's door.
    commands:spawn({ ["scope/portal"] = { at = "zz_d" }, Name = "zz_e",
        Transform = { translation = { x = 0, y = 0, z = -6 } }, ["core/net/sync"] = false, ["zz/px/entry"] = {} })
    -- A portal home that is not a door.
    commands:spawn({ ["scope/portal"] = { target = boot.HERE }, Transform = { translation = { x = 9, y = 0, z = 9 } },
        ["core/net/sync"] = false, ["zz/px/home"] = {} })
end)

local walked, walked_home = false, false
app:add_systems(Update, {
    Query[{ with = { "zz/px/connection", "core/net/connection" } }],
    Query[{
        with = { "player", "core/net/owner" },
        optional = { "scope/portal/cooling", "cooldown", "core/net/sync", "scope/portal/from", "core/net/peer/mirror" },
    }],
    Query[{ with = { "zz/px/entry" }, optional = { "CollidingEntities3d" } }],
    Query[{ with = { "zz/px/home" }, optional = { "scope/portal/hosted", "CollidingEntities3d" } }],
    Query[{ with = { "core/net/peer/link", "ChildOf" }, optional = { "core/net/peer/link/state" } }],
    Commands,
}, function(connections, players, entries, homes, links, commands)
    local c = connections:iter()[1]
    local connection = c and c:get("core/net/connection")
    local state = connection and connection.synced_state
    local timers = state and state.cooldown or {}
    local timer = timers["scope/portal/cooling"]
    if timer ~= nil and ts.t_timer < 0 then
        ts.t_timer = timer.remaining or 0
    end
    local entry, home = entries:iter()[1], homes:iter()[1]
    ts.t_plain = home ~= nil and home:has("scope/portal/hosted") and home:has("CollidingEntities3d")
    local owned = nil
    for _, p in ipairs(players:iter()) do
        if c ~= nil and p:get("core/net/owner") == c:id() and not p:has("core/net/peer/mirror") then owned = p end
    end
    if c ~= nil then watch(commands, c, owned) end
    ts.t_owned = owned ~= nil
    if owned ~= nil then
        local sync = owned:get("core/net/sync")
        local from = owned:get("scope/portal/from")
        ts.t_cooling = owned:has("scope/portal/cooling")
        ts.t_synced = type(sync) == "table" and sync.cooldown ~= nil and sync.cooldown.target == "owner"
        ts.t_from = from and (tostring(from.target) .. "|" .. tostring(from.door)) or ""
        local entry_sync = type(sync) == "table" and sync["scope/portal/from"] or nil
        ts.t_from_synced = entry_sync ~= nil and entry_sync.target == "owner" and entry_sync.authority == "server"
    end
    local count, back = 0, false
    for _, l in ipairs(links:iter()) do
        if entry ~= nil and l:get("ChildOf") == entry:id() then
            count = count + 1
            local cfg, st = l:get("core/net/peer/link"), l:get("core/net/peer/link/state")
            back = back or (cfg.name == "peer_to_" .. boot.HERE .. "@zz_e" and cfg.at == "zz_d" and cfg.scope_key == boot.HERE
                and st ~= nil and st.welcomed == true)
        end
    end
    ts.t_links, ts.t_back = count, back
    if ts.move and owned ~= nil and not walked then
        commands:entity(owned:id()):insert({ Transform = { translation = { x = 0, y = 0, z = -5 } } })
    end
    if ts.walk_back and not walked and owned ~= nil and entry ~= nil then
        walked = true
        commands:entity(entry:id()):insert({
            collision_trigger = { entered = { owned:id() }, exited = {}, inside = { owned:id() } },
        })
    end
    if ts.walk_home and not walked_home and owned ~= nil and home ~= nil then
        walked_home = true
        commands:entity(home:id()):insert({
            collision_trigger = { entered = { owned:id() }, exited = {}, inside = { owned:id() } },
        })
    end
end):in_set("zz/px_target")
]=])

reg.started(helpers.spawn_vm("modules/test_fixtures/gen_portal_cross_target.lua",
    { DEFAULTS = DEFAULTS, HERE = HERE, OTHER = OTHER, ACCEPT = ACCEPT }, { headless = true }), OTHER)
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_portal_cross_source.lua",
    { DEFAULTS = DEFAULTS, HERE = HERE, OTHER = OTHER, ACCEPT = ACCEPT }, { headless = true }), HERE)

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
step(within(5, function() return ts.t_from ~= "" and ts.t_from_synced end), function()
    T("X3_it_has_where_it_came_from_and_the_door_it_came_out_of_synced_to_its_owner",
        ts.t_from == HERE .. "|zz_e" and ts.t_from_synced, ts.t_from .. " synced=" .. tostring(ts.t_from_synced))
end)
step(within(10, function() return ts.t_back end), function()
    T("X4_the_door_it_came_out_of_links_back_at_its_own_at", ts.t_back and ts.t_links == 1,
        "links=" .. tostring(ts.t_links))
end)
step(within(6, function() return not ts.t_cooling end), function() ts.move = true end)
step(after(0.5), function() ts.walk_back = true end)
step(within(10, function() return ts.s_back and ts.s_from ~= "" end), function()
    T("X5_walking_in_hands_it_back_arriving_at_the_door_it_left_by", ts.s_back and ts.s_at == "5.00,0.00,1.00"
        and ts.s_from == "zz:px:third|zz_x", string.format("back=%s at=%s from=%s", tostring(ts.s_back), ts.s_at, ts.s_from))
end)
step(within(6, function() return not ts.s_cooling and ts.s_plain end), function() ts.walk_plain = true end)
step(within(10, function() return ts.t_owned and not ts.s_back end), function()
    T("X7_through_a_portal_not_a_door_back_in_the_target_it_keeps_the_from_it_had", ts.t_owned and ts.t_from == HERE .. "|zz_e",
        string.format("owned=%s from=%s", tostring(ts.t_owned), ts.t_from))
end)
step(after(1), function()
    T("X6_the_link_back_stays_while_the_player_it_kept_names_it", ts.t_links == 1, "links=" .. tostring(ts.t_links))
end)
step(within(6, function() return not ts.t_cooling and ts.t_plain end), function() ts.walk_home = true end)
step(within(10, function() return ts.s_back and not ts.t_owned end), function()
    T("X7_back_in_the_world_whose_entity_it_was_it_keeps_the_from_it_had", ts.s_back and ts.s_from == "zz:px:third|zz_x",
        string.format("back=%s from=%s", tostring(ts.s_back), ts.s_from))
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
