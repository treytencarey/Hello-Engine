-- --host
-- The player spawner on a world's server: a player for each client, only on a free, ready point
-- the map carries, linked to its spawner. Clients are connections as core's net server spawns
-- them. The scene is a SceneRoot from a fixture with one node, `zz_scene_point` at (2, 0, -3),
-- turned half a turn, which the suite makes a point as `gltf/mod_registry` makes one from a
-- node's custom property; the suite writes `collider/status` on the scene root itself, as a
-- collider mod would.
--
--   W1 with no point, a client waits with no player
--   W2 ...and with its only point in a scene whose root has no status, then one that is building
--   W3 the status "done" spawns it on the point, `lift` above, turned to the point's facing,
--      claiming the point by its Name, linked to its spawner, which lists it, and with its share
--   C1 a second client takes the point nobody holds: one outside any scene, ready at once
--   C2 two more in one run: the first takes the first by name of those held least, the second
--      the one now held least
--   R1 a point made again under its name, as a re-export makes it, keeps its claims
--   R2 a point made again under a new name: the players whose point is gone claim the least held
--      ready point, the new one, and are not moved
--   L1 the spawner despawning leaves its players in the world, unlinked
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local AssetServer = require("bevy::asset::AssetServer")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerSpawnerSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false, ["zz/ps/spawner"] = {} })
end)

local function player_of(world, client_id)
    for _, p in ipairs(world:query({
        with = { "player", "core/net/owner" },
        optional = { "player/spawner/player", "core/net/peer/share", "camera" },
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

local function named(world, name)
    for _, e in ipairs(world:query({ with = { "Name" } })) do
        if e:get("Name").name == name then return e end
    end
end

local function status(world, commands, state)
    commands:entity(world:query({ with = { "zz/ps/scene" } })[1]:id()):insert({ ["collider/status"] = { state = state } })
end

local function at(world, p)
    return world:get_entity(p:id()).GlobalTransform:compute_transform().translation
end

local function near(a, b) return math.abs(a - b) < 1e-2 end

local function where(p) return p and string.format("%.2f %.2f %.2f", p.x, p.y, p.z) or "none" end

local function claim(world, client_id)
    local p = player_of(world, client_id)
    return p and p:get("player").spawn_point
end

local phase, clock = "none", 0

app:add_systems(Update, { World, Res[AssetServer], Commands }, function(world, asset_server, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "none" and clock > 0.2 then
        connect(commands, 1)
        step("no point")

    elseif phase == "no point" and clock > 0.5 then
        T("W1_with_no_point_a_client_waits_with_no_player", player_of(world, 1) == nil, "")
        commands:spawn({
            ["zz/ps/scene"] = {},
            SceneRoot = asset_server:load("modules/player/spawner/tests/fixtures/zz_scene.gltf#Scene0"),
            Transform = {},
            ["core/net/sync"] = false,
        })
        step("scene")

    elseif phase == "scene" and named(world, "zz_scene_point") ~= nil then
        commands:entity(named(world, "zz_scene_point"):id()):insert({ ["player/spawner/point"] = {} })
        step("no status")

    elseif phase == "no status" and clock > 0.5 then
        T("W2_its_only_point_in_a_scene_with_no_status_it_still_waits", player_of(world, 1) == nil, "")
        status(world, commands, "building")
        step("building")

    elseif phase == "building" and clock > 0.5 then
        T("W2_while_the_scene_is_building_it_still_waits", player_of(world, 1) == nil, "")
        status(world, commands, "done")
        step("done")

    elseif phase == "done" and player_of(world, 1) ~= nil and clock > 0.3 then
        local one, s = player_of(world, 1), spawner(world)
        local pos = at(world, one)
        local camera = one:get("camera") or {}
        local link = one:get("player/spawner/player")
        local listed = s:get("player/spawner/players") or {}
        local share = one:get("core/net/peer/share")
        T("W3_done_spawns_it_on_the_point_lift_above_turned_to_its_facing_claiming_it_by_name",
            near(pos.x, 2) and near(pos.y, 1) and near(pos.z, -3) and near(math.abs(camera.yaw or 0), math.pi)
                and claim(world, 1) == "zz_scene_point",
            string.format("at %s yaw %s claim %s", where(pos), tostring(camera.yaw), tostring(claim(world, 1))))
        T("W3_linked_to_its_spawner_which_lists_it_and_with_its_share",
            link ~= nil and link.entity == s:id() and #listed == 1 and listed[1] == one:id()
                and share ~= nil and share.stable_id == "player_1",
            string.format("link=%s listed=%d share=%s", tostring(link and link.entity), #listed,
                tostring(share and share.stable_id)))
        commands:spawn({
            Name = "zz_b",
            Transform = { translation = { x = 6, y = 0, z = 0 } },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
        connect(commands, 2)
        step("second")

    elseif phase == "second" and player_of(world, 2) ~= nil and clock > 0.3 then
        local pos = at(world, player_of(world, 2))
        T("C1_a_second_client_takes_the_point_nobody_holds",
            claim(world, 2) == "zz_b" and near(pos.x, 6) and near(pos.y, 1) and near(pos.z, 0),
            tostring(claim(world, 2)) .. " at " .. where(pos))
        connect(commands, 3)
        connect(commands, 4)
        step("more")

    elseif phase == "more" and player_of(world, 3) ~= nil and player_of(world, 4) ~= nil and clock > 0.3 then
        T("C2_then_the_least_held_the_first_by_name_of_a_tie",
            claim(world, 3) == "zz_b" and claim(world, 4) == "zz_scene_point",
            tostring(claim(world, 3)) .. " / " .. tostring(claim(world, 4)))
        -- A re-export that keeps the name: the point is made again.
        commands:entity(named(world, "zz_b"):id()):despawn()
        commands:spawn({
            Name = "zz_b",
            Transform = { translation = { x = 6, y = 0, z = 0 } },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
        step("kept")

    elseif phase == "kept" and clock > 0.3 then
        T("R1_a_point_made_again_with_its_name_keeps_its_claims", claim(world, 2) == "zz_b" and claim(world, 3) == "zz_b",
            tostring(claim(world, 2)) .. " / " .. tostring(claim(world, 3)))
        -- A re-export that renames it.
        commands:entity(named(world, "zz_b"):id()):despawn()
        commands:spawn({
            Name = "zz_c",
            Transform = { translation = { x = -6, y = 0, z = 0 } },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
        step("renamed")

    elseif phase == "renamed" and clock > 0.3 then
        local pos = at(world, player_of(world, 2))
        T("R2_players_whose_point_is_gone_claim_the_least_held_ready_point_and_are_not_moved",
            claim(world, 2) == "zz_c" and claim(world, 3) == "zz_c" and claim(world, 1) == "zz_scene_point"
                and near(pos.x, 6) and near(pos.y, 1) and near(pos.z, 0),
            tostring(claim(world, 2)) .. " / " .. tostring(claim(world, 3)) .. ", 2 at " .. where(pos))
        commands:entity(spawner(world):id()):despawn()
        step("gone")

    elseif phase == "gone" and clock > 0.5 then
        local stayed, linked = 0, 0
        for client_id = 1, 4 do
            local p = player_of(world, client_id)
            if p ~= nil then stayed = stayed + 1 end
            if p ~= nil and p:has("player/spawner/player") then linked = linked + 1 end
        end
        T("L1_the_spawner_despawning_leaves_its_players_unlinked", stayed == 4 and linked == 0,
            string.format("%d players, %d linked", stayed, linked))
        phase = "done"
        suite.finish("PlayerSpawnerSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("L0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerSpawnerSuite")
    end
end):in_set("zz/player_spawner_suite")
