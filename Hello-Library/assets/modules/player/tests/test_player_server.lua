-- --host (windowed: under --host --headless Rapier panics in parry3d after S11, with or without this work)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerServerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

-- Connections are what the net server spawns for each client.
local function connect(commands, client_id, observer)
    commands:spawn({ ["core/net/connection"] = { client_id = client_id, observer = observer or false }, ["core/net/sync"] = false })
end

local function connection(world, client_id)
    for _, c in ipairs(world:query({ with = { "core/net/connection" } })) do
        if c:get("core/net/connection").client_id == client_id then
            return c
        end
    end
end

local function players(world, client_id)
    local out = {}
    for _, p in ipairs(world:query({
        with = { "player", "core/net/owner" },
        optional = { "abilities/fireball", "abilities/grenade", "Transform", "camera/third_person", "movement", "animation", "core/net/sync/Transform", "RigidBody3d" },
    })) do
        if p:get("core/net/owner").client_id == client_id then
            out[#out + 1] = p
        end
    end
    return out
end

local function at(world, p)
    return world:get_entity(p:id()).GlobalTransform:compute_transform().translation
end

local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-2) end

-- The map's points, as a map carries them: `player/spawner` puts players only on one.
local function points(commands)
    commands:spawn({ Name = "zz_a", Transform = { translation = { x = 2, y = 0, z = -2 } }, ["player/spawner/point"] = {}, ["core/net/sync"] = false })
    commands:spawn({ Name = "zz_b", Transform = { translation = { x = -2, y = 0, z = 2 } }, ["player/spawner/point"] = {}, ["core/net/sync"] = false })
end

local function claim(p) return p and p:get("player").spawn_point end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
        points(commands)
        connect(commands, 7)
        connect(commands, 8)
        connect(commands, 9, true)
        step("joining")

    -- Spawns land after the system that makes them, so the players arrive frames later and
    -- a long first frame can pass 0.3 s before they do: wait for them, then let them settle.
    elseif phase == "joining" and #players(world, 7) > 0 and #players(world, 8) > 0 then
        step("joined")

    elseif phase == "joined" and clock > 0.3 then
        local s = world:query({ with = { "player/spawner" } })[1]:get("player/spawner")
        suite.assert_test("S1_missing_fields_get_defaults", s.lift == 1, "")
        local seven, eight = players(world, 7), players(world, 8)
        local p = seven[1]
        local pos = p and at(world, p)
        suite.assert_test("S2_a_client_gets_one_player_at_a_spawn_point",
            #seven == 1 and claim(p) == "zz_a"
                and near(pos.x, 2) and near(pos.y, 1) and near(pos.z, -2)
                and p:get("RigidBody3d") == "KinematicPositionBased",
            pos and string.format("claim=%s at %.2f %.2f %.2f", tostring(claim(p)), pos.x, pos.y, pos.z) or "none")
        suite.assert_test("S3_the_next_client_gets_the_next_free_point", #eight == 1 and claim(eight[1]) == "zz_b", "")
        suite.assert_test("S4_a_client_only_watching_gets_no_player", #players(world, 9) == 0, "")
        suite.assert_test("S5_every_player_gets_a_camera_movement_and_its_abilities_and_no_attest_of_its_own",
            not p:has("core/player/attest") and p:has("camera/third_person") and p:has("movement") and p:has("animation") and p:has("abilities/fireball")
                and p:has("abilities/grenade")
                and p:get("player").user_id == "" and p:get("player").smoothing == 15, "")
        -- a changed connection (the net server patches them) must not spawn a second player
        connection(world, 7):patch({ ["core/net/connection"] = { ping = 1 } })
        connection(world, 9):patch({ ["core/net/connection"] = { observer = false } })
        p:patch({ ["core/net/sync/Transform"] = { translation = { x = 0, y = 5, z = 4 } } })
        -- Who the client is lands on its connection, as core/player/attest writes it.
        commands:entity(connection(world, 7):id()):insert({ ["core/player/attest"] = { state = "attested", user = "u7" } })
        step("changed")

    elseif phase == "changed" and clock > 1.0 then
        local p = players(world, 7)[1]
        local pos = at(world, p)
        suite.assert_test("S6_a_changed_connection_does_not_spawn_another", #players(world, 7) == 1, "")
        suite.assert_test("S7_a_watcher_who_joins_gets_a_player",
            #players(world, 9) == 1 and claim(players(world, 9)[1]) == "zz_a", "")
        suite.assert_test("S8_the_server_follows_the_owners_transform",
            near(pos.x, 0, 0.05) and near(pos.z, 4, 0.05), string.format("at %.2f %.2f", pos.x, pos.z))
        suite.assert_test("S9_identity_comes_from_the_join_ticket", p:get("player").user_id == "u7", "")
        connection(world, 9):patch({ ["core/net/connection"] = { observer = true } })
        commands:entity(connection(world, 7):id()):despawn()
        step("left")

    elseif phase == "left" and clock > 0.3 then
        suite.assert_test("S10_a_client_back_to_watching_loses_its_player", #players(world, 9) == 0, "")
        suite.assert_test("S11_a_client_that_left_loses_its_player_and_others_stay",
            #players(world, 7) == 0 and #players(world, 8) == 1, "")
        connect(commands, 10)
        step("reused")

    elseif phase == "reused" and clock > 0.3 then
        local ten = players(world, 10)
        suite.assert_test("S12_a_freed_point_is_used_again", #ten == 1 and claim(ten[1]) == "zz_a", "")
        players(world, 8)[1]:remove("player")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local eight = world:query({ with = { "core/net/owner" }, optional = { "camera/third_person", "movement", "animation", "abilities/fireball", "abilities/grenade" } })
        local gone = true
        for _, e in ipairs(eight) do
            if e:get("core/net/owner").client_id == 8 then
                gone = not e:has("camera/third_person") and not e:has("movement")
                    and not e:has("animation")
                    and not e:has("abilities/fireball") and not e:has("abilities/grenade")
            end
        end
        suite.assert_test("S13_removing_player_takes_off_camera_movement_and_abilities", gone, "")
        -- No spawner (its mod stops with it; players stay), then a client joins, then a
        -- new spawner comes: it serves the client already connected, and no one else twice.
        commands:entity(world:query({ with = { "player/spawner" } })[1]:id()):despawn()
        step("no spawner")

    elseif phase == "no spawner" and clock > 0.3 then
        connect(commands, 12)
        step("waiting")

    elseif phase == "waiting" and clock > 0.3 then
        suite.assert_test("S14_players_outlive_their_spawner", #players(world, 10) == 1 and #players(world, 12) == 0, "")
        -- The registry takes a mod's parts with it when its last carrier goes, the map's points
        -- among them, so a new spawner needs the map's points again.
        commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
        points(commands)
        step("new spawner")

    elseif phase == "new spawner" and clock > 0.5 then
        suite.assert_test("S15_a_new_spawner_serves_clients_already_connected",
            #players(world, 12) == 1 and #players(world, 10) == 1, "")
        phase = "done"
        suite.finish("PlayerServerSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerServerSuite")
    end
end):in_set("zz/player_server_suite")
