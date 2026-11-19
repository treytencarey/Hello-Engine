-- test_voip_relay.lua: the server half of voip relays voice frames on the world net's `voip/frame`
-- channel. This VM is the server: a real world net, and one real client in an isolated VM that
-- declares the channel on its side, as the client half does, and sends frames through core. The
-- suite stands in for the other clients: their `core/net/connection` under the world net, their
-- players owned by them, and the `core/net/received` core writes for each message they send. What
-- the relay forwards is read from the `core/net/send_to_client` it writes.
--
-- R0  the channel is declared on the world net's Unreliable lane, beside core's own
-- R1  a real client's frame arrives through core and goes to every other participant who is not an
--     observer, with `from` the sender's client id as core stamped it, not the one it wrote
-- R2  a frame from a connection with no participant here goes nowhere
-- R3  an observer's frame goes nowhere
-- R4  a silenced participant's frame goes nowhere
-- R5  a malformed frame goes nowhere: no data, data not text, data not base64, no codec, another
--     message type
-- R6  2,048 bytes go, 2,049 do not
-- R7  a sender's 6 frames in one run: 4 go
-- R8  a frame on another net's name or another channel goes nowhere
-- R9  an observer is sent nothing, whoever speaks
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local bevy = require("bevy::prelude")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("VoipRelaySuite")
local T = suite.assert_test

local PORT = 15863
local FORGED = 777777
local REAL = "UjFyZWFsZnJhbWU="

local DEFAULTS = { go = false, stop = false, sent = 0 }
local ts = helpers.shared_state("VoipRelayState", DEFAULTS)

-- The real client: an isolated VM joining this VM's world net.
helpers.make_fixture("modules/test_fixtures/gen_voip_relay_client.lua", [=[
require("modules/core/net/client/init.lua")
local bevy = require("bevy::prelude")
local Time = require("bevy::time::Time")
local boot = require("modules/core/instances.lua").boot_data()
local ts = require("modules/core/test_helpers.lua").shared_state("VoipRelayState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "client", name = "zzvr_c", ip = "127.0.0.1", port = boot.PORT },
        ["core/net"] = { mode = "client", name = "zzvr_c", ip = "127.0.0.1", port = boot.PORT },
        ["core/net/channels"] = { Unreliable = { ["voip/frame"] = {} } },
        ["core/net/sync"] = false,
    })
end)

local since = 0
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "core/net/connected" } }],
    bevy.MessageWriter["core/net/send"],
}, function(time, connected, send)
    since = since + time:delta_secs()
    if ts.go and not ts.stop and not connected:is_empty() and since > 0.25 then
        since = 0
        send:write({ msg_type = "voip/frame", channel = "voip/frame", codec = 2, data = boot.REAL, from = boot.FORGED })
        ts.sent = ts.sent + 1
    end
end)
]=])
helpers.spawn_vm("modules/test_fixtures/gen_voip_relay_client.lua",
    { DEFAULTS = DEFAULTS, PORT = PORT, REAL = REAL, FORGED = FORGED }, { headless = true })

local net
local c = {}

app:add_systems(Startup, { Commands }, function(commands)
    net = commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzvr", port = PORT },
        ["core/net/sync"] = false,
    }):id()
    -- 2 and 6 listen; 3 only watches; 4 is silenced; 5 has no player here.
    for id = 2, 6 do
        c[id] = commands:spawn({
            ["core/net/connection"] = { client_id = id, observer = id == 3 },
            ["core/net/sync"] = false,
            ChildOf = net,
        }):id()
        if id ~= 5 then
            commands:spawn({ player = { client_id = id }, ["core/net/owner"] = c[id], ["core/net/sync"] = false })
        end
    end
    commands:entity(c[4]):insert({ ["voip/silenced"] = {} })
    commands:spawn({ voip = {}, ["core/net/sync"] = false })
end)

-- What the other clients send, as core writes it on arrival: the message, its channel, the net's
-- name and the sender's client id.
local outbox = {}
app:add_systems(First, { bevy.MessageWriter["core/net/received"] }, function(received)
    for _, m in ipairs(outbox) do
        received:write(m)
    end
    outbox = {}
end):in_set("zz/voip_relay_senders")

local function frame(client_id, data, fields)
    local m = { msg_type = "voip/frame", channel = "voip/frame", net = "zzvr", client_id = client_id, codec = 2, data = data }
    for k, v in pairs(fields or {}) do m[k] = v end
    outbox[#outbox + 1] = m
end

-- data -> the forwards it got: { client_id, from }
local sent = {}
local observer_got = 0
app:add_systems(Last, { bevy.MessageReader["core/net/send_to_client"] }, function(sends)
    for _, s in ipairs(sends:read()) do
        local msg = s.msg or {}
        if msg.msg_type == "voip/frame" then
            local key = tostring(msg.data)
            sent[key] = sent[key] or {}
            sent[key][#sent[key] + 1] = { client_id = s.client_id, from = msg.from, net = s.net, channel = msg.channel }
            if s.client_id == 3 then observer_got = observer_got + 1 end
        end
    end
end):in_set("zz/voip_relay_forwards")

local function to(data)
    local out = {}
    for _, f in ipairs(sent[data] or {}) do out[#out + 1] = tostring(f.client_id) end
    table.sort(out)
    return table.concat(out, ",")
end

local function real_connection(world)
    for _, e in ipairs(world:query({ with = { "core/net/connection", "ChildOf" } })) do
        local id = e:get("core/net/connection").client_id
        if e:get("ChildOf") == net and (id < 2 or id > 6) then return e end
    end
    return nil
end

local phase, clock = "start", 0
local seen = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        ts.stop = true
        phase = "done"
        suite.finish("VOIP_RELAY")
    end

    if phase == "start" then
        local conn = real_connection(world)
        if conn == nil and clock < 15 then return end
        local channels = (world:get_entity(net):get("core/net/channels") or {}).Unreliable or {}
        T("R0_the_channel_is_declared_on_the_world_nets_unreliable_lane",
            channels["voip/frame"] ~= nil and channels.sync_unreliable ~= nil,
            string.format("voip/frame=%s sync_unreliable=%s", tostring(channels["voip/frame"] ~= nil),
                tostring(channels.sync_unreliable ~= nil)))
        if conn == nil then
            T("R1_a_real_clients_frame_is_forwarded_with_core_stamped_from", false, "the client never connected")
            finish()
            return
        end
        seen.real = conn:get("core/net/connection").client_id
        commands:spawn({ player = { client_id = seen.real }, ["core/net/owner"] = conn:id(), ["core/net/sync"] = false })
        step("real")

    elseif phase == "real" then
        if clock > 0.5 then ts.go = true end
        if #(sent[REAL] or {}) < 3 and clock < 10 then return end
        ts.stop = true
        local from_ok, net_ok = #(sent[REAL] or {}) > 0, true
        for _, f in ipairs(sent[REAL] or {}) do
            if f.from ~= seen.real then from_ok = false end
            if f.net ~= "zzvr" or f.channel ~= "voip/frame" then net_ok = false end
        end
        local first = {}
        for i = 1, 3 do first[i] = (sent[REAL] or {})[i] end
        local who = {}
        for _, f in ipairs(first) do who[#who + 1] = tostring(f.client_id) end
        table.sort(who)
        T("R1_a_real_clients_frame_is_forwarded_with_core_stamped_from",
            from_ok and net_ok and table.concat(who, ",") == "2,4,6",
            string.format("sent=%d forwards=%d first to=[%s] from=%s real=%s forged=%d net/channel ok=%s",
                ts.sent, #(sent[REAL] or {}), table.concat(who, ","), tostring(((sent[REAL] or {})[1] or {}).from),
                tostring(seen.real), FORGED, tostring(net_ok)))
        frame(5, "UjJub3BhcnQ=")
        frame(3, "UjNvYnNlcnZlcg==")
        frame(4, "UjRzaWxlbmNlZA==")
        frame(2, nil)
        frame(2, 42)
        frame(2, "UjVub3Q$YmFzZTY0")
        frame(2, "UjVub2NvZGVj", { codec = false })
        frame(2, "UjV0eXBl", { msg_type = "zz/other" })
        frame(2, string.rep("A", 2048))
        frame(2, string.rep("B", 2049))
        for i = 1, 6 do frame(6, "UjdjYXA=") end
        frame(2, "UjhuZXQ=", { net = "zzother" })
        frame(2, "UjhjaGFubmVs", { channel = "zz_chat" })
        step("forged")

    elseif phase == "forged" then
        if clock < 0.5 then return end
        T("R2_a_frame_from_no_participant_goes_nowhere", to("UjJub3BhcnQ=") == "", to("UjJub3BhcnQ="))
        T("R3_an_observers_frame_goes_nowhere", to("UjNvYnNlcnZlcg==") == "", to("UjNvYnNlcnZlcg=="))
        T("R4_a_silenced_participants_frame_goes_nowhere", to("UjRzaWxlbmNlZA==") == "", to("UjRzaWxlbmNlZA=="))
        T("R5_a_malformed_frame_goes_nowhere",
            to("nil") == "" and to("42") == "" and to("UjVub3Q$YmFzZTY0") == "" and to("UjVub2NvZGVj") == ""
                and to("UjV0eXBl") == "",
            string.format("no data=[%s] number=[%s] not base64=[%s] no codec=[%s] other type=[%s]", to("nil"), to("42"),
                to("UjVub3Q$YmFzZTY0"), to("UjVub2NvZGVj"), to("UjV0eXBl")))
        local at_limit, over = to(string.rep("A", 2048)), to(string.rep("B", 2049))
        local others = { tostring(seen.real), "4", "6" }
        table.sort(others)
        T("R6_2048_bytes_go_and_2049_do_not", at_limit == table.concat(others, ",") and over == "",
            string.format("2048 to=[%s] 2049 to=[%s]", at_limit, over))
        local capped = sent["UjdjYXA="] or {}
        local per = {}
        for _, f in ipairs(capped) do per[f.client_id] = (per[f.client_id] or 0) + 1 end
        T("R7_six_frames_in_a_run_four_go", per[2] == 4 and per[4] == 4 and per[seen.real] == 4 and per[6] == nil,
            string.format("to 2=%s to 4=%s to real=%s to the sender=%s", tostring(per[2]), tostring(per[4]),
                tostring(per[seen.real]), tostring(per[6])))
        T("R8_another_nets_name_or_another_channel_goes_nowhere", to("UjhuZXQ=") == "" and to("UjhjaGFubmVs") == "",
            string.format("other net=[%s] other channel=[%s]", to("UjhuZXQ="), to("UjhjaGFubmVs")))
        T("R9_an_observer_is_sent_nothing", observer_got == 0, "observer was sent " .. observer_got)
        finish()
    end

    if phase ~= "done" and clock > 20 then
        T("R_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        finish()
    end
end):in_set("zz/voip_relay_suite")
