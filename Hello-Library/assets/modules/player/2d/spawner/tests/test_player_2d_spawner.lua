-- --host
-- `player/2d/spawner` and the server half of `player/2d`, as `core/net/connection`s come and go.
--
--   D1   missing fields get defaults; a client gets one 2D player, at a spawn point in the plane
--   D2   its server body is kinematic, its Transform is the owner's and not predicted, and the body
--        replicates; the server's follow target is seeded
--   D3   its starting zoom is `camera.distance = 1`, and `camera/2d` syncs as that mod declares
--   D4   with no sheet named its sprite names no image; a world's sheet reaches its players
--   D5   every 2D player gets identity, the 2D camera and 2D movement, and nothing 3D: no `player`
--   D6   the next client gets the next free point; a client only watching gets none
--   D7   a changed connection does not spawn another, and a watcher who joins gets one
--   D8   the server follows the owner's Transform, in the plane
--   D9   identity comes from the join ticket, on the player's connection
--   D9b  a player spawned again for the same connection is who it was
--   D10  the spawner's and the mod's files edited: no second player, and it still follows
--   D11  a client back to watching, or gone, loses its player; others stay; the point is free again
--   D12  `player/2d` taken off an entity that stays takes off what the mod added
--   D13  players outlive their spawner, and a new spawner serves clients already connected
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("Player2dSpawnerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
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
        with = { "player/2d", "core/net/owner" },
        optional = {
            "camera", "camera/2d", "movement/2d", "animation/sprite", "player",
            "camera/third_person", "movement", "animation",
            "core/net/sync", "core/net/sync/Transform", "RigidBody2d", "Collider2d", "LockedAxes2d", "GravityScale2d",
        },
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

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["player/2d/spawner"] = {}, ["core/net/sync"] = false })
        connect(commands, 7)
        connect(commands, 8)
        connect(commands, 9, true)
        step("joining")

    -- Spawns land after the system that makes them, so the players arrive frames later: wait
    -- for them, then let them settle.
    elseif phase == "joining" and #players(world, 7) > 0 and #players(world, 8) > 0 then
        step("joined")

    elseif phase == "joined" and clock > 0.5 then
        local s = world:query({ with = { "player/2d/spawner" } })[1]:get("player/2d/spawner")
        local seven, eight = players(world, 7), players(world, 8)
        local p = seven[1]
        local pos = at(world, p)
        -- point 1 of 8: an eighth of a turn from +x, 96 out, in the plane
        suite.assert_test("D1_a_client_gets_one_2d_player_at_a_spawn_point_in_the_plane",
            s.count == 8 and s.radius == 96 and s.z == 0
                and #seven == 1 and p:get("player/2d").spawn_index == 1
                and near(pos.x, 67.88) and near(pos.y, 67.88) and near(pos.z, 0),
            string.format("index=%s at %.2f %.2f %.2f", tostring(p:get("player/2d").spawn_index), pos.x, pos.y, pos.z))
        local sync = p:get("core/net/sync")
        suite.assert_test("D2a_its_server_body_is_kinematic", p:get("RigidBody2d") == "KinematicPositionBased"
            and p:has("Collider2d") and p:has("LockedAxes2d") and p:has("GravityScale2d"), tostring(p:get("RigidBody2d")))
        suite.assert_test("D2b_its_transform_is_the_owners_and_not_predicted",
            sync.Transform.authority == "client" and sync.Transform.reliable == false and not sync.Transform.predict, "")
        suite.assert_test("D2c_its_body_replicates",
            sync.RigidBody2d.authority == "server" and sync.Collider2d.authority == "server"
                and sync.LockedAxes2d.authority == "server" and sync.GravityScale2d.authority == "server", "")
        suite.assert_test("D2d_the_follow_target_is_seeded_where_it_stands",
            near(p:get("core/net/sync/Transform").translation.x, 67.88), "")
        suite.assert_test("D3a_its_starting_zoom_is_1_to_1", p:has("camera") and p:get("camera").distance == 1,
            tostring(p:has("camera") and p:get("camera").distance))
        suite.assert_test("D3b_the_2d_camera_is_not_overridden_to_client_authority", (sync["camera/2d"] or {}).authority ~= "client", "")
        local sprite = p:has("animation/sprite") and p:get("animation/sprite") or {}
        suite.assert_test("D4a_with_no_sheet_named_its_sprite_names_no_image", sprite.image == nil and sprite.columns == 1, tostring(sprite.image))
        suite.assert_test("D5a_every_2d_player_gets_a_2d_camera_and_2d_movement_and_no_attest_of_its_own",
            not p:has("core/player/attest") and p:has("camera/2d") and p:has("movement/2d")
                and p:get("player/2d").user_id == "" and p:get("player/2d").smoothing == 15, "")
        suite.assert_test("D5b_and_nothing_3d",
            not p:has("player") and not p:has("camera/third_person") and not p:has("movement") and not p:has("animation"), "")
        suite.assert_test("D6a_the_next_client_gets_the_next_free_point", #eight == 1 and eight[1]:get("player/2d").spawn_index == 2, "")
        suite.assert_test("D6b_a_client_only_watching_gets_no_player", #players(world, 9) == 0, "")
        -- a changed connection (the net server patches them) must not spawn a second player
        connection(world, 7):patch({ ["core/net/connection"] = { ping = 1 } })
        connection(world, 9):patch({ ["core/net/connection"] = { observer = false } })
        p:patch({ ["core/net/sync/Transform"] = { translation = { x = 10, y = 40, z = 0 } } })
        -- Who the client is lands on its connection, as core/player/attest writes it.
        commands:entity(connection(world, 7):id()):insert({ ["core/player/attest"] = { state = "attested", user = "u7" } })
        step("changed")

    elseif phase == "changed" and clock > 1.0 then
        local p = players(world, 7)[1]
        local pos = at(world, p)
        suite.assert_test("D7a_a_changed_connection_does_not_spawn_another", #players(world, 7) == 1, "")
        suite.assert_test("D7b_a_watcher_who_joins_gets_a_player",
            #players(world, 9) == 1 and players(world, 9)[1]:get("player/2d").spawn_index == 3, "")
        suite.assert_test("D8_the_server_follows_the_owners_transform",
            near(pos.x, 10, 0.05) and near(pos.y, 40, 0.05), string.format("at %.2f %.2f", pos.x, pos.y))
        suite.assert_test("D9_identity_comes_from_the_join_ticket", p:get("player/2d").user_id == "u7", "")
        -- The mods' own files are written again with the same bytes: the watcher reloads them.
        for _, path in ipairs({ "assets/modules/player/2d/spawner/init.lua", "assets/modules/player/2d/server/init.lua" }) do
            write_file_bytes(path, read_file_bytes(path))
        end
        p:patch({ ["core/net/sync/Transform"] = { translation = { x = -30, y = 40, z = 0 } } })
        step("reloaded")

    elseif phase == "reloaded" and clock > 1.5 then
        local p = players(world, 7)[1]
        local pos = at(world, p)
        suite.assert_test("D10a_after_a_reload_there_is_no_second_player",
            #players(world, 7) == 1 and #players(world, 8) == 1 and #players(world, 9) == 1, "")
        suite.assert_test("D10b_what_each_has_stays", p:has("camera/2d") and p:has("movement/2d") and p:get("player/2d").user_id == "u7"
            and p:get("camera").distance == 1, "")
        suite.assert_test("D10c_and_it_still_follows", near(pos.x, -30, 0.05), string.format("at %.2f", pos.x))
        connection(world, 7):patch({ ["core/net/connection"] = { observer = true } })
        step("away")

    elseif phase == "away" and (#players(world, 7) == 0 or clock > 5) then
        connection(world, 7):patch({ ["core/net/connection"] = { observer = false } })
        step("back")

    elseif phase == "back" and ((#players(world, 7) == 1 and clock > 0.5) or clock > 5) then
        local p = players(world, 7)[1]
        suite.assert_test("D9b_a_player_spawned_again_is_who_it_was", p ~= nil and p:get("player/2d").user_id == "u7",
            tostring(p and p:get("player/2d").user_id))
        connection(world, 9):patch({ ["core/net/connection"] = { observer = true } })
        commands:entity(connection(world, 7):id()):despawn()
        step("left")

    elseif phase == "left" and clock > 0.3 then
        suite.assert_test("D11a_a_client_back_to_watching_loses_its_player", #players(world, 9) == 0, "")
        suite.assert_test("D11b_a_client_that_left_loses_its_player_and_others_stay",
            #players(world, 7) == 0 and #players(world, 8) == 1, "")
        connect(commands, 10)
        step("reused")

    elseif phase == "reused" and clock > 0.3 then
        local ten = players(world, 10)
        suite.assert_test("D11c_a_freed_point_is_used_again", #ten == 1 and ten[1]:get("player/2d").spawn_index == 1, "")
        players(world, 8)[1]:remove("player/2d")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local gone = false
        for _, e in ipairs(world:query({
            with = { "core/net/owner" },
            optional = { "camera/2d", "movement/2d", "animation/sprite" },
        })) do
            if e:get("core/net/owner").client_id == 8 then
                gone = not e:has("camera/2d")
                    and not e:has("movement/2d") and not e:has("animation/sprite")
            end
        end
        suite.assert_test("D12_removing_player_2d_takes_off_what_it_added", gone, "")
        -- No spawner (its mod stops with it; players stay), then a client joins, then a
        -- new spawner comes: it serves the client already connected, and no one else twice.
        commands:entity(world:query({ with = { "player/2d/spawner" } })[1]:id()):despawn()
        step("no spawner")

    elseif phase == "no spawner" and clock > 0.3 then
        connect(commands, 12)
        step("waiting")

    elseif phase == "waiting" and clock > 0.3 then
        suite.assert_test("D13a_players_outlive_their_spawner", #players(world, 10) == 1 and #players(world, 12) == 0, "")
        commands:spawn({
            ["player/2d/spawner"] = { sprite = { image = "zz.png", columns = 13 } },
            ["core/net/sync"] = false,
        })
        step("new spawner")

    elseif phase == "new spawner" and clock > 0.5 then
        suite.assert_test("D13b_a_new_spawner_serves_clients_already_connected",
            #players(world, 12) == 1 and #players(world, 10) == 1, "")
        local given = #players(world, 12) == 1 and players(world, 12)[1]:get("animation/sprite") or {}
        suite.assert_test("D4b_a_worlds_sheet_reaches_its_players", given.image == "zz.png" and given.columns == 13, tostring(given.image))
        phase = "done"
        suite.finish("Player2dSpawnerSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("D0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("Player2dSpawnerSuite")
    end
end):in_set("zz/player_2d_spawner_suite")
