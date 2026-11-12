-- --host
-- scope/portal on a client: walking in predicts the crossing with one ask to root, and the
-- server's switch on this client's player is followed with a plain one. Root is stubbed by this
-- world's own row, so core's flip driver leaves the asks alone; walking in is `collision_trigger`
-- as the trigger mod writes it, and the switch is `core/net/peer/switch` as the server syncs it to
-- the player's owner.
--
--   C1  the local player walking into a portal asks one predicted flip, shared with root, carrying
--       `player/spawner/standin`, its place where it stands and its look: its whole camera, the yaw
--       relative to its body; and no plain flip
--   C2  walking into a hosted one asks the same: hosted or not, only the server decides
--   C3  a portal to this world's own scope asks none
--   C4  a remote player walking in asks none
--   C11 walking through a door (`at`, on a named node, turned) the place is relative to the door,
--       and the ask names `at`
--   C5  a switch on this client's player asks one plain flip to its target, with no prediction
--   C12 a switch on another entity asks none, nor one on a player that is not this client's
--   C13 the switch written again (the next crossing; the copy here keeps the last) asks again
--   C15 the switch and the player's demotion (`core/net/local` taken off) landing in the same frame,
--       as the net client applies them in `First`, ask one plain flip
--   C14 a reload of this half, with the last switch still on a player handed over (no longer this
--       client's), asks nothing
--   C6  in a world that only observes, walking in asks none
--   C7  a local player still cooling from its crossing (the `cooldown` its server synced) asks none
--   C8  ...and once it has cooled, walking in asks one
--   C9  with real physics: a portal being placed where the player stands has no body and no
--       trigger, and asks nothing
--   C9b ...once dropped it has them, and its trigger reads the player inside, who did not walk in:
--       no ask
--   C10 ...and walking out and back in asks one
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("ScopePortalClientSuite")
local T = suite.assert_test

local HERE = "github:zzportalc/here:main"
local OTHER = "github:zzportalc/other:main"
local SECOND = "github:zzportalc/second:main"
local THIRD = "github:zzportalc/third:main"
local FIFTH = "github:zzportalc/fifth:main"
local SIXTH = "github:zzportalc/sixth:main"
local DOOR = "github:zzportalc/door:main"
local SWITCHED = "github:zzportalc/switched:main"
local NOWHERE = "github:zzportalc/nowhere:main"
local REMOTE = "github:zzportalc/remote:main"
local STALE = "github:zzportalc/stale:main"
local LATE = "github:zzportalc/late:main"
local CLIENT_SOURCE = "assets/modules/scope/portal/client/init.lua"

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

local function bodied(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/pc/p" },
        optional = { "RigidBody3d", "Collider3d", "collision_trigger" },
    })) do
        if e:get("zz/pc/p").name == name then
            return e:has("RigidBody3d") or e:has("Collider3d") or e:has("collision_trigger")
        end
    end
    return false
end

-- The asks for a scope: how many are predicted, how many plain, whether each is shaped as an ask
-- to root, and the last predicted one.
local function asks(world, scope)
    local predicted, plain, shaped, last = 0, 0, true, nil
    for _, e in ipairs(world:query({
        with = { "core/world/flip" },
        optional = { "WorldShared", "core/net/sync", "player/spawner/standin" },
    })) do
        local flip = e:get("core/world/flip")
        if flip.scope == scope then
            shaped = shaped and e:has("WorldShared") and e:get("core/net/sync") == false
            if flip.predicted ~= nil then
                predicted = predicted + 1
                shaped = shaped and e:has("player/spawner/standin")
                last = flip.predicted
            else
                plain = plain + 1
            end
        end
    end
    return predicted, plain, shaped, last
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-3 end

local function walk(commands, world, portal, who)
    local ids = {}
    for _, name in ipairs(who) do ids[#ids + 1] = named(world, "zz/pc/h", name):id() end
    commands:entity(named(world, "zz/pc/p", portal):id()):insert({
        collision_trigger = { entered = ids, exited = {}, inside = ids },
    })
end

local phase, clock = "spawn", 0

-- The net client applies the server's switch and, when the next packet came in the same frame, the
-- player's demotion, both in `First`, after the half's follow (which runs before the net client).
local demote_late = false
app:add_systems(First, { World, Commands }, function(world, commands)
    if demote_late then
        demote_late = false
        local late = named(world, "zz/pc/h", "late"):id()
        commands:entity(late):insert({ ["core/net/peer/switch"] = { target_scope = LATE } })
        commands:entity(late):remove("core/net/local")
    end
end):in_set("zz/portal_client_net"):after("scope/portal/client")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        -- Turned 0.5 about Y, looking 0.8 to its left and 0.1 down, from 6 m back and 2 m up.
        commands:spawn({ player = { client_id = 7 }, ["core/net/local"] = true, ["core/net/sync"] = false,
            Transform = { translation = { x = 3, y = 1, z = 4 }, rotation = Quat.from_rotation_y(0.5) },
            camera = { yaw = 1.3, pitch = -0.1, distance = 6, height = 2 },
            ["zz/pc/h"] = { name = "me" } })
        -- This client's player once, handed over since, as the switch will find it.
        commands:spawn({ player = { client_id = 7 }, ["core/net/local"] = true, ["core/net/sync"] = false,
            ["zz/pc/h"] = { name = "gone" } })
        commands:spawn({ player = { client_id = 7 }, ["core/net/local"] = true, ["core/net/sync"] = false,
            ["zz/pc/h"] = { name = "late" } })
        commands:spawn({ player = { client_id = 8 }, ["core/net/sync"] = false,
            Transform = { translation = { x = -3, y = 1, z = 4 } }, ["zz/pc/h"] = { name = "them" } })
        commands:spawn({ ["zz/pc/h"] = { name = "thing" }, ["core/net/sync"] = false })
        commands:spawn({ ["scope/portal"] = { target = OTHER }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c1" } })
        commands:spawn({ ["scope/portal"] = { target = SECOND }, ["scope/portal/hosted"] = {}, ["core/net/sync"] = false,
            ["zz/pc/p"] = { name = "c2" } })
        commands:spawn({ ["scope/portal"] = { target = HERE }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c3" } })
        commands:spawn({ ["scope/portal"] = { target = THIRD }, ["core/net/sync"] = false, ["zz/pc/p"] = { name = "c4" } })
        -- A map's door at (1, 0, 2), turned a quarter about Y.
        commands:spawn({ ["scope/portal"] = { target = DOOR, at = "zz_arrival" }, Name = "zz_door",
            Transform = { translation = { x = 1, y = 0, z = 2 }, rotation = Quat.from_rotation_y(math.pi / 2) },
            ["core/net/sync"] = false, ["zz/pc/p"] = { name = "door" } })
        step("spawned")

    -- The trigger mod writes its first `collision_trigger` once its sensor parts land, which would
    -- overwrite a walk written before it: walk once every portal has them, and they have settled.
    elseif phase == "spawned" and #world:query({ with = { "zz/pc/p", "CollidingEntities3d" } }) == 5 then
        step("settling")

    elseif phase == "settling" and clock > 0.5 then
        walk(commands, world, "c1", { "me" })
        walk(commands, world, "c2", { "me" })
        walk(commands, world, "c3", { "me" })
        walk(commands, world, "c4", { "them" })
        walk(commands, world, "door", { "me" })
        step("walked")

    elseif phase == "walked" and clock > 0.3 then
        local predicted, plain, shaped, ask = asks(world, OTHER)
        local place = ask and ask.place or {}
        local at = place.translation or {}
        local look = ask and ask.look or {}
        T("C1_walking_in_asks_one_predicted_flip_with_its_place_and_its_whole_camera_and_no_plain_one",
            predicted == 1 and plain == 0 and shaped and ask.at == nil
                and near(at.x, 3) and near(at.y, 1) and near(at.z, 4) and near(look.yaw, 0.8) and near(look.pitch, -0.1)
                and look.distance == 6 and look.height == 2,
            string.format("predicted=%d plain=%d shaped=%s at=%s,%s,%s yaw=%s distance=%s height=%s", predicted, plain,
                tostring(shaped), tostring(at.x), tostring(at.y), tostring(at.z), tostring(look.yaw),
                tostring(look.distance), tostring(look.height)))
        local p2, n2 = asks(world, SECOND)
        T("C2_walking_into_a_hosted_one_asks_the_same", p2 == 1 and n2 == 0, string.format("predicted=%d plain=%d", p2, n2))
        local p3, n3 = asks(world, HERE)
        T("C3_a_portal_to_this_world_asks_none", p3 + n3 == 0, "")
        local p4, n4 = asks(world, THIRD)
        T("C4_a_remote_player_walking_in_asks_none", p4 + n4 == 0, "")
        -- The player at (3, 1, 4) is (2, 1, 2) from the door, which is (-2, 1, 2) in the door's
        -- quarter-turned frame, and its body is turned 0.5 - pi/2 there.
        local dp, dn, _, door = asks(world, DOOR)
        local dplace = door and door.place or {}
        local dat = dplace.translation or {}
        local dyaw = dplace.rotation and Quat.to_euler(dplace.rotation, "YXZ")[1]
        T("C11_through_a_door_the_place_is_relative_to_it_and_the_ask_names_at",
            dp == 1 and dn == 0 and door.at == "zz_arrival" and near(dat.x, -2) and near(dat.y, 1) and near(dat.z, 2)
                and near(dyaw, 0.5 - math.pi / 2) and near(door.look.yaw, 0.8),
            string.format("predicted=%d at=%s place=%s,%s,%s yaw=%s", dp, tostring(door and door.at), tostring(dat.x),
                tostring(dat.y), tostring(dat.z), tostring(dyaw)))
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({
            ["core/net/peer/switch"] = { target_scope = SWITCHED, link = "peer_to_" .. SWITCHED },
        })
        commands:entity(named(world, "zz/pc/h", "thing"):id()):insert({
            ["core/net/peer/switch"] = { target_scope = NOWHERE },
        })
        commands:entity(named(world, "zz/pc/h", "them"):id()):insert({
            ["core/net/peer/switch"] = { target_scope = REMOTE },
        })
        commands:entity(named(world, "zz/pc/h", "gone"):id()):insert({
            ["core/net/peer/switch"] = { target_scope = STALE },
        })
        step("switched")

    elseif phase == "switched" and clock > 0.3 then
        local predicted, plain, shaped = asks(world, SWITCHED)
        T("C5_a_switch_on_this_client_s_player_asks_one_plain_flip", plain == 1 and predicted == 0 and shaped,
            string.format("plain=%d predicted=%d", plain, predicted))
        local p12, n12 = asks(world, NOWHERE)
        local pr, nr = asks(world, REMOTE)
        T("C12_a_switch_on_another_entity_or_a_player_not_this_client_s_asks_none", p12 + n12 + pr + nr == 0,
            string.format("other entity=%d not this client's=%d", p12 + n12, pr + nr))
        -- The player handed over: the net client takes `core/net/local` off it, and the switch it
        -- followed stays on its copy here.
        commands:entity(named(world, "zz/pc/h", "gone"):id()):remove("core/net/local")
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({
            ["core/net/peer/switch"] = { target_scope = SWITCHED, link = "peer_to_" .. SWITCHED },
        })
        demote_late = true
        step("switched_again")

    elseif phase == "switched_again" and clock > 0.3 then
        local _, plain = asks(world, SWITCHED)
        T("C13_the_switch_written_again_asks_again", plain == 2, "plain=" .. plain)
        local pl, nl = asks(world, LATE)
        T("C15_the_switch_and_the_demotion_in_one_frame_ask_one_plain_flip", nl == 1 and pl == 0,
            string.format("plain=%d predicted=%d", nl, pl))
        local _, stale = asks(world, STALE)
        T("C14_before_it_was_handed_over_its_switch_was_followed_once", stale == 1, "plain=" .. stale)
        -- Back in place, core takes the old switch off this client's player.
        commands:entity(named(world, "zz/pc/h", "me"):id()):remove("core/net/peer/switch")
        write_file_bytes(CLIENT_SOURCE, read_file_bytes(CLIENT_SOURCE))
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local _, stale = asks(world, STALE)
        local _, again = asks(world, SWITCHED)
        T("C14_a_reload_with_the_last_switch_on_a_player_handed_over_asks_nothing", stale == 1 and again == 2,
            string.format("stale=%d switched=%d", stale, again))
        commands:entity(world:query({ with = { "zz/pc/row" } })[1]:id()):insert({
            ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = true },
        })
        step("watching")

    elseif phase == "watching" and clock > 0.3 then
        walk(commands, world, "c4", { "me" })
        step("watched")

    elseif phase == "watched" and clock > 0.3 then
        local p6, n6 = asks(world, THIRD)
        T("C6_in_a_world_that_only_observes_walking_in_asks_none", p6 + n6 == 0, "")
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
        and #world:query({ with = { "zz/pc/p", "CollidingEntities3d" } }) == 6 and clock > 0.5 then
        walk(commands, world, "c5", { "me" })
        step("cooled_walk")

    elseif phase == "cooled_walk" and clock > 0.3 then
        local p7, n7 = asks(world, FIFTH)
        T("C7_a_player_still_cooling_asks_none", p7 + n7 == 0
            and #world:query({ with = { "zz/pc/h", "scope/portal/cooling" } }) == 1, "")
        step("cooled")

    elseif phase == "cooled" and #world:query({ with = { "zz/pc/h", "scope/portal/cooling" } }) == 0 then
        walk(commands, world, "c5", { "me" })
        step("walked_cooled")

    elseif phase == "walked_cooled" and clock > 0.3 then
        local p8, n8 = asks(world, FIFTH)
        T("C8_once_it_has_cooled_walking_in_asks_one", p8 == 1 and n8 == 0, string.format("predicted=%d plain=%d", p8, n8))
        -- Real physics from here: the player is a body, and the trigger mod reads Rapier's overlaps.
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({
            Transform = { translation = { x = 50, y = 0, z = 0 } },
            RigidBody3d = "Dynamic",
            Collider3d = { ball = { radius = 0.3 } },
            GravityScale3d = { value = 0 },
        })
        commands:spawn({
            ["scope/portal"] = { target = SIXTH },
            placement = {},
            Transform = { translation = { x = 50, y = 0, z = 0 } },
            ["core/net/sync"] = false,
            ["zz/pc/p"] = { name = "c6" },
        })
        step("placing")

    elseif phase == "placing" and clock > 1 then
        local p9, n9 = asks(world, SIXTH)
        T("C9_a_portal_being_placed_has_no_body_or_trigger_and_asks_nothing_of_the_player_inside",
            not bodied(world, "c6") and p9 + n9 == 0,
            string.format("body=%s asks=%d", tostring(bodied(world, "c6")), p9 + n9))
        commands:entity(named(world, "zz/pc/p", "c6"):id()):remove("placement")
        step("placed_here")

    elseif phase == "placed_here" and clock > 1 then
        local me = named(world, "zz/pc/h", "me"):id()
        local read = false
        for _, e in ipairs(world:query({ with = { "zz/pc/p", "collision_trigger" } })) do
            if e:get("zz/pc/p").name == "c6" then
                for _, id in ipairs(e:get("collision_trigger").inside or {}) do
                    if id == me then read = true end
                end
            end
        end
        local p9, n9 = asks(world, SIXTH)
        T("C9b_dropped_on_the_player_it_reads_it_inside_and_asks_nothing",
            bodied(world, "c6") and read and p9 + n9 == 0,
            string.format("body=%s inside=%s asks=%d", tostring(bodied(world, "c6")), tostring(read), p9 + n9))
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({ Transform = { translation = { x = 60, y = 0, z = 0 } } })
        step("out")

    elseif phase == "out" and clock > 1 then
        commands:entity(named(world, "zz/pc/h", "me"):id()):insert({ Transform = { translation = { x = 50, y = 0, z = 0 } } })
        step("back_in")

    elseif phase == "back_in" and clock > 1 then
        local p10, n10 = asks(world, SIXTH)
        T("C10_walking_out_and_back_in_asks_one", p10 == 1 and n10 == 0, string.format("predicted=%d plain=%d", p10, n10))
        phase = "done"
        suite.finish("ScopePortalClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ScopePortalClientSuite")
    end
end):in_set("zz/portal_client_suite")
