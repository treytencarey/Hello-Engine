-- --host
-- A console's server half on a world's server, headless: the scene's door and console are stood in
-- as `gltf/mod_registry` leaves them (the door's custom properties in its `GltfExtras`), and the
-- owner's request is written on a player as the net delivers it.
--
--   S1 a player carrying `scope/portal/console/user` gets the request's and response's sync, the
--      owner's alone
--   S2 a request to another branch of this world's repository re-points the server's door copy at
--      the console's `at`, keeps one record, synced to everyone, and answers done
--   S3 a second request moves the same record and the door with it
--   S4 a door the scene doesn't have, or one no console names, is refused no-such-door, and the
--      door is left alone
--   S5 a target outside this world's repository is refused not-this-repository, a name that only
--      starts the same included
--   S6 pointed back at its authored target, the door keeps its authored `at`, and its record goes
--   S7 the door's scene written again spawns it with its authored target, and the record sets it again
--   S8 in a world in a folder of its repository, a branch of that folder's world is taken, and a
--      branch of the repository's top is refused not-this-repository
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("PortalConsoleServerSuite")
local T = suite.assert_test

local ROOT = "github:zzcons/world"
local HERE = ROOT .. ":main"
local AUTHORED = ROOT .. ":prologue"
local FEATURE = ROOT .. ":feature"
local OTHER = ROOT .. ":other"
local FOLDER = ROOT .. "/Hello"

local function door_bundle()
    return {
        ["zz/door"] = {},
        Name = "zz_door",
        ["scope/portal"] = { target = AUTHORED, at = "zz_arrival" },
        GltfExtras = { value = '{"scope/portal":{"target":"' .. AUTHORED .. '","at":"zz_arrival"}}' },
        Transform = { translation = { x = 0, y = 0, z = -10 } },
        ["core/net/sync"] = false,
    }
end

local player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, scope_root = ROOT, mode = "server", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn(door_bundle())
    commands:spawn({
        Name = "zz_lone",
        ["scope/portal"] = { target = AUTHORED, at = "zz_lone" },
        Transform = { translation = { x = 10, y = 0, z = -10 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal/console"] = { door = "zz_door", at = "zz_door" }, ["core/net/sync"] = false })
    player = commands:spawn({ ["zz/player"] = {}, ["scope/portal/console/user"] = {}, ["core/net/sync"] = {} }):id()
end)

local function me(world)
    return world:query({
        with = { "zz/player" },
        optional = { "core/net/sync", "scope/portal/console/response" },
    })[1]
end

local function portal(world, name)
    for _, e in ipairs(world:query({ with = { "scope/portal", "Name" } })) do
        if e:get("Name").name == name then return e:get("scope/portal") end
    end
end

local function records(world)
    local out = {}
    for _, e in ipairs(world:query({ with = { "scope/portal/console/target" }, optional = { "core/net/sync" } })) do
        out[#out + 1] = { record = e:get("scope/portal/console/target"), sync = e:get("core/net/sync") }
    end
    return out
end

local function show(p) return p and (tostring(p.target) .. " @ " .. tostring(p.at)) or "none" end

local function ask(commands, door, target)
    commands:entity(player):insert({ ["scope/portal/console/request"] = { door = door, target = target } })
end

local function said(world)
    return me(world):get("scope/portal/console/response") or {}
end

local phase, clock = "start", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "start" and clock > 0.5 then
        local sync = me(world):get("core/net/sync") or {}
        local req, res = sync["scope/portal/console/request"], sync["scope/portal/console/response"]
        T("S1_the_request_and_response_reach_the_owner_alone",
            req ~= nil and req.authority == "client" and req.target == "owner"
            and res ~= nil and res.authority == "server" and res.target == "owner")
        ask(commands, "zz_door", FEATURE)
        step("s2")

    elseif phase == "s2" and (said(world).status ~= nil or clock > 5) then
        local list = records(world)
        local r = list[1]
        T("S2_a_request_re_points_the_door_at_the_console_s_at", show(portal(world, "zz_door")) == FEATURE .. " @ zz_door",
            show(portal(world, "zz_door")))
        T("S2_and_keeps_one_record_synced_to_everyone", #list == 1 and r.record.door == "zz_door"
            and r.record.target == FEATURE and r.record.at == "zz_door"
            and type(r.sync) == "table" and r.sync["scope/portal/console/target"] ~= nil
            and r.sync["scope/portal/console/target"].authority == "server"
            and r.sync["scope/portal/console/target"].target == nil, tostring(#list))
        T("S2_and_answers_done", said(world).status == "done", tostring(said(world).status))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_door", OTHER)
        step("s3")

    elseif phase == "s3" and (said(world).status ~= nil or clock > 5) then
        local list = records(world)
        T("S3_a_second_request_moves_the_same_record_and_the_door", #list == 1 and list[1].record.target == OTHER
            and show(portal(world, "zz_door")) == OTHER .. " @ zz_door", tostring(#list) .. " " .. show(portal(world, "zz_door")))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_nowhere", FEATURE)
        step("s4a")

    elseif phase == "s4a" and (said(world).status ~= nil or clock > 5) then
        T("S4_a_door_the_scene_does_not_have_is_refused", said(world).status == "refused"
            and said(world).reason == "no-such-door", tostring(said(world).reason))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_lone", FEATURE)
        step("s4b")

    elseif phase == "s4b" and (said(world).status ~= nil or clock > 5) then
        T("S4_a_door_no_console_names_is_refused_and_left_alone", said(world).reason == "no-such-door"
            and show(portal(world, "zz_lone")) == AUTHORED .. " @ zz_lone", show(portal(world, "zz_lone")))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_door", "github:zzelse/repo:main")
        step("s5a")

    elseif phase == "s5a" and (said(world).status ~= nil or clock > 5) then
        T("S5_another_repository_is_refused", said(world).reason == "not-this-repository"
            and show(portal(world, "zz_door")) == OTHER .. " @ zz_door", tostring(said(world).reason))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_door", ROOT .. "x:main")
        step("s5b")

    elseif phase == "s5b" and (said(world).status ~= nil or clock > 5) then
        T("S5_a_repository_that_only_starts_the_same_is_refused", said(world).reason == "not-this-repository",
            tostring(said(world).reason))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_door", AUTHORED)
        step("s6")

    elseif phase == "s6" and (said(world).status ~= nil or clock > 5) then
        T("S6_pointed_back_it_keeps_its_authored_at_and_its_record_goes", said(world).status == "done"
            and show(portal(world, "zz_door")) == AUTHORED .. " @ zz_arrival" and #records(world) == 0,
            show(portal(world, "zz_door")) .. " records=" .. #records(world))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_door", FEATURE)
        step("s7 re-pointed")

    elseif phase == "s7 re-pointed" and (said(world).status ~= nil or clock > 5) then
        -- As a re-export does: the door's node goes, and a new one comes with its authored value.
        commands:entity(world:query({ with = { "zz/door" } })[1]:id()):despawn()
        commands:spawn(door_bundle())
        step("s7")

    elseif phase == "s7" and clock > 0.5 then
        T("S7_a_door_spawned_again_takes_its_record", #world:query({ with = { "zz/door" } }) == 1
            and show(portal(world, "zz_door")) == FEATURE .. " @ zz_door", show(portal(world, "zz_door")))
        -- This world becomes one in a folder of its repository, as the engine's repository's is.
        local row = world:query({ with = { "core/world/status" } })[1]
        commands:entity(row:id()):insert({
            ["core/world/status"] = { scope_key = FOLDER .. ":main", scope_root = ROOT, mode = "server", status = "ready" },
        })
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        step("s8 moved")

    elseif phase == "s8 moved" and clock > 0.2 then
        ask(commands, "zz_door", FOLDER .. ":feature")
        step("s8a")

    elseif phase == "s8a" and (said(world).status ~= nil or clock > 5) then
        T("S8_a_branch_of_this_folder_s_world_is_taken", said(world).status == "done"
            and show(portal(world, "zz_door")) == FOLDER .. ":feature @ zz_door",
            tostring(said(world).reason) .. " " .. show(portal(world, "zz_door")))
        commands:entity(player):insert({ ["scope/portal/console/response"] = {} })
        ask(commands, "zz_door", OTHER)
        step("s8b")

    elseif phase == "s8b" and (said(world).status ~= nil or clock > 5) then
        T("S8_a_branch_of_the_repository_s_top_is_refused", said(world).reason == "not-this-repository"
            and show(portal(world, "zz_door")) == FOLDER .. ":feature @ zz_door", tostring(said(world).reason))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_SERVER")
    end

    if phase ~= "done" and clock > 10 then
        T("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        suite.finish("PORTAL_CONSOLE_SERVER")
    end
end):in_set("zz/console_server")
