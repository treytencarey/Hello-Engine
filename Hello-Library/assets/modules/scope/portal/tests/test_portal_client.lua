-- --host
-- scope/portal on a client: walking in asks root for a flip. Root is stubbed by this world's own
-- row, so core's flip driver leaves the asks alone; walking in is `collision_trigger` as the
-- trigger mod writes it, and the handover is `core/net/local` leaving the player, as the net
-- client takes it off when the server demotes the player.
--
--   C1  the local player walking into a portal that is not hosted asks one flip, shared with root
--   C2  walking into a hosted one asks none yet
--   C3  a portal to this world's own scope asks none
--   C4  a remote player walking in asks none
--   C5  once the player inside a hosted portal stops being this client's, one flip to its target
--   C6  in a world that only observes, walking in asks none
--   C7  a local player still cooling from its crossing (the `cooldown` its server synced) asks none
--   C8  ...and once it has cooled, walking in asks one
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ScopePortalClientSuite")
local T = suite.assert_test

local HERE = "github:zzportalc/here:main"
local OTHER = "github:zzportalc/other:main"
local SECOND = "github:zzportalc/second:main"
local THIRD = "github:zzportalc/third:main"
local FIFTH = "github:zzportalc/fifth:main"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = false },
        WorldShared = {},
        ["core/net/sync"] = false,
        ["zz/pc/row"] = {},
    })
end)

local function named(world, marker, name)
    for _, e in ipairs(world:query({ with = { marker } })) do
        if e:get(marker).name == name then return e end
    end
end

local function flips(world, scope)
    local n, shaped = 0, true
    for _, e in ipairs(world:query({ with = { "core/world/flip" }, optional = { "WorldShared", "core/net/sync" } })) do
        if e:get("core/world/flip").scope == scope then
            n = n + 1
            shaped = shaped and e:has("WorldShared") and e:get("core/net/sync") == false
        end
    end
    return n, shaped
end

local function walk(commands, world, portal, who)
    local ids = {}
    for _, name in ipairs(who) do ids[#ids + 1] = named(world, "zz/pc/h", name):id() end
    commands:entity(named(world, "zz/pc/p", portal):id()):insert({
        collision_trigger = { entered = ids, exited = {}, inside = ids },
    })
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ player = { client_id = 7 }, ["core/net/local"] = true, ["core/net/sync"] = false,
            ["zz/pc/h"] = { name = "me" } })
        commands:spawn({ player = { client_id = 8 }, ["core/net/sync"] = false, ["zz/pc/h"] = { name = "them" } })
        commands:spawn({ ["scope/portal"] = { target = OTHER }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c1" } })
        commands:spawn({ ["scope/portal"] = { target = SECOND }, ["scope/portal/hosted"] = {}, ["core/net/sync"] = false,
            ["zz/pc/p"] = { name = "c2" } })
        commands:spawn({ ["scope/portal"] = { target = HERE }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c3" } })
        commands:spawn({ ["scope/portal"] = { target = THIRD }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c4" } })
        step("spawned")

    -- The trigger mod writes its first `collision_trigger` once its sensor parts land, which would
    -- overwrite a walk written before it: walk once every portal has them, and they have settled.
    elseif phase == "spawned" and #world:query({ with = { "zz/pc/p", "CollidingEntities3d" } }) == 4 then
        step("settling")

    elseif phase == "settling" and clock > 0.5 then
        walk(commands, world, "c1", { "me" })
        walk(commands, world, "c2", { "me" })
        walk(commands, world, "c3", { "me" })
        walk(commands, world, "c4", { "them" })
        step("walked")

    elseif phase == "walked" and clock > 0.3 then
        local n, shaped = flips(world, OTHER)
        T("C1_walking_into_a_portal_that_is_not_hosted_asks_one_flip", n == 1 and shaped, "flips=" .. n)
        T("C2_walking_into_a_hosted_one_asks_none_yet", flips(world, SECOND) == 0, "")
        T("C3_a_portal_to_this_world_asks_none", flips(world, HERE) == 0, "")
        T("C4_a_remote_player_walking_in_asks_none", flips(world, THIRD) == 0, "")
        commands:entity(named(world, "zz/pc/h", "me"):id()):remove("core/net/local")
        step("handed")

    elseif phase == "handed" and clock > 0.3 then
        local n, shaped = flips(world, SECOND)
        T("C5_once_the_player_is_no_longer_its_own_it_follows_to_the_hosted_target",
            n == 1 and shaped and flips(world, OTHER) == 1, "flips=" .. n)
        commands:entity(world:query({ with = { "zz/pc/row" } })[1]:id()):insert({
            ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = true },
        })
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({ ["core/net/local"] = true })
        step("watching")

    elseif phase == "watching" and clock > 0.3 then
        walk(commands, world, "c4", { "me" })
        step("watched")

    elseif phase == "watched" and clock > 0.3 then
        T("C6_in_a_world_that_only_observes_walking_in_asks_none", flips(world, THIRD) == 0, "")
        commands:entity(world:query({ with = { "zz/pc/row" } })[1]:id()):insert({
            ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = false },
        })
        -- What a handed player arrives with from its server, which `cooldown` turns into the mark here.
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({
            cooldown = { ["scope/portal/cooling"] = { remaining = 3 } },
        })
        commands:spawn({ ["scope/portal"] = { target = FIFTH }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c5" } })
        step("cooling")

    elseif phase == "cooling" and #world:query({ with = { "zz/pc/h", "scope/portal/cooling" } }) == 1
        and named(world, "zz/pc/p", "c5") ~= nil
        and #world:query({ with = { "zz/pc/p", "CollidingEntities3d" } }) == 5 and clock > 0.5 then
        walk(commands, world, "c5", { "me" })
        step("cooled_walk")

    elseif phase == "cooled_walk" and clock > 0.3 then
        T("C7_a_player_still_cooling_asks_none", flips(world, FIFTH) == 0
            and #world:query({ with = { "zz/pc/h", "scope/portal/cooling" } }) == 1, "")
        step("cooled")

    elseif phase == "cooled" and #world:query({ with = { "zz/pc/h", "scope/portal/cooling" } }) == 0 then
        walk(commands, world, "c5", { "me" })
        step("walked_cooled")

    elseif phase == "walked_cooled" and clock > 0.3 then
        local n, shaped = flips(world, FIFTH)
        T("C8_once_it_has_cooled_walking_in_asks_one", n == 1 and shaped, "flips=" .. n)
        phase = "done"
        suite.finish("ScopePortalClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ScopePortalClientSuite")
    end
end):in_set("zz/portal_client_suite")
