-- --host
-- A client cannot get this mod's server half run for it. A real server VM gives its client an owned
-- entity, without the panel, and that client tries every way it has: adding the component to the
-- entity, spawning a new one with it, and forged UPDATEs naming it and its sync. Each attempt is seen
-- to arrive. Then the server adds the component itself, and only then does the half run.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local MessageWriter = require("bevy::prelude").MessageWriter

local suite = helpers.create_suite("FileBrowserClientCannotAddSuite")
local T = suite.assert_test

local PORT = 15193
local DEFAULTS = {
    port_up = false, carriers = 0, half_loaded = false, shadows = 0, shadow_named = false, client_field = 0,
    listed = false, give = false, take = false,
}
local ts = helpers.shared_state("FileBrowserCannotAddState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_file_browser_cannot_add.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("FileBrowserCannotAddState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzfbadd", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzfbadd", port = boot.PORT },
        ["core/net/sync"] = false,
    })
end)
-- What the client owns: an entity with no panel, and a field it may write, which shows a forged
-- update arrived.
app:add_systems(First, {
    Query[{ added = { "core/net/connection" } }],
    Commands,
}, function(connections, commands)
    for _, c in ipairs(connections:iter()) do
        commands:spawn({
            ["zz/owned"] = {},
            ["zz/field"] = { value = 0 },
            ["core/net/owner"] = { client_id = c:get("core/net/connection").client_id },
            ["core/net/sync"] = {
                ["zz/owned"] = { authority = "server" },
                ["zz/field"] = { authority = "client", target = "owner" },
            },
        })
    end
end):in_set("zz/fb_add_owned")
app:add_systems(Update, {
    World,
    Query[{ with = { "core/net/predict" } }],
    Query[{
        with = { "zz/owned" },
        optional = { "zz/field", "core/net/sync", "sidebar/file_browser" },
    }],
    Commands,
}, function(world, shadows, owned, commands)
    ts.port_up = true
    ts.carriers = #world:query({ with = { "sidebar/file_browser" } })
    for _, row in ipairs(world:query({ with = { "core/script" } })) do
        local entry = row:get("core/script").entry
        if type(entry) == "string" and entry:find("sidebar/file_browser", 1, true) then ts.half_loaded = true end
    end
    for _, s in ipairs(shadows:iter()) do
        ts.shadows = math.max(ts.shadows, shadows:count())
        local requested = s:get("core/net/predict").requested
        if type(requested) == "table" and requested["sidebar/file_browser"] ~= nil then ts.shadow_named = true end
    end
    for _, e in ipairs(owned:iter()) do
        ts.client_field = (e:get("zz/field") or {}).value or 0
        local sync = e:get("core/net/sync")
        ts.listed = type(sync) == "table" and (sync["sidebar/file_browser"] ~= nil or sync["sidebar/file_browser/request"] ~= nil)
        if ts.give and not e:has("sidebar/file_browser") then
            commands:entity(e:id()):patch({ ["sidebar/file_browser"] = {} })
        end
        if ts.take and e:has("sidebar/file_browser") then
            commands:entity(e:id()):remove("sidebar/file_browser")
        end
    end
end):in_set("zz/fb_add_report")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_file_browser_cannot_add.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })

local phase, clock = "wait_server", 0

app:add_systems(Update, {
    World,
    MessageWriter["core/net/send"],
    Commands,
}, function(world, sends, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local mine = world:query({ with = { "zz/owned", "core/net/id" }, optional = { "sidebar/file_browser", "core/net/sync" } })[1]

    if phase == "wait_server" and ts.port_up then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzfbadd_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzfbadd_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        step("joining")

    elseif phase == "joining" and mine ~= nil and clock > 0.3 then
        T("W0_the_server_gave_no_panel", ts.carriers == 0 and not ts.half_loaded)
        commands:entity(mine:id()):patch({ ["sidebar/file_browser"] = {} })
        step("patched")

    elseif phase == "patched" and clock > 1 then
        T("W1_adding_it_to_its_own_entity_stays_on_this_client", mine:has("sidebar/file_browser") and ts.carriers == 0 and not ts.half_loaded,
            ts.carriers .. " " .. tostring(ts.half_loaded))
        commands:spawn({
            ["sidebar/file_browser"] = {},
            ["sidebar/file_browser/request"] = { ["0:"] = { op = "list", path = "", offset = 0, limit = 50 } },
            ["core/net/sync"] = {
                ["sidebar/file_browser"] = { authority = "client" },
                ["sidebar/file_browser/request"] = { authority = "client" },
            },
        })
        step("spawned")

    elseif phase == "spawned" and ts.shadow_named and clock > 1 then
        T("W2_a_spawn_request_naming_it_arrives_as_a_payload_and_no_more", ts.shadows >= 1 and ts.carriers == 0 and not ts.half_loaded,
            ts.shadows .. " " .. ts.carriers .. " " .. tostring(ts.half_loaded))
        sends:write({
            msg_type = "update",
            net_id = mine:get("core/net/id").id,
            components = {
                ["zz/field"] = { value = 7 },
                ["sidebar/file_browser"] = {},
                ["sidebar/file_browser/request"] = { ["0:"] = { op = "list", path = "", offset = 0, limit = 50 } },
                ["core/net/sync"] = {
                    ["sidebar/file_browser"] = { authority = "client" },
                    ["sidebar/file_browser/request"] = { authority = "client" },
                },
            },
        })
        step("forged")

    elseif phase == "forged" and ts.client_field == 7 and clock > 0.5 then
        T("W3_a_forged_update_arrives_and_only_its_own_field_lands", ts.carriers == 0 and not ts.half_loaded and not ts.listed,
            ts.carriers .. " " .. tostring(ts.half_loaded) .. " " .. tostring(ts.listed))
        ts.give = true
        step("given")

    elseif phase == "given" and ts.half_loaded and ts.carriers == 1 and ts.listed and clock > 0.3 then
        T("W4_the_server_adding_it_runs_the_half_and_lists_its_sync", true)
        ts.give = false
        ts.take = true
        step("taken")

    elseif phase == "taken" and clock > 1 then
        T("W5_the_server_taking_it_off_takes_its_sync", ts.carriers == 0 and not ts.listed, ts.carriers .. " " .. tostring(ts.listed))
        phase = "done"
        suite.finish("FILE_BROWSER_CANNOT_ADD")
    end

    if phase ~= "done" and clock > 20 then
        T("Z_reached_" .. phase, false, string.format("stuck in phase '%s': carriers %d half %s shadows %d named %s field %d listed %s",
            phase, ts.carriers, tostring(ts.half_loaded), ts.shadows, tostring(ts.shadow_named), ts.client_field, tostring(ts.listed)))
        phase = "done"
        suite.finish("FILE_BROWSER_CANNOT_ADD")
    end
end):in_set("zz/fb_cannot_add")
