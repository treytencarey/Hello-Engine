-- test_voip_participants.lua: the server half of voip makes each of this world's players a
-- participant, from the connection that owns it. The suite stands in for core/net (a real world
-- net, and each client's `core/net/connection` under it, as core spawns them), for
-- core/player/attest (the verdict on each connection) and for the player spawner (players owned
-- by their connection).
--
-- P1  a player gets `voip/participant` with its connection's client id, not speaking, not
--     silenced, and the sync entries: the participant to everyone, `voip/silence` from its owner
-- P2  `login` is the attested connection's GitHub link; an anonymous connection and an attested
--     one with no link have none
-- P3  a player another world shares here, and a player with no owner, are no participants
-- P4  a new attestation changes `login`: linked now, gone when the ticket is anonymous
-- P5  `silenced` follows the connection's `voip/silenced`, both ways
-- P6  a player handed to another world (a mirror now, no owner) is no participant any more
-- P7  the carrier leaving takes every participant, the sync entries and the channel
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("VoipParticipantsSuite")
local T = suite.assert_test

local net, carrier
local c = {}
local p = {}

app:add_systems(Startup, { Commands }, function(commands)
    net = commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzvp", port = 15861 },
        ["core/net/sync"] = false,
    }):id()
    local verdicts = {
        { state = "attested", user = "u1", name = "Alice", links = { github = "alice-gh" }, nonce = "n1" },
        { state = "anonymous" },
        { state = "attested", user = "u3", name = "Carol", nonce = "n3" },
    }
    for id = 1, 3 do
        c[id] = commands:spawn({
            ["core/net/connection"] = { client_id = id, observer = false },
            ["core/player/attest"] = verdicts[id],
            ["core/net/sync"] = false,
            ChildOf = net,
        }):id()
        p[id] = commands:spawn({
            player = { client_id = id },
            ["core/net/owner"] = c[id],
            ["core/net/sync"] = {},
        }):id()
    end
    p.mirror = commands:spawn({
        player = { client_id = 9 },
        ["core/net/peer/mirror"] = { stable_id = "player_9", source_peer = "zz", via = "out:zz" },
        ["core/net/sync"] = {},
    }):id()
    p.unowned = commands:spawn({ player = { client_id = 8 }, ["core/net/sync"] = {} }):id()
    carrier = commands:spawn({ voip = {}, ["core/net/sync"] = false }):id()
end)

local function participant(world, id)
    local e = world:get_entity(id)
    return e and e:get("voip/participant")
end

local function sync(world, id)
    local e = world:get_entity(id)
    return e and e:get("core/net/sync") or {}
end

local phase, clock = "start", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        suite.finish("VOIP_PARTICIPANTS")
    end

    if phase == "start" then
        local ready = participant(world, p[1]) and participant(world, p[2]) and participant(world, p[3])
        if not ready and clock < 5 then return end
        if clock < 0.5 then return end
        p.declared = ((world:get_entity(net):get("core/net/channels") or {}).Unreliable or {})["voip/frame"] ~= nil
        local a = participant(world, p[1]) or {}
        local s = sync(world, p[1])
        local part, silence = s["voip/participant"] or {}, s["voip/silence"] or {}
        T("P1_a_player_is_a_participant_with_its_connections_client_id_and_the_sync_entries",
            a.client_id == 1 and a.speaking == false and a.silenced == false
                and part.authority == "server" and part.target == nil
                and silence.authority == "client" and silence.target == "owner",
            string.format("client_id=%s speaking=%s silenced=%s participant=%s/%s silence=%s/%s",
                tostring(a.client_id), tostring(a.speaking), tostring(a.silenced), tostring(part.authority),
                tostring(part.target), tostring(silence.authority), tostring(silence.target)))
        local b, d = participant(world, p[2]) or {}, participant(world, p[3]) or {}
        T("P2_login_is_the_attested_github_link_and_none_otherwise",
            a.login == "alice-gh" and participant(world, p[2]) ~= nil and b.login == nil
                and participant(world, p[3]) ~= nil and d.login == nil,
            string.format("alice=%s anonymous=%s unlinked=%s", tostring(a.login), tostring(b.login), tostring(d.login)))
        T("P3_a_shared_player_and_an_unowned_player_are_no_participants",
            participant(world, p.mirror) == nil and participant(world, p.unowned) == nil
                and sync(world, p.mirror)["voip/participant"] == nil,
            string.format("mirror=%s unowned=%s", tostring(participant(world, p.mirror) ~= nil),
                tostring(participant(world, p.unowned) ~= nil)))
        commands:entity(c[2]):insert({ ["core/player/attest"] = {
            state = "attested", user = "u2", name = "Bob", links = { github = "bob-gh" }, nonce = "n2" } })
        commands:entity(c[1]):insert({ ["core/player/attest"] = { state = "anonymous" } })
        step("attest")

    elseif phase == "attest" then
        local a, b = participant(world, p[1]) or {}, participant(world, p[2]) or {}
        if not (a.login == nil and b.login == "bob-gh") and clock < 3 then return end
        T("P4_a_new_attestation_changes_login", a.login == nil and b.login == "bob-gh",
            string.format("alice now anonymous=%s bob now linked=%s", tostring(a.login), tostring(b.login)))
        commands:entity(c[3]):insert({ ["voip/silenced"] = {} })
        step("silenced")

    elseif phase == "silenced" then
        if not (participant(world, p[3]) or {}).silenced and clock < 3 then return end
        p.was_silenced = (participant(world, p[3]) or {}).silenced == true
        commands:entity(c[3]):remove("voip/silenced")
        step("unsilenced")

    elseif phase == "unsilenced" then
        local d = participant(world, p[3]) or {}
        if d.silenced ~= false and clock < 3 then return end
        T("P5_silenced_follows_the_connection_both_ways", p.was_silenced and d.silenced == false,
            string.format("on=%s off=%s", tostring(p.was_silenced), tostring(d.silenced)))
        commands:entity(p[1]):insert({
            ["core/net/peer/mirror"] = { stable_id = "player_1", source_peer = "zz", via = "out:zz", was_source = true },
        })
        commands:entity(p[1]):remove("core/net/owner")
        step("handed")

    elseif phase == "handed" then
        if participant(world, p[1]) ~= nil and clock < 3 then return end
        T("P6_a_player_handed_away_is_no_participant", participant(world, p[1]) == nil
            and participant(world, p[2]) ~= nil, string.format("handed=%s other=%s",
                tostring(participant(world, p[1]) ~= nil), tostring(participant(world, p[2]) ~= nil)))
        commands:entity(carrier):remove("voip")
        step("gone")

    elseif phase == "gone" then
        local channels = (world:get_entity(net):get("core/net/channels") or {}).Unreliable or {}
        local left = participant(world, p[2]) ~= nil or participant(world, p[3]) ~= nil
        local entries = sync(world, p[2])["voip/participant"] ~= nil or sync(world, p[3])["voip/silence"] ~= nil
        if (left or entries or channels["voip/frame"] ~= nil) and clock < 3 then return end
        T("P7_the_carrier_leaving_takes_participants_sync_entries_and_the_channel",
            p.declared and not left and not entries and channels["voip/frame"] == nil,
            string.format("declared before=%s participants=%s entries=%s channel=%s", tostring(p.declared),
                tostring(left), tostring(entries), tostring(channels["voip/frame"] ~= nil)))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/voip_participants_suite")
