-- test_voip_client.lua: the client half of voip, on this client's world net, unconnected. The
-- suite stands in for the server (the carrier, and each player's synced `voip/participant`, the
-- local player's owned by this client's net), for root (its `vault/microphone/reply`, and Opus
-- packets made with root's encoder and base64, as root makes them) and for core/net (the
-- `core/net/received` it writes for each frame that arrives). V is pressed through
-- `input/synthetic_key`.
--
-- C1  the local player gets its microphone settings, its intent and V in game input only; the
--     ask of root is a child of the carrier, open, sending nothing, at complexity 5; a remote
--     participant gets its local mute; the channel is declared
-- C2  the ask's complexity follows the carrier's
-- C3  V held sends every block and released sends none; in UI input V does nothing
-- C4  open-mic mode sends what the voice gate passes
-- C5  muted, the ask is closed; silenced, too; and open again after each
-- C6  root's packets above `taken` go, once each, from windows of two: none lost, none twice
-- C7  a participant's frames are decoded; this player's own, a locally muted participant's and
--     another net's never are, and never reach the speaker
-- C12 a source waits for 3 blocks: 2 write nothing, the third starts it, and it fills the
--     speaker to 60 ms (2,880 samples) and no further
-- C13 a speaker holding more than 60 ms is written nothing, though a source is primed
-- C8  a participant gone: its decoder goes, and what it had buffered never plays
-- C9  with no microphone (`no_device`), nothing is sent and frames are still heard
-- C14 two loud sources mix into one clamped write: 960 samples, not 1,920
-- C15 a participant muted for this player: what it had buffered never plays
-- C10 the speaking sphere comes and goes with `speaking`
-- C11 this player no longer a participant: its settings, intent and key go, and the speaker
--
-- The speaker: the suite opens `voip/speaker` itself, on a device that does not exist, before
-- the client half would. With no device nothing plays it, so what the mixer writes stays in its
-- queue: `queued()` counts every sample written, and the suite empties it (`clear()`), as a
-- device would, between cases. That holds with no output device, as in CI.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local bevy = require("bevy::prelude")
local OpusDecoders = require("hello::audio::OpusDecoders")
local Speakers = require("hello::audio::Speakers")
local OpusEncoders = require("hello::audio::OpusEncoders")
local Net = require("modules/core/net/shared/net.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("VoipClientSuite")
local T = suite.assert_test

-- Root's encoder, as vault/microphone/base64.lua has it.
local ROOT_ENCODER = [=[
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 0, 63 do DIGIT[i] = ALPHABET:sub(i + 1, i + 1) end
local M = {}
function M.encode(bytes)
    local byte, out, j, n = string.byte, {}, 0, #bytes
    for i = 1, n - 2, 3 do
        local a, b, c = byte(bytes, i, i + 2)
        local v = (a << 16) | (b << 8) | c
        out[j + 1] = DIGIT[v >> 18]
        out[j + 2] = DIGIT[(v >> 12) & 63]
        out[j + 3] = DIGIT[(v >> 6) & 63]
        out[j + 4] = DIGIT[v & 63]
        j = j + 4
    end
    local rest = n % 3
    if rest == 1 then
        local v = byte(bytes, n) << 16
        out[j + 1], out[j + 2], out[j + 3] = DIGIT[v >> 18], DIGIT[(v >> 12) & 63], "=="
    elseif rest == 2 then
        local a, b = byte(bytes, n - 1, n)
        local v = (a << 16) | (b << 8)
        out[j + 1], out[j + 2], out[j + 3], out[j + 4] = DIGIT[v >> 18], DIGIT[(v >> 12) & 63], DIGIT[(v >> 6) & 63], "="
    end
    return table.concat(out)
end
return M
]=]

local net, carrier
local packet, loud

app:add_systems(Startup, { ResMut[OpusEncoders], ResMut[Speakers], Commands }, function(encoders, speakers, commands)
    net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzvc" },
        ["core/net/sync"] = false,
    }):id()
    carrier = commands:spawn({ voip = {}, ["core/net/sync"] = false }):id()
    speakers:open("voip/speaker", { device = "zz no device by this name", rate = 48000 })
    local encode = load(ROOT_ENCODER)().encode
    encoders:open("zz/voip_client", 48000, "Mono", "Voip")
    local encoder = encoders:get_mut("zz/voip_client")
    packet = encode(encoder:encode(string.rep("\0", 960 * 2), 4000))
    -- A 1 kHz square wave near full scale: two of them sum past what 16 bits hold.
    local square = {}
    for i = 0, 959 do square[i + 1] = (i // 24) % 2 == 0 and 30000 or -30000 end
    local pcm = string.pack("<" .. string.rep("i2", 960), table.unpack(square))
    encoder:encode(pcm, 4000)
    loud = encode(encoder:encode(pcm, 4000))
    encoders:remove("zz/voip_client")
end)

-- What core/net writes for each frame that arrives.
local inbox = {}
app:add_systems(First, { bevy.MessageWriter["core/net/received"] }, function(received)
    for _, m in ipairs(inbox) do
        received:write(m)
    end
    inbox = {}
end):in_set("zz/voip_client_arrivals")

local function arrive(from, fields)
    local m = { msg_type = "voip/frame", channel = "voip/frame", net = "zzvc", codec = 2, data = packet, from = from }
    for k, v in pairs(fields or {}) do m[k] = v end
    inbox[#inbox + 1] = m
end

local keys = {}
app:add_systems(First, { bevy.MessageWriter["input/synthetic_key"] }, function(synthetic)
    for _, k in ipairs(keys) do
        synthetic:write({ key_code = "KeyV", state = k })
    end
    keys = {}
end):in_set("zz/voip_client_keys")

-- The suite as the device: `empty` clears the speaker's queue, `fill` writes that many samples of
-- its own; `queued` is what the mixer has written since.
local sent = {}
local probe = {}
local device = { empty = false, fill = 0 }
app:add_systems(Last, {
    bevy.MessageReader["core/net/send"],
    ResMut[OpusDecoders],
    ResMut[Speakers],
}, function(sends, decoders, speakers)
    for _, s in ipairs(sends:read()) do
        if s.msg_type == "voip/frame" then sent[#sent + 1] = s.data end
    end
    for _, id in ipairs({ "1", "7", "8", "9", "10" }) do
        probe[id] = decoders:contains_key(id)
    end
    local speaker = speakers:get_mut("voip/speaker")
    probe.speaker = speaker ~= nil
    if speaker and device.empty then speaker:clear() end
    if speaker and device.fill > 0 then speaker:write(string.rep("\0", device.fill * 2)) end
    device.empty, device.fill = false, 0
    probe.queued = speaker and speaker:queued()
    probe.state = speaker and speaker:status().state
end):in_set("zz/voip_client_probe")

local me
local remote = {}

local function get(world, id, name)
    local e = world:get_entity(id)
    return e and e:get(name)
end

local function ask(world)
    return world:query({ with = { "vault/microphone", "Request", "ChildOf" }, optional = { "vault/microphone/reply" } })[1]
end

local function asked(world)
    local a = ask(world)
    return a and a:get("vault/microphone") or {}
end

local phase, clock = "spawn", 0
local seen = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        suite.finish("VOIP_CLIENT")
    end
    local function participant(id, fields)
        local value = { client_id = id, login = "u" .. id, speaking = false, silenced = false }
        for k, v in pairs(fields or {}) do value[k] = v end
        return value
    end

    if phase == "spawn" then
        if clock < 0.2 then return end
        -- Declared first, as the net does when it starts.
        Net.declare_ownership(world, commands)
        me = commands:spawn({
            ["voip/participant"] = participant(1),
            ["core/net/owner"] = net,
            ["core/net/sync"] = false,
            input = {},
            ["input/mode"] = { mode = "input/game" },
        }):id()
        for _, id in ipairs({ 7, 8, 9, 10 }) do
            remote[id] = commands:spawn({
                ["voip/participant"] = participant(id),
                -- Another client's, as its replica names that client's connection.
                ["core/net/owner"] = commands:spawn({ ["zz/voip_client/connection"] = {}, ["core/net/sync"] = false }):id(),
                ["core/net/sync"] = false,
            }):id()
        end
        step("setup")

    elseif phase == "setup" then
        local a = ask(world)
        if not (a and get(world, me, "voip/intent")) and clock < 5 then return end
        if clock < 0.3 then return end
        local wanted = asked(world)
        local mic = get(world, me, "voip/mic") or {}
        local intent = get(world, me, "voip/intent") or {}
        local game = (get(world, me, "input/game") or {}).voip or {}
        local ui = (get(world, me, "input/ui") or {}).voip
        local channels = (get(world, net, "core/net/channels") or {}).Unreliable or {}
        local mute7, mute_me = get(world, remote[7], "voip/participant/local"), get(world, me, "voip/participant/local")
        T("C1_the_local_player_the_ask_the_remote_mute_and_the_channel",
            a ~= nil and a:get("ChildOf") == carrier and wanted.open == true and wanted.send == "none"
                and wanted.complexity == 5 and mic.muted == false and mic.mode == "push"
                and intent.listen == true and intent.transmit == false and intent.taken == 0
                and (game.talk or {}).key == "KeyV" and ui == nil
                and mute7 ~= nil and mute7.local_muted == false and mute_me == nil and channels["voip/frame"] ~= nil,
            string.format("ask under carrier=%s open=%s send=%s complexity=%s mic=%s/%s intent=%s/%s/%s V=%s ui=%s "
                .. "remote mute=%s own mute=%s channel=%s", tostring(a and a:get("ChildOf") == carrier),
                tostring(wanted.open), tostring(wanted.send), tostring(wanted.complexity), tostring(mic.muted),
                tostring(mic.mode), tostring(intent.listen), tostring(intent.transmit), tostring(intent.taken),
                tostring((game.talk or {}).key), tostring(ui ~= nil), tostring(mute7 and mute7.local_muted),
                tostring(mute_me ~= nil), tostring(channels["voip/frame"] ~= nil)))
        commands:entity(carrier):insert({ voip = { complexity = 7 } })
        step("complexity")

    elseif phase == "complexity" then
        if asked(world).complexity ~= 7 and clock < 3 then return end
        T("C2_the_complexity_follows_the_carrier", asked(world).complexity == 7, tostring(asked(world).complexity))
        keys[#keys + 1] = "Pressed"
        step("held")

    elseif phase == "held" then
        if asked(world).send ~= "all" and clock < 3 then return end
        seen.held = asked(world).send
        keys[#keys + 1] = "Released"
        step("released")

    elseif phase == "released" then
        if asked(world).send ~= "none" and clock < 3 then return end
        seen.released = asked(world).send
        commands:entity(me):insert({ ["input/mode"] = { mode = "input/ui" } })
        step("ui")

    elseif phase == "ui" then
        if clock < 0.3 then return end
        if not seen.ui_pressed then
            seen.ui_pressed = true
            keys[#keys + 1] = "Pressed"
            clock = 0
            return
        end
        local in_ui = asked(world).send
        local action = world:get_entity(me):has("input/ui/voip/talk")
        T("C3_v_held_sends_all_released_none_and_ui_input_nothing",
            seen.held == "all" and seen.released == "none" and in_ui == "none" and not action,
            string.format("held=%s released=%s in ui=%s ui action=%s", tostring(seen.held), tostring(seen.released),
                tostring(in_ui), tostring(action)))
        keys[#keys + 1] = "Released"
        commands:entity(me):insert({ ["input/mode"] = { mode = "input/game" } })
        commands:entity(me):insert({ ["voip/mic"] = { muted = false, mode = "voice" } })
        step("voice")

    elseif phase == "voice" then
        if asked(world).send ~= "voice" and clock < 3 then return end
        T("C4_open_mic_sends_what_the_gate_passes", asked(world).send == "voice", tostring(asked(world).send))
        commands:entity(me):insert({ ["voip/mic"] = { muted = true, mode = "push" } })
        step("muted")

    elseif phase == "muted" then
        if asked(world).open ~= false and clock < 3 then return end
        seen.muted = asked(world).open
        commands:entity(me):insert({ ["voip/mic"] = { muted = false, mode = "push" } })
        step("unmuted")

    elseif phase == "unmuted" then
        if asked(world).open ~= true and clock < 3 then return end
        seen.unmuted = asked(world).open
        commands:entity(me):insert({ ["voip/participant"] = participant(1, { silenced = true }) })
        step("silenced")

    elseif phase == "silenced" then
        if asked(world).open ~= false and clock < 3 then return end
        seen.silenced = asked(world).open
        commands:entity(me):insert({ ["voip/participant"] = participant(1) })
        step("unsilenced")

    elseif phase == "unsilenced" then
        if asked(world).open ~= true and clock < 3 then return end
        T("C5_muted_or_silenced_closes_the_ask_and_it_opens_again",
            seen.muted == false and seen.unmuted == true and seen.silenced == false and asked(world).open == true,
            string.format("muted=%s unmuted=%s silenced=%s back=%s", tostring(seen.muted), tostring(seen.unmuted),
                tostring(seen.silenced), tostring(asked(world).open)))
        sent = {}
        commands:entity(ask(world):id()):insert({
            ["vault/microphone/reply"] = { status = "allowed", packets = { "UDE=", "UDI=" }, last = 2, level = 0.1 },
        })
        step("window 1")

    elseif phase == "window 1" then
        if #sent < 2 and clock < 3 then return end
        if clock < 0.2 then return end
        seen.transmit = (get(world, me, "voip/intent") or {}).transmit
        commands:entity(ask(world):id()):insert({
            ["vault/microphone/reply"] = { status = "allowed", packets = { "UDI=", "UDM=" }, last = 3, level = 0.1 },
        })
        step("window 2")

    elseif phase == "window 2" then
        if #sent < 3 and clock < 3 then return end
        if clock < 0.2 then return end
        commands:entity(ask(world):id()):insert({
            ["vault/microphone/reply"] = { status = "allowed", packets = { "UDM=", "UDQ=" }, last = 4, level = 0.1 },
        })
        step("window 3")

    elseif phase == "window 3" then
        if #sent < 4 and clock < 3 then return end
        if clock < 0.3 then return end
        local intent = get(world, me, "voip/intent") or {}
        T("C6_packets_above_taken_go_once_each_none_lost",
            table.concat(sent, ",") == "UDE=,UDI=,UDM=,UDQ=" and intent.taken == 4 and seen.transmit == true,
            string.format("sent=[%s] taken=%s transmit=%s", table.concat(sent, ","), tostring(intent.taken),
                tostring(seen.transmit)))
        commands:entity(remote[8]):insert({ ["voip/participant/local"] = { local_muted = true } })
        step("receive")

    elseif phase == "receive" then
        if clock < 0.2 then return end
        if not seen.arrived then
            seen.arrived = true
            device.empty = true
            for _ = 1, 2 do arrive(7) end
            for _ = 1, 3 do
                arrive(8)
                arrive(1)
                arrive(9, { net = "zzother" })
            end
            clock = 0
            return
        end
        if clock < 0.4 then return end
        seen.two = probe.queued
        arrive(7)
        step("primed")

    elseif phase == "primed" then
        if (probe.queued or 0) == 0 and clock < 3 then return end
        if clock < 0.3 then return end
        T("C7_a_participants_frames_are_decoded_and_never_own_muted_or_another_nets",
            probe["7"] and not probe["8"] and not probe["1"] and not probe["9"] and seen.two == 0,
            string.format("decoder 7=%s 8 (muted)=%s 1 (own)=%s 9 (other net)=%s; written before 7 primed=%s",
                tostring(probe["7"]), tostring(probe["8"]), tostring(probe["1"]), tostring(probe["9"]),
                tostring(seen.two)))
        T("C12_a_source_waits_for_3_blocks_then_fills_the_speaker_to_60_ms",
            seen.two == 0 and probe.queued == 2880 and probe.state == "no_device",
            string.format("after 2 blocks=%s after 3=%s speaker=%s", tostring(seen.two), tostring(probe.queued),
                tostring(probe.state)))
        device.empty, device.fill = true, 3000
        for _ = 1, 3 do arrive(7) end
        step("full")

    elseif phase == "full" then
        if clock < 0.4 then return end
        T("C13_a_speaker_holding_more_than_60_ms_is_written_nothing", probe.queued == 3000,
            "queued " .. tostring(probe.queued) .. " of the 3000 the suite wrote")
        commands:entity(remote[7]):remove("voip/participant")
        step("forget")

    elseif phase == "forget" then
        if probe["7"] and clock < 3 then return end
        if not seen.drained then
            seen.drained = true
            device.empty = true
            clock = 0
            return
        end
        if clock < 0.4 then return end
        T("C8_a_participant_gone_takes_its_decoder_and_its_buffer_never_plays",
            not probe["7"] and get(world, remote[7], "voip/participant/local") == nil and probe.queued == 0,
            string.format("decoder 7=%s local mute=%s written after=%s", tostring(probe["7"]),
                tostring(get(world, remote[7], "voip/participant/local") ~= nil), tostring(probe.queued)))
        sent = {}
        commands:entity(ask(world):id()):insert({
            ["vault/microphone/reply"] = { status = "no_device", packets = { "UDU=" }, last = 5, level = 0 },
        })
        step("no device")

    elseif phase == "no device" then
        if (get(world, me, "voip/intent") or {}).transmit ~= false and clock < 3 then return end
        if clock < 0.2 then return end
        if not seen.heard then
            seen.heard = true
            arrive(9, { data = loud })
            clock = 0
            return
        end
        if not probe["9"] and clock < 3 then return end
        T("C9_with_no_microphone_nothing_is_sent_and_frames_are_heard",
            #sent == 0 and (get(world, me, "voip/intent") or {}).transmit == false and probe["9"],
            string.format("sent=%d transmit=%s decoder 9=%s", #sent,
                tostring((get(world, me, "voip/intent") or {}).transmit), tostring(probe["9"])))
        device.empty, device.fill = true, 1920
        for _ = 1, 3 do
            arrive(9, { data = loud })
            arrive(10, { data = loud })
        end
        step("mix")

    elseif phase == "mix" then
        if (probe.queued or 0) <= 1920 and clock < 3 then return end
        if clock < 0.3 then return end
        T("C14_two_loud_sources_mix_into_one_clamped_write", probe.queued == 2880 and probe["10"],
            string.format("queued %s: 1920 the suite wrote and %s mixed", tostring(probe.queued),
                tostring((probe.queued or 0) - 1920)))
        for _, id in ipairs({ 9, 10 }) do
            commands:entity(remote[id]):insert({ ["voip/participant/local"] = { local_muted = true } })
        end
        device.empty = true
        step("muted here")

    elseif phase == "muted here" then
        if clock < 0.4 then return end
        T("C15_a_participant_muted_here_never_plays_what_it_had_buffered", probe.queued == 0,
            "written after the mute: " .. tostring(probe.queued))
        commands:entity(remote[9]):insert({ ["voip/participant"] = participant(9, { speaking = true }) })
        step("speaking")

    elseif phase == "speaking" then
        local function sphere()
            return world:query({ with = { "voip/indicator", "ChildOf", "Transform" } })[1]
        end
        if not seen.sphere then
            if sphere() == nil and clock < 3 then return end
            local s = sphere()
            seen.sphere = s ~= nil and s:get("ChildOf") == remote[9]
            commands:entity(remote[9]):insert({ ["voip/participant"] = participant(9) })
            clock = 0
            return
        end
        if sphere() ~= nil and clock < 3 then return end
        T("C10_the_speaking_sphere_follows_speaking", seen.sphere == true and sphere() == nil,
            string.format("shown on the speaker=%s gone=%s", tostring(seen.sphere), tostring(sphere() == nil)))
        commands:entity(me):remove("voip/participant")
        step("left")

    elseif phase == "left" then
        local intent = get(world, me, "voip/intent")
        local game = (get(world, me, "input/game") or {}).voip
        if (intent ~= nil or game ~= nil or probe.speaker) and clock < 3 then return end
        T("C11_no_longer_a_participant_takes_the_intent_the_key_and_the_speaker",
            intent == nil and game == nil and get(world, me, "voip/mic") == nil and not probe.speaker,
            string.format("intent=%s key=%s mic=%s speaker=%s", tostring(intent ~= nil), tostring(game ~= nil),
                tostring(get(world, me, "voip/mic") ~= nil), tostring(probe.speaker)))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/voip_client_suite")
