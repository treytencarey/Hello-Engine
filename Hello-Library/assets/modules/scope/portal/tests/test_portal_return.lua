-- --host
-- A portal's return end, between two worlds, each its own isolated VM, as two worlds of one process
-- are in production: each world's row, shared, is what the other's server links by. A player drops
-- a portal in the source world to the target; once it is hosted it stands in the target too,
-- leading back. The player crosses through it, then walks back through the return end. The target's
-- client is a connection that only watches until the handover lands; its `player/spawner` is real,
-- and so is its physics, which says who walks into the return end there.
--
--   R1 in the target the return end appears, a portal to the source at the portal's place, shown
--      as the portal is, replicated to the target's clients with `scope/portal/hosted`
--   R2 in the source it is the portal's (`scope/portal/return`), leads to the source itself, and
--      has no link and no mark
--   R3 a scene's door and a portal still being placed get none; a second later, the target has
--      made none of its own for the mirror, and the source holds no mirror of a portal
--   R4 the target's server hosts it: its link to the source is up
--   R5 in the source, walking into the return end hands nobody over
--   R6 a reload of the server half keeps one return end, the same, and one mirror in the target
--   R7 a player handed over through the portal arrives inside the return end, cooling
--   R8 ...and staying inside after the timer ends, it is not handed back
--   R9 ...walking out and in again hands it back to the source
--   R10 the target's link going takes the return end, here and in the target
--   R11 ...and it comes back with the link
--   R12 the portal despawned takes its return end, here and in the target
--   R13 the portal that was being placed, once placed, gets its own, at its place
--   R14 `scope/portal` taken off it, the entity staying, takes its return end, here and there
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ScopePortalReturnSuite")
local T = suite.assert_test

local HERE = "github:zzportalr/here:main"
local OTHER = "github:zzportalr/other:main"
local SERVER = "assets/modules/scope/portal/server/init.lua"
-- What each world accepts from a peer, as a world's boot declares it.
local ACCEPT = { "Transform", "cooldown", "scope/portal", "scope/portal/view", "scope/portal/hosted" }

local DEFAULTS = {
    x_hosted = false, x_ends = 0, x_end_ok = false, x_end = "", x_door = false, x_placing = false,
    x_mirrors = 0, x_owned = false, x_same = false,
    x_mark = false, x_walk_end = false, x_walk = false, x_despawn = false, x_place = false, x_unportal = false,
    y_mirrors = 0, y_end_ok = false, y_end = "", y_at_x = 0, y_hosted = false, y_returns = 0, y_same = false,
    y_arrived = false, y_owned = false, y_handed = false, y_cooling = false, y_inside = false,
    y_mark = false, y_go = "", y_status = "ready",
}
local ts = helpers.shared_state("ScopePortalReturnState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_portal_return_x.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("ScopePortalReturnState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpr_x", port = 15515 },
        ["core/net"] = { mode = "server", name = "zzpr_x", port = 15515 },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/net/peer/listen"] = { name = "zzpr_x_peer", port = 15518, scope_key = boot.HERE, world_port = 15515 },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/accept"] = { components = boot.ACCEPT }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.HERE, mode = "server", status = "ready",
            ports = { world = 15515, peer = 15518 } },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    -- As `git/panel`'s server half drops one.
    commands:spawn({
        ["scope/portal"] = { target = boot.OTHER },
        ["scope/portal/view"] = { mode = "3d" },
        Transform = { translation = { x = 2, y = 0, z = 1 } },
        ["core/net/owner"] = { client_id = 41 },
        ["core/net/sync"] = {
            Transform = { authority = "server" },
            ["scope/portal"] = { authority = "server" },
            ["scope/portal/view"] = { authority = "server" },
            ["scope/portal/hosted"] = { authority = "server" },
        },
        ["core/script/owner"] = false,
        ["zz/pr/p"] = { name = "drop" },
    })
    -- A scene's door, as `gltf/mod_registry` makes one: never replicated.
    commands:spawn({
        ["scope/portal"] = { target = boot.OTHER },
        ["scope/portal/view"] = { mode = "none" },
        Transform = { translation = { x = -6, y = 0, z = 0 } },
        ["core/net/sync"] = false,
        ["zz/pr/p"] = { name = "door" },
    })
    commands:spawn({
        ["scope/portal"] = { target = boot.OTHER },
        ["scope/portal/view"] = { mode = "3d" },
        placement = {},
        Transform = { translation = { x = 9, y = 0, z = 0 } },
        ["core/net/owner"] = { client_id = 41 },
        ["core/net/sync"] = {
            placement = { authority = "client" },
            Transform = { authority = "client", reliable = false },
            ["scope/portal"] = { authority = "server" },
            ["scope/portal/view"] = { authority = "server" },
            ["scope/portal/hosted"] = { authority = "server" },
        },
        ["core/script/owner"] = false,
        ["zz/pr/p"] = { name = "placing" },
    })
    commands:spawn({
        player = { client_id = 41 },
        Transform = { translation = { x = 2, y = 0, z = 1 } },
        ["core/net/owner"] = { client_id = 41 },
        ["core/net/peer/share"] = { stable_id = "player_41" },
        ["core/net/sync"] = { Transform = { authority = "server", reliable = false } },
        ["core/script/owner"] = false,
        ["zz/pr/player"] = {},
    })
end)

local kept, walked_end, walked, gone, placed, unportaled = nil, false, false, false, false, false
app:add_systems(Update, { World, Commands }, function(world, commands)
    local portals = {}
    for _, e in ipairs(world:query({
        with = { "zz/pr/p", "scope/portal" },
        optional = { "scope/portal/hosted", "scope/portal/returns", "placement" },
    })) do
        portals[e:get("zz/pr/p").name] = e
    end
    local drop, door, placing = portals.drop, portals.door, portals.placing
    local ends = world:query({
        with = { "scope/portal", "core/net/peer/share" },
        without = { "core/net/peer/mirror" },
        optional = { "scope/portal/return", "scope/portal/hosted", "Transform" },
    })
    local r = ends[1]
    local player = world:query({
        with = { "zz/pr/player" },
        optional = { "core/net/owner", "core/net/peer/mirror" },
    })[1]
    ts.x_hosted = drop ~= nil and drop:has("scope/portal/hosted")
    ts.x_ends = #ends
    ts.x_door = door ~= nil and door:has("scope/portal/hosted") and not door:has("scope/portal/returns")
    ts.x_placing = placing ~= nil and not placing:has("scope/portal/returns")
    ts.x_mirrors = #world:query({ with = { "scope/portal", "core/net/peer/mirror" } })
    ts.x_owned = player ~= nil and player:has("core/net/owner") and not player:has("core/net/peer/mirror")
    if r ~= nil then
        local target = r:get("scope/portal").target
        local place = r:get("Transform")
        local at = place and place.translation or {}
        local link = r:get("scope/portal/return")
        local listed = drop and drop:get("scope/portal/returns") or {}
        local links = 0
        for _, l in ipairs(world:query({ with = { "core/net/peer/link", "ChildOf" } })) do
            if l:get("ChildOf") == r:id() then links = links + 1 end
        end
        ts.x_end_ok = target == boot.HERE and at.x == 2 and at.y == 0 and at.z == 1
            and link ~= nil and drop ~= nil and link.entity == drop:id() and #listed == 1 and listed[1] == r:id()
            and not r:has("scope/portal/hosted") and links == 0
        ts.x_end = string.format("target=%s at=%s,%s,%s linked=%s listed=%d hosted=%s links=%d",
            tostring(target), tostring(at.x), tostring(at.y), tostring(at.z),
            tostring(link ~= nil and drop ~= nil and link.entity == drop:id()), #listed,
            tostring(r:has("scope/portal/hosted")), links)
        ts.x_same = kept ~= nil and r:id() == kept
    else
        ts.x_end_ok, ts.x_end, ts.x_same = false, "none", false
    end
    if ts.x_mark and kept == nil and r ~= nil then kept = r:id() end
    if ts.x_walk_end and not walked_end and r ~= nil and player ~= nil then
        walked_end = true
        commands:entity(r:id()):insert({
            collision_trigger = { entered = { player:id() }, exited = {}, inside = { player:id() } },
        })
    end
    if ts.x_walk and not walked and drop ~= nil and player ~= nil then
        walked = true
        commands:entity(drop:id()):insert({
            collision_trigger = { entered = { player:id() }, exited = {}, inside = { player:id() } },
        })
    end
    if ts.x_despawn and not gone and drop ~= nil then
        gone = true
        commands:entity(drop:id()):despawn()
    end
    if ts.x_place and not placed and placing ~= nil then
        placed = true
        commands:entity(placing:id()):remove("placement")
    end
    if ts.x_unportal and not unportaled and placing ~= nil then
        unportaled = true
        commands:entity(placing:id()):remove("scope/portal")
    end
end):in_set("zz/pr_x")
]=])

helpers.make_fixture("modules/test_fixtures/gen_portal_return_y.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("ScopePortalReturnState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpr_y", port = 15516 },
        ["core/net"] = { mode = "server", name = "zzpr_y", port = 15516 },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/net/peer/listen"] = { name = "zzpr_y_peer", port = 15517, scope_key = boot.OTHER, world_port = 15516 },
        ["core/net/peer"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["core/net/peer/accept"] = { components = boot.ACCEPT }, ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        ["core/net/connection"] = { client_id = 41, observer = true },
        ["core/net/sync"] = false,
        ["zz/pr/connection"] = {},
    })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.OTHER, mode = "server", status = "ready",
            ports = { world = 15516, peer = 15517 } },
        WorldShared = {},
        ["core/net/sync"] = false,
        ["zz/pr/row"] = {},
    })
end)

local kept, flipped, went = nil, false, ""
app:add_systems(Update, { World, Commands }, function(world, commands)
    local c = world:query({ with = { "zz/pr/connection", "core/net/connection" } })[1]
    local connection = c and c:get("core/net/connection")
    local handed = connection and connection.synced_state
    if handed ~= nil and handed.cooldown ~= nil and not flipped then
        flipped = true
        commands:entity(c:id()):entry("core/net/connection"):and_modify(function(conn) conn.observer = false end)
    end
    local mirrors = world:query({
        with = { "scope/portal", "core/net/peer/mirror" },
        optional = { "scope/portal/hosted", "Transform", "scope/portal/view", "collision_trigger", "core/net/sync",
            "RigidBody3d" },
    })
    local m = mirrors[1]
    ts.y_mirrors = #mirrors
    ts.y_returns = #world:query({ with = { "scope/portal/return" } })
    ts.y_hosted = m ~= nil and m:has("scope/portal/hosted")
    if m ~= nil then
        local target = m:get("scope/portal").target
        local place = m:get("Transform")
        local at = place and place.translation or {}
        local view = m:get("scope/portal/view")
        local sync = m:get("core/net/sync")
        local listed = type(sync) == "table" and sync["scope/portal/hosted"] ~= nil and sync["scope/portal"] ~= nil
            and sync["scope/portal/view"] ~= nil
        ts.y_end_ok = target == boot.HERE and at.x == 2 and at.y == 0 and at.z == 1 and view ~= nil
            and view.mode == "3d" and listed and m:get("RigidBody3d") == "Fixed"
        ts.y_end = string.format("target=%s at=%s,%s,%s view=%s synced=%s body=%s", tostring(target),
            tostring(at.x), tostring(at.y), tostring(at.z), tostring(view and view.mode), tostring(listed),
            tostring(m:get("RigidBody3d")))
        ts.y_same = kept ~= nil and m:id() == kept
        ts.y_at_x = at.x or 0
        if ts.y_mark and kept == nil then kept = m:id() end
    else
        ts.y_end_ok, ts.y_end, ts.y_same, ts.y_at_x = false, "none", false, 0
    end
    local p
    for _, e in ipairs(world:query({
        with = { "player" },
        optional = { "core/net/owner", "core/net/peer/mirror", "scope/portal/cooling" },
    })) do
        if e:get("player").client_id == 41 then p = e end
    end
    ts.y_arrived = p ~= nil
    ts.y_owned = p ~= nil and p:has("core/net/owner") and not p:has("core/net/peer/mirror")
    ts.y_handed = p ~= nil and p:has("core/net/peer/mirror")
    ts.y_cooling = p ~= nil and p:has("scope/portal/cooling")
    local trigger = m and m:get("collision_trigger")
    local inside = false
    for _, id in ipairs(trigger and trigger.inside or {}) do
        if p ~= nil and id == p:id() then inside = true end
    end
    ts.y_inside = inside
    -- Where its client would move it: the server's player follows this shadow (`player`).
    local go = ts.y_go
    if p ~= nil and go ~= went and go ~= "" then
        went = go
        commands:entity(p:id()):insert({
            ["core/net/sync/Transform"] = {
                translation = { x = go == "out" and 20 or 2, y = 0, z = 1 },
                rotation = { x = 0, y = 0, z = 0, w = 1 },
            },
        })
    end
    local row = world:query({ with = { "zz/pr/row", "core/world/status" } })[1]
    local status = ts.y_status
    if row ~= nil and row:get("core/world/status").status ~= status then
        commands:entity(row:id()):entry("core/world/status"):and_modify(function(s) s.status = status end)
    end
end):in_set("zz/pr_y")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_portal_return_y.lua",
    { DEFAULTS = DEFAULTS, HERE = HERE, OTHER = OTHER, ACCEPT = ACCEPT }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_portal_return_x.lua",
    { DEFAULTS = DEFAULTS, HERE = HERE, OTHER = OTHER, ACCEPT = ACCEPT }, { headless = true })

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end
local function after(seconds) return function() return t - mark > seconds end end
local function ends() return string.format("x: hosted=%s ends=%d %s | y: mirrors=%d hosted=%s %s",
    tostring(ts.x_hosted), ts.x_ends, ts.x_end, ts.y_mirrors, tostring(ts.y_hosted), ts.y_end) end

step(within(20, function() return ts.x_end_ok and ts.y_end_ok and ts.y_hosted end), function()
    T("R1_in_the_target_the_return_end_is_a_portal_back_at_the_portal_s_place", ts.y_mirrors == 1 and ts.y_end_ok,
        ends())
    T("R2_in_the_source_it_is_the_portal_s_leads_here_and_has_no_link_or_mark", ts.x_ends == 1 and ts.x_end_ok,
        ends())
    T("R3_a_door_and_a_portal_being_placed_get_none", ts.x_door and ts.x_placing,
        string.format("door=%s placing=%s", tostring(ts.x_door), tostring(ts.x_placing)))
    T("R4_the_target_hosts_it", ts.y_hosted, ends())
    ts.x_walk_end = true
end)
step(after(1), function()
    T("R3_the_target_makes_none_for_the_mirror_and_the_source_holds_no_mirror_of_a_portal",
        ts.y_returns == 0 and ts.x_mirrors == 0, string.format("y_returns=%d x_mirrors=%d", ts.y_returns, ts.x_mirrors))
    T("R5_walking_into_it_in_the_source_hands_nobody_over", ts.x_owned and not ts.y_arrived,
        string.format("owned=%s arrived=%s", tostring(ts.x_owned), tostring(ts.y_arrived)))
    ts.x_mark, ts.y_mark = true, true
end)
step(after(0.5), function()
    write_file_bytes(SERVER, read_file_bytes(SERVER))
end)
step(after(4), function()
    T("R6_a_reload_keeps_one_return_end_the_same_and_one_mirror",
        ts.x_ends == 1 and ts.x_same and ts.x_end_ok and ts.y_mirrors == 1 and ts.y_same and ts.y_hosted,
        string.format("same x=%s y=%s; %s", tostring(ts.x_same), tostring(ts.y_same), ends()))
end)
step(within(10, function() return ts.x_hosted and ts.y_hosted and ts.x_ends == 1 and ts.y_mirrors == 1 end),
    function()
        ts.x_walk = true
    end)
step(within(15, function() return ts.y_owned and ts.y_inside end), function()
    T("R7_handed_over_it_arrives_inside_the_return_end_cooling",
        ts.y_owned and ts.y_inside and ts.y_cooling and not ts.x_owned,
        string.format("owned=%s inside=%s cooling=%s source_owned=%s", tostring(ts.y_owned), tostring(ts.y_inside),
            tostring(ts.y_cooling), tostring(ts.x_owned)))
end)
step(within(10, function() return ts.y_owned and not ts.y_cooling end), function() end)
step(after(1.5), function()
    T("R8_staying_inside_after_the_timer_it_is_not_handed_back",
        ts.y_owned and ts.y_inside and not ts.y_cooling and not ts.x_owned,
        string.format("owned=%s inside=%s cooling=%s", tostring(ts.y_owned), tostring(ts.y_inside),
            tostring(ts.y_cooling)))
    ts.y_go = "out"
end)
step(within(5, function() return not ts.y_inside end), function()
    ts.y_go = "in"
end)
step(within(10, function() return ts.x_owned and ts.y_handed end), function()
    T("R9_walking_out_and_in_again_hands_it_back", ts.x_owned and ts.y_handed,
        string.format("source_owned=%s target_handed=%s", tostring(ts.x_owned), tostring(ts.y_handed)))
    ts.y_status = "starting"
end)
step(within(10, function() return not ts.x_hosted and ts.x_ends == 0 and ts.y_mirrors == 0 end), function()
    T("R10_the_link_going_takes_the_return_end_here_and_there",
        not ts.x_hosted and ts.x_ends == 0 and ts.y_mirrors == 0, ends())
    ts.y_status = "ready"
end)
step(within(15, function() return ts.x_hosted and ts.x_end_ok and ts.y_end_ok end), function()
    T("R11_it_comes_back_with_the_link", ts.x_ends == 1 and ts.x_end_ok and ts.y_mirrors == 1 and ts.y_end_ok, ends())
    ts.x_despawn = true
end)
step(within(10, function() return ts.x_ends == 0 and ts.y_mirrors == 0 end), function()
    T("R12_the_portal_despawned_takes_it_here_and_there", ts.x_ends == 0 and ts.y_mirrors == 0, ends())
    ts.x_place = true
end)
step(within(10, function() return ts.x_ends == 1 and ts.y_mirrors == 1 and ts.y_at_x == 9 end), function()
    T("R13_once_placed_the_other_portal_gets_its_own_at_its_place",
        ts.x_ends == 1 and ts.y_mirrors == 1 and ts.y_at_x == 9, ends())
    ts.x_unportal = true
end)
step(within(10, function() return ts.x_ends == 0 and ts.y_mirrors == 0 end), function()
    T("R14_scope_portal_taken_off_a_portal_that_stays_takes_it_here_and_there",
        ts.x_ends == 0 and ts.y_mirrors == 0, ends())
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
        suite.finish("ScopePortalReturnSuite")
    elseif s.ready(world) then
        s.act(world)
        at, mark = at + 1, t
    elseif t - mark > 30 then
        T("R0_stuck_at_step_" .. at, false, ends())
        done = true
        suite.finish("ScopePortalReturnSuite")
    end
end):in_set("zz/pr_drive")
