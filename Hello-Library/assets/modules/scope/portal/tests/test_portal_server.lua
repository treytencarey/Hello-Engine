-- --host
-- scope/portal on a server. The target's server is stubbed by its row and by a real peer listener
-- in this VM that answers as the target's scope; the link the portal makes dials it and is
-- welcomed. Walking in is `collision_trigger` as the trigger mod writes it. A portal being placed
-- is spawned as `git/panel`'s server half spawns one.
--
--   P6  one identity link to each target running here, however many portals name it
--   P25 a door (`at`, on a named node) to the same target gets a link of its own, its child, named
--       for the door, carrying `at` and the door's world transform; a door to a target whose
--       link is not welcomed gets its own too
--   P7  a welcomed link marks the portals to its target hosted, and a door's own welcomed link
--       (its place found there) marks the door
--   P8  a link that is not welcomed marks nothing
--   P9  a target with no row here gets no link and no mark
--   P10 a player walking into a hosted portal is handed over to its target, on its identity link
--   P26 a player walking into a door is handed over on the door's link
--   P11 with no welcomed link to the target, the player is handed over all the same (core releases
--       it), on its join's link, a portal's and a door's alike
--   P12 a peer mirror, or a player with no share, is not handed over
--   P27 a portal's return end does not copy its `at`
--   P13 a portal still being placed has no body and no trigger; a placed one has a fixed ball body
--       of radius 1.2 and a trigger
--   P14 ...and the one being placed gets them once placed
--   P19 a player walking into a portal still being placed is not handed over
--   P15 taking `scope/portal` off a portal that stays takes its body, trigger, mark and link
--   P16 ...and another portal to that target takes the link
--   P10b ...taking a 3 s crossing timer with it in `transfer_data`
--   P17 a player still cooling from its crossing (`cooldown`'s `scope/portal/cooling`) is not handed
--       over
--   P18 ...and once it has cooled, walking in again hands it over
--   P20 with real physics: a hosted portal dropped where a player stands reads it inside and hands
--       it nobody over, as only walking in counts
--   P21 ...nor a player spawned inside it, as one spawns inside a door
--   P22 ...and the first walking out and back in is handed over
--   P23 a scene's door spawned around a standing player reads it inside and hands it nobody over
--   P24 no portal reaches Rapier as a solid ball: in every frame, one with a collider is a sensor
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("ScopePortalServerSuite")
local T = suite.assert_test

local HERE = "github:zzportal/here:main"
local OTHER = "github:zzportal/other:main"
local FOURTH = "github:zzportal/fourth:main"
local THIRD = "github:zzportal/third:main"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, mode = "server", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
end)

local function named(world, marker, name)
    for _, e in ipairs(world:query({
        with = { marker },
        optional = {
            "scope/portal", "scope/portal/view", "scope/portal/hosted", "placement", "Transform",
            "core/net/sync", "core/script/owner", "core/net/peer/switch", "scope/portal/cooling",
            "RigidBody3d", "Collider3d", "collision_trigger", "Children",
        },
    })) do
        if e:get(marker).name == name then return e end
    end
end

-- The identity links to `scope`, or with `door` its doors' links.
local function links(world, scope, door)
    local out = {}
    for _, e in ipairs(world:query({ with = { "core/net/peer/link" }, optional = { "core/net/peer/link/state", "ChildOf" } })) do
        local cfg = e:get("core/net/peer/link")
        if cfg.scope_key == scope and (cfg.at ~= nil) == (door == true) then out[#out + 1] = e end
    end
    return out
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-3 end

-- Core's switch takes `core/net/peer/switch` off in the same frame when it finds no peer for the
-- target, so what the portal asked for is read on its edge, right after the portal's systems.
local switched, carried, via = {}, {}, {}
app:add_systems(Update, {
    Query[{
        added = { "core/net/peer/switch" },
        with = { "zz/portal/h" },
        optional = { "core/net/peer/share" },
    }],
}, function(rows)
    for _, r in ipairs(rows:iter()) do
        local name = r:get("zz/portal/h").name
        switched[name] = r:get("core/net/peer/switch").target_scope
        via[name] = r:get("core/net/peer/switch").link
        local share = r:get("core/net/peer/share") or {}
        local timers = share.transfer_data and share.transfer_data.cooldown or {}
        carried[name] = timers["scope/portal/cooling"] and timers["scope/portal/cooling"].remaining
    end
end):in_set("zz/portal_switch_seen"):after("scope/portal/server")

local phase, clock = "listen", 0

-- Lua's PostUpdate systems run before Rapier's, which build what they find. Counted once the first
-- triggers have their parts: the first trigger in a world loads `collision_trigger`, which adds them
-- a frame later.
local solid = 0
app:add_systems(PostUpdate, { World }, function(world)
    if phase ~= "listen" and phase ~= "binding" and phase ~= "linking" then
        solid = solid + #world:query({ with = { "scope/portal", "Collider3d" }, without = { "Sensor3d" } })
    end
end):in_set("zz/portal_solid")
local bound_port
local link_holder

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "listen" then
        commands:spawn({
            ["core/net/peer/listen"] = { port = 47731, name = "peer_zzportal", scope_key = OTHER, world_port = 47730 },
            ["core/net/peer"] = {},
            ["core/net/sync"] = false,
        })
        commands:spawn({
            ["scope/portal"] = { target = OTHER },
            ["scope/portal/view"] = { mode = "3d" },
            placement = {},
            Transform = { translation = { x = 1, y = 0, z = 2 } },
            ["core/net/sync"] = {
                placement = { authority = "client" },
                Transform = { authority = "client", reliable = false },
                ["scope/portal"] = { authority = "server" },
            },
            ["zz/portal/p"] = { name = "a1" },
        })
        step("binding")

    elseif phase == "binding" then
        local listener = world:query({ with = { "core/net/peer/state", "core/net/peer/listen" } })[1]
        if listener and listener:get("core/net/peer/state").bound then
            bound_port = listener:get("core/net/peer/listen").port
            commands:spawn({
                ["core/world/status"] = { scope_key = OTHER, mode = "server", status = "ready",
                    ports = { world = 47730, peer = bound_port } },
                ["core/net/sync"] = false,
            })
            commands:spawn({
                ["core/world/status"] = { scope_key = FOURTH, mode = "server", status = "ready",
                    ports = { world = 47732, peer = 47733 } },
                ["core/net/sync"] = false,
            })
            for _, p in ipairs({ { "l1", OTHER }, { "l2", OTHER }, { "l4", FOURTH }, { "l5", THIRD } }) do
                commands:spawn({ ["scope/portal"] = { target = p[2] }, ["core/net/sync"] = false, ["zz/portal/p"] = { name = p[1] } })
            end
            -- Map doors, as a scene's nodes are: named, never placed. The listener answers as OTHER
            -- in this VM, so the place its doors name stands here.
            commands:spawn({ Name = "zz_arrival", Transform = { translation = { x = 0, y = 1, z = -9 } },
                ["core/net/sync"] = false })
            commands:spawn({ ["scope/portal"] = { target = OTHER, at = "zz_arrival" }, Name = "zz_door",
                Transform = { translation = { x = 8, y = 0, z = 3 }, rotation = Quat.from_rotation_y(math.pi / 2) },
                ["core/net/sync"] = false, ["zz/portal/p"] = { name = "door_o" } })
            commands:spawn({ ["scope/portal"] = { target = FOURTH, at = "zz_arrival" }, Name = "zz_door4",
                Transform = { translation = { x = -8, y = 0, z = 3 } },
                ["core/net/sync"] = false, ["zz/portal/p"] = { name = "door_4" } })
            step("linking")
        end

    elseif phase == "linking" then
        local up = links(world, OTHER)[1]
        local st = up and up:get("core/net/peer/link/state")
        if (st and st.welcomed and named(world, "zz/portal/p", "l1"):has("scope/portal/hosted")
                and named(world, "zz/portal/p", "door_o"):has("scope/portal/hosted")) or clock > 8 then
            local others, fourths = links(world, OTHER), links(world, FOURTH)
            local cfg = others[1] and others[1]:get("core/net/peer/link")
            local l1, l2 = named(world, "zz/portal/p", "l1"), named(world, "zz/portal/p", "l2")
            link_holder = others[1] and others[1]:get("ChildOf")
            T("P6_one_identity_link_to_each_running_target",
                #others == 1 and #fourths == 1 and cfg.name == "peer_to_127.0.0.1_47730" and cfg.port == bound_port
                    and cfg.server_addr == "127.0.0.1" and (link_holder == l1:id() or link_holder == l2:id()),
                string.format("links to OTHER=%d FOURTH=%d", #others, #fourths))
            local door_o, door_4 = named(world, "zz/portal/p", "door_o"), named(world, "zz/portal/p", "door_4")
            local doors, doors4 = links(world, OTHER, true), links(world, FOURTH, true)
            local dcfg = doors[1] and doors[1]:get("core/net/peer/link")
            local frame = dcfg and dcfg.frame or {}
            local at = frame.translation or {}
            local yaw = frame.rotation and Quat.to_euler(frame.rotation, "YXZ")[1]
            local d4 = doors4[1] and doors4[1]:get("core/net/peer/link")
            T("P25_a_door_gets_a_link_of_its_own_named_for_it_with_at_and_its_frame",
                #doors == 1 and dcfg.name == "peer_to_" .. OTHER .. "@zz_door" and dcfg.at == "zz_arrival"
                    and dcfg.port == bound_port and doors[1]:get("ChildOf") == door_o:id()
                    and near(at.x, 8) and near(at.y, 0) and near(at.z, 3) and near(yaw, math.pi / 2)
                    and #doors4 == 1 and d4.name == "peer_to_" .. FOURTH .. "@zz_door4"
                    and doors4[1]:get("ChildOf") == door_4:id(),
                string.format("door links to OTHER=%d FOURTH=%d name=%s at=%s frame=%s,%s,%s yaw=%s", #doors, #doors4,
                    tostring(dcfg and dcfg.name), tostring(dcfg and dcfg.at), tostring(at.x), tostring(at.y),
                    tostring(at.z), tostring(yaw)))
            T("P7_a_welcomed_link_marks_its_portals_hosted",
                l1:has("scope/portal/hosted") and l2:has("scope/portal/hosted"), "")
            local dst = doors[1] and doors[1]:get("core/net/peer/link/state")
            T("P7_a_door_s_own_welcomed_link_marks_the_door",
                door_o:has("scope/portal/hosted") and dst ~= nil and dst.welcomed, "")
            local l4 = named(world, "zz/portal/p", "l4")
            local st4 = fourths[1] and fourths[1]:get("core/net/peer/link/state")
            T("P8_a_link_not_welcomed_marks_nothing",
                not l4:has("scope/portal/hosted") and not door_4:has("scope/portal/hosted")
                    and not (st4 and st4.welcomed), "")
            T("P9_a_target_with_no_row_gets_no_link",
                #links(world, THIRD) == 0 and not named(world, "zz/portal/p", "l5"):has("scope/portal/hosted"), "")
            local placing = named(world, "zz/portal/p", "a1")
            T("P13a_a_portal_still_being_placed_has_no_body_and_no_trigger",
                placing:has("placement") and not placing:has("RigidBody3d") and not placing:has("Collider3d")
                    and not placing:has("collision_trigger"),
                string.format("body=%s collider=%s trigger=%s", tostring(placing:get("RigidBody3d")),
                    tostring(placing:has("Collider3d")), tostring(placing:has("collision_trigger"))))
            -- A portal a player dropped, hosted, that came to carry an `at`.
            commands:spawn({
                ["scope/portal"] = { target = OTHER, at = "zz_arrival" },
                Transform = { translation = { x = 12, y = 0, z = -4 } },
                ["core/net/sync"] = {
                    Transform = { authority = "server" },
                    ["scope/portal"] = { authority = "server" },
                },
                ["zz/portal/p"] = { name = "dropped_at" },
            })
            for _, h in ipairs({
                { "h7", 17, true, false }, { "h8", 18, true, false }, { "hm", 19, true, true }, { "hn", 20, false, false },
                { "hp", 25, true, false }, { "hdo", 26, true, false }, { "hd4", 27, true, false },
            }) do
                commands:spawn({
                    player = { client_id = h[2], spawn_index = 0 },
                    ["core/net/owner"] = { client_id = h[2] },
                    ["core/net/peer/share"] = h[3] and { stable_id = "player_" .. h[2] } or nil,
                    ["core/net/peer/mirror"] = h[4] and { stable_id = "player_" .. h[2] } or nil,
                    ["core/net/sync"] = false,
                    ["zz/portal/h"] = { name = h[1] },
                })
            end
            -- Cooling as a handed player arrives: a `cooldown` timer, which `cooldown` turns into the mark.
            commands:spawn({
                player = { client_id = 21, spawn_index = 0 },
                ["core/net/owner"] = { client_id = 21 },
                ["core/net/peer/share"] = { stable_id = "player_21" },
                cooldown = { ["scope/portal/cooling"] = { remaining = 3 } },
                ["core/net/sync"] = false,
                ["zz/portal/h"] = { name = "hc" },
            })
            step("players")
        end

    elseif phase == "players" and clock > 0.3 and named(world, "zz/portal/h", "hc"):has("scope/portal/cooling") then
        local function id(name) return named(world, "zz/portal/h", name):id() end
        local walked = { id("h7"), id("hm"), id("hn"), id("hc") }
        local function walk(portal, who)
            commands:entity(named(world, "zz/portal/p", portal):id()):insert({
                collision_trigger = { entered = { id(who) }, exited = {}, inside = { id(who) } },
            })
        end
        walk("a1", "hp")
        commands:entity(named(world, "zz/portal/p", "l1"):id()):insert({
            collision_trigger = { entered = walked, exited = {}, inside = walked },
        })
        walk("l4", "h8")
        walk("door_o", "hdo")
        walk("door_4", "hd4")
        step("walked")

    elseif phase == "walked" and clock > 0.3 then
        T("P10_walking_into_a_hosted_portal_hands_the_player_over_on_its_identity_link",
            switched.h7 == OTHER and via.h7 == "peer_to_127.0.0.1_47730", tostring(switched.h7) .. " " .. tostring(via.h7))
        T("P10b_taking_a_3_s_crossing_timer_in_transfer_data", carried.h7 == 3, tostring(carried.h7))
        T("P26_walking_into_a_door_hands_the_player_over_on_the_door_s_link",
            switched.hdo == OTHER and via.hdo == "peer_to_" .. OTHER .. "@zz_door" and carried.hdo == 3,
            tostring(switched.hdo) .. " " .. tostring(via.hdo))
        T("P11_with_no_welcomed_link_it_is_handed_over_all_the_same_on_its_join_s_link",
            switched.h8 == FOURTH and via.h8 == "peer_to_127.0.0.1_47732"
                and switched.hd4 == FOURTH and via.hd4 == "peer_to_" .. FOURTH .. "@zz_door4",
            string.format("portal: %s %s door: %s %s", tostring(switched.h8), tostring(via.h8), tostring(switched.hd4),
                tostring(via.hd4)))
        T("P19_a_portal_still_being_placed_hands_nobody_over", switched.hp == nil, tostring(switched.hp))
        local ends, kept = 0, false
        for _, e in ipairs(world:query({ with = { "scope/portal/return", "scope/portal" } })) do
            local back = e:get("scope/portal")
            ends = ends + 1
            kept = kept or back.at ~= nil
        end
        T("P27_a_return_end_does_not_copy_the_portal_s_at",
            ends == 1 and not kept and named(world, "zz/portal/p", "dropped_at"):has("scope/portal/hosted"),
            string.format("return ends=%d with at=%s", ends, tostring(kept)))
        T("P12_a_peer_mirror_or_a_player_without_a_share_is_not_handed_over",
            switched.hm == nil and switched.hn == nil, "")
        T("P17_a_player_still_cooling_is_not_handed_over", switched.hc == nil
            and named(world, "zz/portal/h", "hc"):has("scope/portal/cooling"), tostring(switched.hc))
        local l1 = named(world, "zz/portal/p", "l1")
        local a1 = named(world, "zz/portal/p", "a1")
        local ball = l1:get("Collider3d")
        -- The walk above wrote a trigger on the portal being placed; no body came with it.
        T("P13b_a_placed_portal_has_a_fixed_ball_and_a_trigger_and_one_being_placed_no_body",
            l1:get("RigidBody3d") == "Fixed" and l1:has("Collider3d") and l1:has("collision_trigger")
                and a1:has("placement") and not a1:has("RigidBody3d") and not a1:has("Collider3d"),
            "collider " .. tostring(ball and (ball.ball and ball.ball.radius)))
        commands:entity(a1:id()):remove("placement")
        local holder = world:get_entity(link_holder)
        commands:entity(holder:id()):remove("scope/portal")
        step("taken")

    elseif phase == "taken" and clock > 0.5 then
        local a1 = named(world, "zz/portal/p", "a1")
        T("P14_once_placed_it_gets_them", not a1:has("placement") and a1:get("RigidBody3d") == "Fixed"
            and a1:has("Collider3d") and a1:has("collision_trigger"), "")
        local holder = world:get_entity(link_holder)
        local gone = true
        for _, child in ipairs(holder:get("Children") or {}) do
            local e = world:get_entity(child)
            if e and e:get("core/net/peer/link") then gone = false end
        end
        T("P15_taking_scope_portal_off_takes_body_trigger_mark_and_link",
            gone and not holder:has("RigidBody3d") and not holder:has("Collider3d")
                and not holder:has("collision_trigger") and not holder:has("scope/portal/hosted"), "")
        local others = links(world, OTHER)
        local now = others[1] and others[1]:get("ChildOf")
        local parent = now and world:get_entity(now)
        local names = parent and parent:get("scope/portal")
        T("P16_another_portal_to_that_target_takes_the_link",
            #others == 1 and now ~= link_holder and names ~= nil and names.target == OTHER,
            string.format("links=%d under %s, was %s", #others, tostring(now), tostring(link_holder)))
        link_holder = now
        step("cooled")

    elseif phase == "cooled" and not named(world, "zz/portal/h", "hc"):has("scope/portal/cooling")
        and world:get_entity(link_holder):has("scope/portal/hosted") then
        local hc = named(world, "zz/portal/h", "hc"):id()
        commands:entity(link_holder):insert({ collision_trigger = { entered = { hc }, exited = {}, inside = { hc } } })
        step("walked_again")

    elseif phase == "walked_again" and clock > 0.3 then
        T("P18_once_it_has_cooled_walking_in_hands_it_over", switched.hc == OTHER, tostring(switched.hc))
        -- Real physics from here: a player is a kinematic body moved by its Transform, as on a server.
        commands:spawn({
            ["scope/portal"] = { target = OTHER },
            placement = {},
            Transform = { translation = { x = 30, y = 0, z = 0 } },
            ["core/net/sync"] = false,
            ["zz/portal/p"] = { name = "d1" },
        })
        commands:spawn({
            player = { client_id = 22, spawn_index = 0 },
            ["core/net/owner"] = { client_id = 22 },
            ["core/net/peer/share"] = { stable_id = "player_22" },
            Transform = { translation = { x = 30, y = 0, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            ["core/net/sync"] = false,
            ["zz/portal/h"] = { name = "hd" },
        })
        step("dropping")

    elseif phase == "dropping" and clock > 1 then
        commands:entity(named(world, "zz/portal/p", "d1"):id()):remove("placement")
        step("dropped")

    elseif phase == "dropped" and clock > 1 then
        local d1 = named(world, "zz/portal/p", "d1")
        local hd = named(world, "zz/portal/h", "hd"):id()
        local trigger = d1:get("collision_trigger")
        local read = false
        for _, id in ipairs(trigger and trigger.inside or {}) do
            if id == hd then read = true end
        end
        T("P20_dropped_where_a_player_stands_it_reads_it_inside_and_hands_nobody_over",
            d1:has("scope/portal/hosted") and read and switched.hd == nil,
            string.format("hosted=%s inside=%s switched=%s", tostring(d1:has("scope/portal/hosted")), tostring(read),
                tostring(switched.hd)))
        commands:spawn({
            player = { client_id = 23, spawn_index = 0 },
            ["core/net/owner"] = { client_id = 23 },
            ["core/net/peer/share"] = { stable_id = "player_23" },
            Transform = { translation = { x = 30, y = 0, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            ["core/net/sync"] = false,
            ["zz/portal/h"] = { name = "hs" },
        })
        step("spawned_inside")

    elseif phase == "spawned_inside" and clock > 1 then
        local d1 = named(world, "zz/portal/p", "d1")
        local hs = named(world, "zz/portal/h", "hs"):id()
        local trigger = d1:get("collision_trigger")
        local read = false
        for _, id in ipairs(trigger and trigger.inside or {}) do
            if id == hs then read = true end
        end
        T("P21_a_player_spawned_inside_it_is_not_handed_over", read and switched.hs == nil,
            string.format("inside=%s switched=%s", tostring(read), tostring(switched.hs)))
        commands:entity(named(world, "zz/portal/h", "hd"):id()):insert({ Transform = { translation = { x = 40, y = 0, z = 0 } } })
        step("walked_out")

    elseif phase == "walked_out" and clock > 0.5 then
        commands:entity(named(world, "zz/portal/h", "hd"):id()):insert({ Transform = { translation = { x = 30, y = 0, z = 0 } } })
        step("walked_back")

    elseif phase == "walked_back" and clock > 0.5 then
        T("P22_walking_out_and_back_in_hands_it_over", switched.hd == OTHER, tostring(switched.hd))
        commands:spawn({
            player = { client_id = 24, spawn_index = 0 },
            ["core/net/owner"] = { client_id = 24 },
            ["core/net/peer/share"] = { stable_id = "player_24" },
            Transform = { translation = { x = 50, y = 0, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            ["core/net/sync"] = false,
            ["zz/portal/h"] = { name = "hw" },
        })
        step("standing")

    -- A scene's door: never placed, so its body comes with it.
    elseif phase == "standing" and clock > 1 then
        commands:spawn({
            ["scope/portal"] = { target = OTHER },
            Transform = { translation = { x = 50, y = 0, z = 0 } },
            ["core/net/sync"] = false,
            ["zz/portal/p"] = { name = "door" },
        })
        step("door_spawned")

    elseif phase == "door_spawned" and clock > 1 then
        local door = named(world, "zz/portal/p", "door")
        local hw = named(world, "zz/portal/h", "hw"):id()
        local trigger = door:get("collision_trigger")
        local read = false
        for _, id in ipairs(trigger and trigger.inside or {}) do
            if id == hw then read = true end
        end
        T("P23_a_door_spawned_around_a_player_reads_it_inside_and_hands_nobody_over",
            read and switched.hw == nil, string.format("inside=%s switched=%s", tostring(read), tostring(switched.hw)))
        T("P24_no_portal_reaches_rapier_as_a_solid_ball", solid == 0, "frames with a solid portal: " .. solid)
        phase = "done"
        suite.finish("ScopePortalServerSuite")
    end

    if phase ~= "done" and clock > 12 then
        T("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s")
        phase = "done"
        suite.finish("ScopePortalServerSuite")
    end
end):in_set("zz/portal_server_suite")
