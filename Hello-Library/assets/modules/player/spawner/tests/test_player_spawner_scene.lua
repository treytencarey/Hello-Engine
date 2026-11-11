-- --host
-- The player spawner on a scene made in Blender, on a world's server: `gltf/mod_registry` turns the
-- scene's custom properties into components, and `collider/mesh` and `collider/bb` build its
-- colliders and keep `collider/status` on its root. The scene is `gltf/mod_registry`'s fixture,
-- markers.glb, whose `fx_start` (at (-1, 0, -4), turned half a turn) carries
-- `player/spawner/point`. The client connects before the scene loads.
--
--   R1 the client gets no player while the scene's colliders are not done
--   R2 once its root's `collider/status` is "done", the player spawns on fx_start, `lift` above,
--      turned to its facing, claiming it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local AssetServer = require("bevy::asset::AssetServer")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerSpawnerSceneSuite")
local T = suite.assert_test

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/connection"] = { client_id = 1, observer = false }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/rs/scene"] = {},
        SceneRoot = asset_server:load("modules/gltf/mod_registry/tests/fixtures/markers.glb#Scene0"),
        Transform = {},
        ["gltf/mod_registry"] = {},
        ["core/net/sync"] = false,
    })
end)

local function player(world)
    return world:query({ with = { "player", "core/net/owner" }, optional = { "camera" } })[1]
end

local function state(world)
    local root = world:query({ with = { "zz/rs/scene" }, optional = { "collider/status" } })[1]
    local s = root and root:get("collider/status")
    return s and s.state or "absent"
end

local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-2 end

local phase, clock = "wait", 0
local waited, early = false, false

app:add_systems(Update, { World }, function(world)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local now, p = state(world), player(world)
    if p == nil and now ~= "done" then waited = true end
    if p ~= nil and now ~= "done" then early = true end

    if phase == "wait" and p ~= nil then
        step("spawned")

    elseif phase == "spawned" and clock > 0.3 then
        p = player(world)
        local at = world:get_entity(p:id()).GlobalTransform:compute_transform().translation
        local camera = p:get("camera") or {}
        T("R1_no_player_while_the_scenes_colliders_are_not_done", waited and not early,
            "waited=" .. tostring(waited) .. " early=" .. tostring(early))
        T("R2_once_done_it_spawns_on_fx_start_lift_above_turned_to_its_facing_claiming_it",
            now == "done" and near(at.x, -1) and near(at.y, 1) and near(at.z, -4)
                and near(math.abs(camera.yaw or 0), math.pi) and p:get("player").spawn_point == "fx_start",
            string.format("status %s at %.2f %.2f %.2f yaw %s claim %s", now, at.x, at.y, at.z,
                tostring(camera.yaw), tostring(p:get("player").spawn_point)))
        phase = "done"
        suite.finish("PlayerSpawnerSceneSuite")
    end

    if phase ~= "done" and clock > 20 then
        T("R0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s; status " .. now)
        phase = "done"
        suite.finish("PlayerSpawnerSceneSuite")
    end
end):in_set("zz/player_spawner_scene_suite")
