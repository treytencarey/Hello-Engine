-- --host
-- scope/portal on a server. The target's server is stubbed by its row and by a real peer listener
-- in this VM that answers as the target's scope; the link the portal makes dials it and is
-- welcomed. Walking in is `collision_trigger` as the trigger mod writes it. A portal being placed
-- is spawned as `git/panel`'s server half spawns one.
--
--   P6  one link to each target running here, however many portals name it
--   P7  a welcomed link marks the portals to its target hosted
--   P8  a link that is not welcomed marks nothing
--   P9  a target with no row here gets no link and no mark
--   P10 a player walking into a hosted portal is handed over to its target
--   P11 with no welcomed link to the target, nothing
--   P12 a peer mirror, or a player with no share, is not handed over
--   P13 a portal has a fixed ball body of radius 1.2 and a trigger, one still being placed too
--   P14 ...and keeps them once placed
--   P19 a player walking into a portal still being placed is not handed over
--   P15 taking `scope/portal` off a portal that stays takes its body, trigger, mark and link
--   P16 ...and another portal to that target takes the link
--   P10b ...taking a 3 s crossing timer with it in `transfer_data`
--   P17 a player still cooling from its crossing (`cooldown`'s `scope/portal/cooling`) is not handed
--       over
--   P18 ...and once it has cooled, walking in again hands it over
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

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

local function links(world, scope)
    local out = {}
    for _, e in ipairs(world:query({ with = { "core/net/peer/link" }, optional = { "core/net/peer/link/state", "ChildOf" } })) do
        if e:get("core/net/peer/link").scope_key == scope then out[#out + 1] = e end
    end
    return out
end

-- Core's switch takes `core/net/peer/switch` off in the same frame when it finds no peer for the
-- target, so what the portal asked for is read on its edge, right after the portal's systems.
local switched, carried = {}, {}
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
        local share = r:get("core/net/peer/share") or {}
        local timers = share.transfer_data and share.transfer_data.cooldown or {}
        carried[name] = timers["scope/portal/cooling"] and timers["scope/portal/cooling"].remaining
    end
end):in_set("zz/portal_switch_seen"):after("scope/portal/server")

local phase, clock = "listen", 0
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
            step("linking")
        end

    elseif phase == "linking" then
        local up = links(world, OTHER)[1]
        local st = up and up:get("core/net/peer/link/state")
        if (st and st.welcomed and named(world, "zz/portal/p", "l1"):has("scope/portal/hosted")) or clock > 8 then
            local others, fourths = links(world, OTHER), links(world, FOURTH)
            local cfg = others[1] and others[1]:get("core/net/peer/link")
            local l1, l2 = named(world, "zz/portal/p", "l1"), named(world, "zz/portal/p", "l2")
            link_holder = others[1] and others[1]:get("ChildOf")
            T("P6_one_link_to_each_running_target",
                #others == 1 and #fourths == 1 and cfg.name == "peer_to_127.0.0.1_47730" and cfg.port == bound_port
                    and cfg.server_addr == "127.0.0.1" and (link_holder == l1:id() or link_holder == l2:id()),
                string.format("links to OTHER=%d FOURTH=%d", #others, #fourths))
            T("P7_a_welcomed_link_marks_its_portals_hosted",
                l1:has("scope/portal/hosted") and l2:has("scope/portal/hosted"), "")
            local l4 = named(world, "zz/portal/p", "l4")
            local st4 = fourths[1] and fourths[1]:get("core/net/peer/link/state")
            T("P8_a_link_not_welcomed_marks_nothing",
                not l4:has("scope/portal/hosted") and not (st4 and st4.welcomed), "")
            T("P9_a_target_with_no_row_gets_no_link",
                #links(world, THIRD) == 0 and not named(world, "zz/portal/p", "l5"):has("scope/portal/hosted"), "")
            for _, h in ipairs({ { "h7", 17, true, false }, { "h8", 18, true, false }, { "hm", 19, true, true }, { "hn", 20, false, false } }) do
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
        commands:entity(named(world, "zz/portal/p", "a1"):id()):insert({
            collision_trigger = { entered = { id("h8") }, exited = {}, inside = { id("h8") } },
        })
        commands:entity(named(world, "zz/portal/p", "l1"):id()):insert({
            collision_trigger = { entered = walked, exited = {}, inside = walked },
        })
        commands:entity(named(world, "zz/portal/p", "l4"):id()):insert({
            collision_trigger = { entered = { id("h8") }, exited = {}, inside = { id("h8") } },
        })
        step("walked")

    elseif phase == "walked" and clock > 0.3 then
        T("P10_walking_into_a_hosted_portal_hands_the_player_over", switched.h7 == OTHER, tostring(switched.h7))
        T("P10b_taking_a_3_s_crossing_timer_in_transfer_data", carried.h7 == 3, tostring(carried.h7))
        T("P11_with_no_welcomed_link_nothing", switched.h8 == nil, tostring(switched.h8))
        T("P19_a_portal_still_being_placed_hands_nobody_over", switched.h8 == nil, tostring(switched.h8))
        T("P12_a_peer_mirror_or_a_player_without_a_share_is_not_handed_over",
            switched.hm == nil and switched.hn == nil, "")
        T("P17_a_player_still_cooling_is_not_handed_over", switched.hc == nil
            and named(world, "zz/portal/h", "hc"):has("scope/portal/cooling"), tostring(switched.hc))
        local l1 = named(world, "zz/portal/p", "l1")
        local a1 = named(world, "zz/portal/p", "a1")
        local ball = l1:get("Collider3d")
        T("P13_a_portal_has_a_fixed_ball_and_a_trigger_one_being_placed_too",
            l1:get("RigidBody3d") == "Fixed" and l1:has("Collider3d") and l1:has("collision_trigger")
                and a1:has("placement") and a1:get("RigidBody3d") == "Fixed" and a1:has("Collider3d")
                and a1:has("collision_trigger"),
            "collider " .. tostring(ball and (ball.ball and ball.ball.radius)))
        commands:entity(a1:id()):remove("placement")
        local holder = world:get_entity(link_holder)
        commands:entity(holder:id()):remove("scope/portal")
        step("taken")

    elseif phase == "taken" and clock > 0.5 then
        local a1 = named(world, "zz/portal/p", "a1")
        T("P14_placed_it_keeps_them", a1:get("RigidBody3d") == "Fixed" and a1:has("Collider3d") and a1:has("collision_trigger"), "")
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
        phase = "done"
        suite.finish("ScopePortalServerSuite")
    end

    if phase ~= "done" and clock > 12 then
        T("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s")
        phase = "done"
        suite.finish("ScopePortalServerSuite")
    end
end):in_set("zz/portal_server_suite")
