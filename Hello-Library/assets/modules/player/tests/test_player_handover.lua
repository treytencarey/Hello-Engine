-- --host
-- A player handed over by another world's server, on this world's server. The handover is
-- stubbed as core's peer switch leaves it: the client's connection here, still only watching,
-- carries the mirror's state in `synced_state`, and a peer mirror is an entity with
-- `core/net/peer/mirror`.
--
--   H1  a client still only watching gets no player, handed state or not
--   H2  a client with no handed state waits while this world has no point, then gets a player on
--       the point, and every player its share's stable id
--   H3  once it stops watching, a handed player arrives where it stood although this world has no
--       point, and claims none; when a point is ready it claims it, and is not moved
--   H10 a handed player arriving while points are ready claims the least held one, and stands
--       where it was handed
--   H4  ...with its whole camera, its yaw the handed look's (relative to the body) turned by the
--       facing it arrived with, and nothing else of the handed state
--   H5  a peer mirror of a player is not set up as this world's player, but gets its abilities, to cast here
--   H6  a peer mirror is not eased toward a shadow nobody writes any more
--   H7  a player being handed over carries its whole camera, its body's place and its look, its
--       yaw relative to the body, in the switch
--   H8  a handed player keeps the timers that crossed with it (a portal's `scope/portal/cooling`), synced
--       to its owner in the spawn; a player that was not handed has no timer
--   H12 every player lists the portal's switch in its sync from its spawn, to its owner
--   H9  leaving, the look's and the body's entries join what the portal put in `transfer_data`, and
--       replace none of it
--   H11 back in place (core sets what was handed on the player whole), the camera stays whole, its
--       yaw the look turned by the facing the body arrived with, and the look goes
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local Quat = require("bevy::math::Quat")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerHandoverSuite")
local T = suite.assert_test

local HANDED = {
    Transform = {
        translation = { x = 10, y = 2, z = -4 },
        rotation = { x = 0, y = 0.70710677, z = 0, w = 0.70710677 },
    },
    ["player/spawner/look"] = { yaw = 0.3, pitch = -0.2 },
    camera = { yaw = 1.1, pitch = -0.2, distance = 5, height = 9 },
    cooldown = { ["scope/portal/cooling"] = { remaining = 3 } },
    movement = { speed = 99 },
    player = { client_id = 7, spawn_point = "zz_elsewhere", user_id = "zz-elsewhere" },
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

-- Core re-promotes a mirror in place in `First`, before `player` eases the body in `Update`.
local repromote = false
app:add_systems(First, { World, Commands }, function(world, commands)
    if repromote then
        repromote = false
        -- What was handed set whole: its body placed turned 1.0 at a door's place here, the shadow
        -- seeded there, and its camera with the yaw it had in the world it left.
        commands:entity(player_of(world, 7):id()):insert({
            Transform = { translation = { x = 4, y = 0, z = 4 }, rotation = Quat.from_rotation_y(1.0) },
            ["core/net/sync/Transform"] = { translation = { x = 4, y = 0, z = 4 }, rotation = Quat.from_rotation_y(1.0) },
            camera = { yaw = 2.9, pitch = 0.1, distance = 7, height = 3 },
            ["player/spawner/look"] = { yaw = 0.25, pitch = 0.1 },
        })
    end
end):in_set("zz/player_handover_repromote")

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

    elseif phase == "joining" and clock > 0.5 then
        T("H1_a_client_still_watching_gets_no_player", player_of(world, 7) == nil, "")
        T("H2_no_handed_state_waits_while_this_world_has_no_point", player_of(world, 8) == nil, "")
        local mirror = world:query({
            with = { "zz/ph/mirror" },
            optional = { "movement", "abilities/fireball", "abilities/grenade", "camera/third_person", "Transform" },
        })[1]
        T("H5_a_peer_mirror_is_not_set_up_here",
            not mirror:has("movement") and not mirror:has("camera/third_person"), "")
        T("H5_but_gets_its_abilities_to_cast_here", mirror:has("abilities/fireball") and mirror:has("abilities/grenade"), "")
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
        T("H3_a_handed_player_arrives_where_it_stood_with_no_point_here_and_claims_none",
            near(pos.x, 10) and near(pos.y, 2) and near(pos.z, -4)
                and near(shadow.x, 10) and near(shadow.z, -4)
                and seven:get("player").spawn_point == nil and share ~= nil and share.stable_id == "player_7",
            string.format("at %.2f %.2f %.2f claim=%s", pos.x, pos.y, pos.z, tostring(seven:get("player").spawn_point)))
        local timer = (seven:get("cooldown") or {})["scope/portal/cooling"]
        local timer_sync = (seven:get("core/net/sync") or {}).cooldown
        T("H8_a_handed_player_arrives_cooling_with_the_timer_synced_to_its_owner",
            timer ~= nil and timer.remaining == 3 and seven:has("scope/portal/cooling")
                and timer_sync ~= nil and timer_sync.authority == "server" and timer_sync.target == "owner",
            string.format("timer=%s mark=%s", tostring(timer and timer.remaining), tostring(seven:has("scope/portal/cooling"))))
        local cam = seven:get("camera") or {}
        local sync = (seven:get("core/net/sync") or {}).camera
        -- Its body arrived turned a quarter, so its look of 0.3 to the body's left is 0.3 + pi/2.
        T("H4_it_keeps_its_whole_camera_its_yaw_turned_by_the_facing_it_arrived_with_and_nothing_else",
            near(cam.yaw or 0, 0.3 + math.pi / 2) and near(cam.pitch or 0, -0.2) and cam.distance == 5
                and cam.height == 9 and sync ~= nil and sync.authority == "client" and sync.target == "owner"
                and (seven:get("movement") or {}).speed ~= 99 and seven:get("player").user_id ~= "zz-elsewhere",
            string.format("yaw=%s pitch=%s distance=%s height=%s", tostring(cam.yaw), tostring(cam.pitch),
                tostring(cam.distance), tostring(cam.height)))
        local switch_sync = (seven:get("core/net/sync") or {})["core/net/peer/switch"]
        T("H12_a_handed_player_lists_the_switch_in_its_sync_to_its_owner",
            switch_sync ~= nil and switch_sync.authority == "server" and switch_sync.target == "owner", "")
        commands:spawn({
            Name = "zz_start",
            Transform = { translation = { x = 2, y = 0, z = -3 } },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
        step("pointed")

    elseif phase == "pointed" and player_of(world, 8) ~= nil and clock > 0.3 then
        local eight = player_of(world, 8)
        local pos = at(world, eight)
        local share = eight:get("core/net/peer/share")
        T("H2_then_it_gets_a_player_on_the_point_and_the_share",
            eight:get("player").spawn_point == "zz_start" and near(pos.x, 2) and near(pos.y, 1) and near(pos.z, -3)
                and share ~= nil and share.stable_id == "player_8",
            string.format("claim=%s at %.2f %.2f %.2f", tostring(eight:get("player").spawn_point), pos.x, pos.y, pos.z))
        T("H8_a_player_not_handed_has_no_timer", not eight:has("cooldown") and not eight:has("scope/portal/cooling")
            and (eight:get("core/net/sync") or {}).cooldown == nil, "")
        local switch_sync = (eight:get("core/net/sync") or {})["core/net/peer/switch"]
        T("H12_a_fresh_player_lists_the_switch_in_its_sync_to_its_owner",
            switch_sync ~= nil and switch_sync.authority == "server" and switch_sync.target == "owner", "")
        local seven = player_of(world, 7)
        local was = at(world, seven)
        T("H3_once_a_point_is_ready_the_handed_player_claims_it_and_is_not_moved",
            seven:get("player").spawn_point == "zz_start" and near(was.x, 10) and near(was.y, 2) and near(was.z, -4),
            string.format("claim=%s at %.2f %.2f %.2f", tostring(seven:get("player").spawn_point), was.x, was.y, was.z))
        -- Its body turned 0.2, as its client moved it, and its look 0.3 to the body's left.
        commands:entity(eight:id()):insert({
            camera = { yaw = 0.5, pitch = -0.1, distance = 6, height = 2 },
            Transform = { translation = { x = 2, y = 1, z = -3 }, rotation = Quat.from_rotation_y(0.2) },
            ["core/net/sync/Transform"] = { translation = { x = 2, y = 1, z = -3 }, rotation = Quat.from_rotation_y(0.2) },
        })
        commands:spawn({
            Name = "zz_second",
            Transform = { translation = { x = 6, y = 0, z = 6 } },
            ["player/spawner/point"] = {},
            ["core/net/sync"] = false,
        })
        commands:spawn({
            ["core/net/connection"] = {
                client_id = 10,
                observer = false,
                synced_state = { Transform = { translation = { x = -7, y = 3, z = 1 }, rotation = { x = 0, y = 0, z = 0, w = 1 } } },
            },
            ["core/net/sync"] = false,
        })
        step("handed while ready")

    elseif phase == "handed while ready" and player_of(world, 10) ~= nil and clock > 0.3 then
        local ten = player_of(world, 10)
        local pos = at(world, ten)
        T("H10_a_handed_player_claims_the_least_held_ready_point_and_stands_where_it_was_handed",
            ten:get("player").spawn_point == "zz_second" and near(pos.x, -7) and near(pos.y, 3) and near(pos.z, 1),
            string.format("claim=%s at %.2f %.2f %.2f", tostring(ten:get("player").spawn_point), pos.x, pos.y, pos.z))
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
        local carried = share.transfer_data or {}
        local look = carried["player/spawner/look"] or {}
        local body = carried.Transform or {}
        local stood = body.translation or {}
        local turned = body.rotation and Quat.to_euler(body.rotation, "YXZ")[1]
        local cam = carried.camera or {}
        T("H7_leaving_it_takes_its_whole_camera_its_body_and_its_look_relative_to_the_body",
            cam.yaw == 0.5 and cam.pitch == -0.1 and cam.distance == 6 and cam.height == 2
                and near(look.yaw or 0, 0.3) and near(look.pitch or 0, -0.1) and near(stood.x or 0, 2)
                and near(stood.z or 0, -3) and turned ~= nil and near(turned, 0.2) and share.stable_id == "player_8",
            string.format("camera=%s,%s,%s,%s look=%s,%s at=%s,%s turned=%s", tostring(cam.yaw), tostring(cam.pitch),
                tostring(cam.distance), tostring(cam.height), tostring(look.yaw), tostring(look.pitch),
                tostring(stood.x), tostring(stood.z), tostring(turned)))
        local timers = carried.cooldown or {}
        T("H9_the_look_and_body_join_what_the_portal_put_in_the_switch", timers["scope/portal/cooling"] ~= nil
            and timers["scope/portal/cooling"].remaining == 3, "")
        -- Back in place, as core re-promotes a mirror that was this world's player.
        repromote = true
        step("back in place")

    elseif phase == "back in place" and clock > 0.3 then
        local seven = world:query({
            with = { "player", "core/net/owner" },
            optional = { "camera", "player/spawner/look" },
        })
        local p
        for _, e in ipairs(seven) do
            if e:get("core/net/owner").client_id == 7 then p = e end
        end
        local cam = p and p:get("camera") or {}
        T("H11_back_in_place_the_camera_stays_whole_its_yaw_the_look_turned_by_the_facing_and_the_look_goes",
            near(cam.yaw or 0, 1.25) and near(cam.pitch or 0, 0.1) and cam.distance == 7 and cam.height == 3
                and not p:has("player/spawner/look"),
            string.format("yaw=%s pitch=%s distance=%s look=%s", tostring(cam.yaw), tostring(cam.pitch),
                tostring(cam.distance), tostring(p:has("player/spawner/look"))))
        phase = "done"
        suite.finish("PlayerHandoverSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("H0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("PlayerHandoverSuite")
    end
end):in_set("zz/player_handover_suite")
