-- --host
-- git/panel over a real connection. An isolated server VM spawns real players (`player/spawner`,
-- `player/server`), and two isolated client VMs join it. Client A asks on its player's request slot,
-- as the panel's Portal click writes it; the server's answer and the portal it opens are read on
-- both clients.
--
--   N1 each client's own player arrives with `git/panel` and the slot's sync; another client's player
--      arrives without it
--   N2 A's ask reaches the server, which opens one portal, owned by A
--   N3 every client sees the portal: on A it is A's own and being placed; on B it is neither
--   N4 A hears "opened", and B hears nothing
--   N5 once A's panel has taken its ask back, the same ask opens a second portal
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitPanelNetSuite")
local T = suite.assert_test

local PORT = 15471
local OTHER = "github:zzpanelnet/other:main"

local DEFAULTS = {
    srv_ready = false, srv_portals = 0, srv_owner = -1,
    a_connected = false, a_panel = false, a_slot = false, a_others = 0, a_portals = 0, a_local = 0,
    a_placing = 0, a_said = "", a_ask = "",
    b_connected = false, b_panel = false, b_slot = false, b_others = 0, b_portals = 0, b_local = 0,
    b_placing = 0, b_said = "", b_ask = "",
}
local ts = helpers.shared_state("GitPanelNetState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_panel_net_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("GitPanelNetState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpn", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzpn", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = { count = 4, height = 1 }, ["core/net/sync"] = false })
end)

app:add_systems(Update, {
    Query[{ with = { "core/net", "core/net/state" } }],
    Query[{ with = { "scope/portal", "core/net/owner" } }],
}, function(nets, portals)
    for _, n in ipairs(nets:iter()) do
        ts.srv_ready = ts.srv_ready or n:get("core/net/state").bound == true or n:get("core/net/state").listening == true
    end
    local list = portals:iter()
    ts.srv_portals = #list
    if list[1] ~= nil then ts.srv_owner = list[1]:get("core/net/owner").client_id end
end):in_set("zz/panel_net_server")
]=])

helpers.make_fixture("modules/test_fixtures/gen_panel_net_client.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("GitPanelNetState", boot.DEFAULTS)
local me = boot.NAME

local joined = false
app:add_systems(Update, {
    Query[{ with = { "core/net", "core/net/state" } }],
    Query[{
        with = { "player" },
        optional = { "core/net/local", "git/panel", "git/panel/response", "core/net/sync" },
    }],
    Query[{
        with = { "scope/portal" },
        optional = { "core/net/local", "placement" },
    }],
    Commands,
}, function(nets, players, portals, commands)
    if ts.srv_ready and not joined then
        joined = true
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzpn_" .. me, ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzpn_" .. me, ip = "127.0.0.1", port = boot.PORT },
            ["core/net/sync"] = false,
        })
    end
    for _, n in ipairs(nets:iter()) do
        ts[me .. "_connected"] = n:get("core/net/state").connected == true
    end
    local others = 0
    for _, p in ipairs(players:iter()) do
        if p:has("core/net/local") then
            local sync = p:get("core/net/sync")
            local said = p:has("git/panel/response") and p:get("git/panel/response") or {}
            ts[me .. "_panel"] = p:has("git/panel")
            ts[me .. "_slot"] = type(sync) == "table" and sync["git/panel/request"] ~= nil
            ts[me .. "_said"] = tostring(said.status or "")
            if ts[me .. "_ask"] ~= "" then
                commands:entity(p:id()):insert({ ["git/panel/request"] = { op = "portal", target_sk = ts[me .. "_ask"] } })
                ts[me .. "_ask"] = ""
            end
        elseif p:has("git/panel") then
            others = others + 1
        end
    end
    ts[me .. "_others"] = others
    local n, mine, placing = 0, 0, 0
    for _, p in ipairs(portals:iter()) do
        n = n + 1
        if p:has("core/net/local") then mine = mine + 1 end
        if p:has("placement") then placing = placing + 1 end
    end
    ts[me .. "_portals"], ts[me .. "_local"], ts[me .. "_placing"] = n, mine, placing
end):in_set("zz/panel_net_client")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_panel_net_server.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_panel_net_client.lua", { DEFAULTS = DEFAULTS, PORT = PORT, NAME = "a" },
    { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_panel_net_client.lua", { DEFAULTS = DEFAULTS, PORT = PORT, NAME = "b" },
    { headless = true })

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end

step(within(20, function()
    return ts.a_connected and ts.b_connected and ts.a_panel and ts.b_panel and ts.a_slot and ts.b_slot
        and ts.a_others == 0 and ts.b_others == 0
end), function()
    T("N1_each_own_player_arrives_with_git_panel_and_the_slot_s_sync", ts.a_panel and ts.b_panel
        and ts.a_slot and ts.b_slot, string.format("panel %s %s slot %s %s", tostring(ts.a_panel),
        tostring(ts.b_panel), tostring(ts.a_slot), tostring(ts.b_slot)))
    ts.a_ask = OTHER
end)
step(within(10, function() return ts.srv_portals == 1 and ts.a_portals == 1 and ts.b_portals == 1 end), function()
    T("N1_another_client_s_player_arrives_without_it", ts.a_others == 0 and ts.b_others == 0,
        string.format("a sees %d, b sees %d", ts.a_others, ts.b_others))
    T("N2_the_ask_reaches_the_server_which_opens_one_portal", ts.srv_portals == 1, tostring(ts.srv_portals))
    T("N3_every_client_sees_it", ts.a_portals == 1 and ts.b_portals == 1, ts.a_portals .. " " .. ts.b_portals)
    T("N3_on_the_asker_it_is_its_own_being_placed", ts.a_local == 1 and ts.a_placing == 1, "")
    T("N3_on_the_other_it_is_not_its_own", ts.b_local == 0, tostring(ts.b_local))
end)
step(within(5, function() return ts.a_said == "opened" end), function()
    T("N4_the_asker_hears_opened_and_the_other_nothing", ts.a_said == "opened" and ts.b_said == "",
        ts.a_said .. " / " .. ts.b_said)
end)
step(within(5, function() return ts.a_said == "" end), function()
    ts.a_ask = OTHER
end)
step(within(10, function() return ts.srv_portals == 2 and ts.a_portals == 2 and ts.b_portals == 2 end), function()
    T("N5_once_taken_back_the_same_ask_opens_a_second_portal", ts.srv_portals == 2 and ts.a_portals == 2
        and ts.b_portals == 2, string.format("server %d a %d b %d", ts.srv_portals, ts.a_portals, ts.b_portals))
end)

local done = false
app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("GitPanelNetSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 30 then
        T("N0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("GitPanelNetSuite")
    end
end):in_set("zz/panel_net_drive")
