-- --host
-- A console's re-point over a real connection. An isolated server VM holds the door and its console
-- as a scene leaves them, and spawns real players (`player/spawner`, `player/server`); two isolated
-- client VMs join it, B only once the record exists. A asks on its own player's request, as the
-- screen writes it.
--
--   N1 A's own player arrives with the request's sync
--   N2 A's request reaches the server, which keeps one record and answers A done
--   N3 the record reaches A, and B, which joined after it was made; B hears no answer
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("PortalConsoleNetSuite")
local T = suite.assert_test

local PORT = 15483
local ROOT = "github:zzconsnet/world"
local FEATURE = ROOT .. ":feature"

local DEFAULTS = {
    srv_ready = false, srv_records = 0, srv_door = "",
    a_join = true, a_connected = false, a_slot = false, a_said = "", a_records = 0, a_ask = "",
    b_join = false, b_connected = false, b_slot = false, b_said = "", b_records = 0, b_ask = "",
}
local ts = helpers.shared_state("PortalConsoleNetState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_console_net_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PortalConsoleNetState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzcn", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzcn", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/world/status"] = { scope_key = boot.ROOT .. ":main", scope_root = boot.ROOT, mode = "server",
            status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_start",
        Transform = { translation = { x = 0, y = 0, z = 0 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        Name = "zz_door",
        ["scope/portal"] = { target = boot.ROOT .. ":prologue", at = "zz_arrival" },
        Transform = { translation = { x = 0, y = 0, z = -20 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal/console"] = { door = "zz_door", at = "zz_door" }, ["core/net/sync"] = false })
end)

app:add_systems(Update, {
    Query[{ with = { "core/net", "core/net/state" } }],
    Query[{ with = { "scope/portal/console/target" } }],
    Query[{ with = { "scope/portal", "Name" } }],
}, function(nets, records, doors)
    for _, n in ipairs(nets:iter()) do
        ts.srv_ready = ts.srv_ready or n:get("core/net/state").bound == true or n:get("core/net/state").listening == true
    end
    ts.srv_records = #records:iter()
    for _, d in ipairs(doors:iter()) do
        if d:get("Name").name == "zz_door" then ts.srv_door = tostring(d:get("scope/portal").target) end
    end
end):in_set("zz/console_net_server")
]=])

helpers.make_fixture("modules/test_fixtures/gen_console_net_client.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PortalConsoleNetState", boot.DEFAULTS)
local me = boot.NAME

-- Each client VM is a world, with its own row: without one, core's root-only systems take this VM
-- for root. The row says it only watches, so a view asks root nothing.
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/status"] = { scope_key = "zz:consolenet:" .. me, mode = "client", status = "ready", observer = true },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
end)

local joined = false
app:add_systems(Update, {
    Query[{ with = { "core/net", "core/net/state" } }],
    -- This client's own nets: what it owns is in their `core/net/owns`.
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{
        with = { "player" },
        optional = { "core/net/sync", "scope/portal/console/response" },
    }],
    Query[{ with = { "scope/portal/console/target" } }],
    Commands,
}, function(nets, own, players, records, commands)
    if ts[me .. "_join"] and not joined then
        joined = true
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzcn_" .. me, ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzcn_" .. me, ip = "127.0.0.1", port = boot.PORT },
            ["core/net/sync"] = false,
        })
    end
    for _, n in ipairs(nets:iter()) do
        ts[me .. "_connected"] = n:get("core/net/state").connected == true
    end
    for _, n in ipairs(own:iter()) do
        for _, p in ipairs(players:iter_many(n:get("core/net/owns"))) do
            local sync = p:get("core/net/sync")
            local said = p:has("scope/portal/console/response") and p:get("scope/portal/console/response") or {}
            ts[me .. "_slot"] = type(sync) == "table" and sync["scope/portal/console/request"] ~= nil
            ts[me .. "_said"] = tostring(said.status or "")
            if ts[me .. "_ask"] ~= "" then
                commands:entity(p:id()):insert({
                    ["scope/portal/console/request"] = { door = "zz_door", target = ts[me .. "_ask"] },
                })
                ts[me .. "_ask"] = ""
            end
        end
    end
    local seen = 0
    for _, r in ipairs(records:iter()) do
        local record = r:get("scope/portal/console/target")
        if record.door == "zz_door" and record.target == boot.FEATURE then seen = seen + 1 end
    end
    ts[me .. "_records"] = seen
end):in_set("zz/console_net_client")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_console_net_server.lua", { DEFAULTS = DEFAULTS, PORT = PORT, ROOT = ROOT },
    { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_console_net_client.lua",
    { DEFAULTS = DEFAULTS, PORT = PORT, NAME = "a", FEATURE = FEATURE }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_console_net_client.lua",
    { DEFAULTS = DEFAULTS, PORT = PORT, NAME = "b", FEATURE = FEATURE }, { headless = true })

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end

step(within(25, function() return ts.srv_ready and ts.a_connected and ts.a_slot end), function()
    T("N1_the_owner_s_player_arrives_with_the_request_s_sync", ts.a_connected and ts.a_slot,
        string.format("connected %s slot %s", tostring(ts.a_connected), tostring(ts.a_slot)))
    ts.a_ask = FEATURE
end)
step(within(10, function() return ts.srv_records == 1 and ts.a_said == "done" and ts.a_records == 1 end), function()
    T("N2_the_request_reaches_the_server_which_keeps_one_record", ts.srv_records == 1 and ts.srv_door == FEATURE,
        string.format("records %d door %s", ts.srv_records, ts.srv_door))
    T("N2_and_answers_the_owner_done", ts.a_said == "done", ts.a_said)
    T("N3_the_record_reaches_the_owner", ts.a_records == 1, tostring(ts.a_records))
    ts.b_join = true
end)
step(within(25, function() return ts.b_connected and ts.b_slot and ts.b_records == 1 end), function()
    T("N3_a_late_joiner_gets_the_record", ts.b_connected and ts.b_records == 1,
        string.format("connected %s records %d", tostring(ts.b_connected), ts.b_records))
    T("N3_and_hears_no_answer", ts.b_said == "", ts.b_said)
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
        suite.finish("PORTAL_CONSOLE_NET")
    elseif s.ready() then
        s.act()
        at, mark = at + 1, t
    end
end):in_set("zz/console_net_drive")
