-- --host
-- The player spawner's link to the players it spawns, on a world's server. Clients are
-- connections as core's net server spawns them.
--
--   L1  a client's player is linked to its spawner, which lists it, and it has its share
--   L2  a second client's player joins the list, after the first
--   L3  the spawner despawning leaves its players in the world, unlinked
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerSpawnerSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function player_of(world, client_id)
    for _, p in ipairs(world:query({
        with = { "player", "core/net/owner" },
        optional = { "player/spawner/player", "core/net/peer/share" },
    })) do
        if p:get("core/net/owner").client_id == client_id then return p end
    end
end

local function spawner(world)
    return world:query({ with = { "zz/ps/spawner" }, optional = { "player/spawner/players" } })[1]
end

local function connect(commands, client_id)
    commands:spawn({ ["core/net/connection"] = { client_id = client_id, observer = false }, ["core/net/sync"] = false })
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false, ["zz/ps/spawner"] = {} })
        connect(commands, 1)
        step("first")

    elseif phase == "first" and player_of(world, 1) ~= nil and clock > 0.3 then
        local one, s = player_of(world, 1), spawner(world)
        local link = one:get("player/spawner/player")
        local listed = s:get("player/spawner/players") or {}
        local share = one:get("core/net/peer/share")
        T("L1_a_clients_player_is_linked_to_its_spawner_which_lists_it_and_has_its_share",
            link ~= nil and link.entity == s:id() and #listed == 1 and listed[1] == one:id()
                and share ~= nil and share.stable_id == "player_1",
            string.format("link=%s listed=%d share=%s", tostring(link and link.entity), #listed,
                tostring(share and share.stable_id)))
        connect(commands, 2)
        step("second")

    elseif phase == "second" and player_of(world, 2) ~= nil and clock > 0.3 then
        local listed = spawner(world):get("player/spawner/players") or {}
        T("L2_a_second_clients_player_joins_the_list_after_the_first",
            #listed == 2 and listed[1] == player_of(world, 1):id() and listed[2] == player_of(world, 2):id(),
            "listed=" .. #listed)
        commands:entity(spawner(world):id()):despawn()
        step("gone")

    elseif phase == "gone" and clock > 0.5 then
        local one, two = player_of(world, 1), player_of(world, 2)
        T("L3_the_spawner_despawning_leaves_its_players_unlinked",
            one ~= nil and two ~= nil and not one:has("player/spawner/player") and not two:has("player/spawner/player"),
            string.format("players %s %s", tostring(one ~= nil), tostring(two ~= nil)))
        phase = "done"
        suite.finish("PlayerSpawnerSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("L0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerSpawnerSuite")
    end
end):in_set("zz/player_spawner_suite")
