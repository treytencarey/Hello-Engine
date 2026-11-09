-- --host
-- A player handed over by another world's server, on this world's server. The handover is
-- stubbed as core's peer switch leaves it: the client's connection here, still only watching,
-- carries the mirror's state in `synced_state`, and a peer mirror is an entity with
-- `core/net/peer/mirror`.
--
--   H1  a client still only watching gets no player, handed state or not
--   H2  a client with no handed state gets a spawn point, and every player its share's stable id
--   H3  once it stops watching, a handed player arrives where it stood, still claiming a point
--   H4  ...with its camera's yaw, pitch and distance, and nothing else of the handed state
--   H5  a peer mirror of a player is not set up as this world's player
--   H6  a peer mirror is not eased toward a shadow nobody writes any more
--   H7  a player being handed over carries its camera's yaw, pitch and distance in the switch
--   H8  a handed player keeps the timers that crossed with it (a portal's `scope/portal/cooling`), synced
--       to its owner in the spawn; a player that was not handed has no timer
--   H9  leaving, the camera's entry joins what the portal put in `transfer_data`, and replaces none of it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerHandoverSuite")
local T = suite.assert_test

local HANDED = {
    Transform = {
        translation = { x = 10, y = 2, z = -4 },
        rotation = { x = 0, y = 0.70710677, z = 0, w = 0.70710677 },
    },
    camera = { yaw = 1.1, pitch = -0.2, distance = 5, height = 9 },
    cooldown = { ["scope/portal/cooling"] = { remaining = 3 } },
    movement = { speed = 99 },
    player = { client_id = 7, spawn_index = 6, user_id = "zz-elsewhere" },
    ["core/net/sync"] = { camera = { authority = "client", target = "owner" } },
}

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function player_of(world, client_id)
    for _, p in ipairs(world:query({
        with = { "player", "core/net/owner" },
        optional = {
            "core/net/peer/share", "core/net/sync/Transform", "core/net/sync", "camera", "movement",
            "cooldown", "scope/portal/cooling",
        },
    })) do
        if p:get("core/net/owner").client_id == client_id then return p end
    end
end

local function at(world, p)
    return world:get_entity(p:id()).GlobalTransform:compute_transform().translation
end

local function near(a, b) return math.abs(a - b) < 1e-2 end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
        commands:spawn({
            ["core/net/connection"] = { client_id = 7, observer = true, synced_state = HANDED },
            ["core/net/sync"] = false,
            ["zz/ph/seven"] = {},
        })
        commands:spawn({ ["core/net/connection"] = { client_id = 8, observer = false }, ["core/net/sync"] = false })
        commands:spawn({
            player = { client_id = 9, spawn_index = 0 },
            ["core/net/peer/mirror"] = { stable_id = "player_9", source_peer = "github:zzhandover/elsewhere:main" },
            Transform = { translation = { x = 5, y = 0, z = 0 } },
            ["core/net/sync/Transform"] = { translation = { x = 0, y = 0, z = 0 }, rotation = { x = 0, y = 0, z = 0, w = 1 } },
            ["core/net/sync"] = false,
            ["zz/ph/mirror"] = {},
        })
        step("joining")

    elseif phase == "joining" and player_of(world, 8) ~= nil and clock > 0.5 then
        T("H1_a_client_still_watching_gets_no_player", player_of(world, 7) == nil, "")
        local eight = player_of(world, 8)
        local pos = at(world, eight)
        local share = eight:get("core/net/peer/share")
        T("H2_no_handed_state_gets_a_spawn_point_and_the_share",
            eight:get("player").spawn_index == 1 and near(pos.x, 2.121) and near(pos.y, 5) and near(pos.z, -2.121)
                and share ~= nil and share.stable_id == "player_8",
            string.format("index=%s at %.2f %.2f %.2f", tostring(eight:get("player").spawn_index), pos.x, pos.y, pos.z))
        local mirror = world:query({
            with = { "zz/ph/mirror" },
            optional = { "movement", "abilities/fireball", "camera/third_person", "Transform" },
        })[1]
        T("H5_a_peer_mirror_is_not_set_up_here",
            not mirror:has("movement") and not mirror:has("abilities/fireball") and not mirror:has("camera/third_person"), "")
        T("H6_a_peer_mirror_is_not_eased_toward_a_stale_shadow",
            near(mirror:get("Transform").translation.x, 5), "x=" .. tostring(mirror:get("Transform").translation.x))
        local seven = world:query({ with = { "zz/ph/seven" } })[1]
        commands:entity(seven:id()):insert({
            ["core/net/connection"] = { client_id = 7, observer = false, synced_state = HANDED },
        })
        step("arrived")

    elseif phase == "arrived" and player_of(world, 7) ~= nil and clock > 0.5 then
        local seven = player_of(world, 7)
        local pos = at(world, seven)
        local shadow = seven:get("core/net/sync/Transform").translation
        local share = seven:get("core/net/peer/share")
        T("H3_a_handed_player_arrives_where_it_stood_still_claiming_a_point",
            near(pos.x, 10) and near(pos.y, 2) and near(pos.z, -4)
                and near(shadow.x, 10) and near(shadow.z, -4)
                and seven:get("player").spawn_index == 2 and share ~= nil and share.stable_id == "player_7",
            string.format("at %.2f %.2f %.2f index=%s", pos.x, pos.y, pos.z, tostring(seven:get("player").spawn_index)))
        local timer = (seven:get("cooldown") or {})["scope/portal/cooling"]
        local timer_sync = (seven:get("core/net/sync") or {}).cooldown
        local eight = player_of(world, 8)
        T("H8_a_handed_player_arrives_cooling_with_the_timer_synced_to_its_owner",
            timer ~= nil and timer.remaining == 3 and seven:has("scope/portal/cooling")
                and timer_sync ~= nil and timer_sync.authority == "server" and timer_sync.target == "owner",
            string.format("timer=%s mark=%s", tostring(timer and timer.remaining), tostring(seven:has("scope/portal/cooling"))))
        T("H8_a_player_not_handed_has_no_timer", not eight:has("cooldown") and not eight:has("scope/portal/cooling")
            and (eight:get("core/net/sync") or {}).cooldown == nil, "")
        local cam = seven:get("camera") or {}
        local sync = (seven:get("core/net/sync") or {}).camera
        T("H4_it_keeps_the_cameras_yaw_pitch_and_distance_and_nothing_else",
            near(cam.yaw or 0, 1.1) and near(cam.pitch or 0, -0.2) and cam.distance == 5 and cam.height == nil
                and sync ~= nil and sync.authority == "client" and sync.target == "owner"
                and (seven:get("movement") or {}).speed ~= 99 and seven:get("player").user_id ~= "zz-elsewhere",
            string.format("yaw=%s distance=%s height=%s", tostring(cam.yaw), tostring(cam.distance), tostring(cam.height)))
        commands:entity(player_of(world, 8):id()):insert({
            camera = { yaw = 0.5, pitch = -0.1, distance = 6, height = 2 },
        })
        step("looking")

    elseif phase == "looking" and clock > 0.2 then
        -- What a portal's handover writes, in Update, for core's switch in PostUpdate.
        commands:entity(player_of(world, 8):id()):insert({
            ["core/net/peer/switch"] = { target_scope = "github:zzhandover/elsewhere:main" },
        })
        commands:entity(player_of(world, 8):id()):entry("core/net/peer/share"):and_modify(function(share)
            share.transfer_data = { cooldown = { ["scope/portal/cooling"] = { remaining = 3 } } }
        end)
        step("leaving")

    elseif phase == "leaving" and clock > 0.2 then
        local share = player_of(world, 8):get("core/net/peer/share")
        local carried = share.transfer_data and share.transfer_data.camera or {}
        T("H7_leaving_it_takes_its_cameras_yaw_pitch_and_distance_in_the_switch",
            carried.yaw == 0.5 and carried.pitch == -0.1 and carried.distance == 6 and carried.height == nil
                and share.stable_id == "player_8",
            string.format("yaw=%s distance=%s", tostring(carried.yaw), tostring(carried.distance)))
        local timers = share.transfer_data and share.transfer_data.cooldown or {}
        T("H9_the_camera_joins_what_the_portal_put_in_the_switch", timers["scope/portal/cooling"] ~= nil
            and timers["scope/portal/cooling"].remaining == 3, "")
        phase = "done"
        suite.finish("PlayerHandoverSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("H0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerHandoverSuite")
    end
end):in_set("zz/player_handover_suite")
