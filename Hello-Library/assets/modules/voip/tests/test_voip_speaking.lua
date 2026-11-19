-- test_voip_speaking.lua: the server half of voip says who is speaking. A relayed frame stamps its
-- sender's connection with `voip/heard`, at most every 100 ms, and the participant speaks from a
-- stamp until 300 ms after the last. The suite stands in for core/net (a real world net, each
-- client's `core/net/connection` under it, and the `core/net/received` core writes for each frame
-- a client sends) and for the player spawner (players owned by their connection).
--
-- S1  a first frame stamps the sender's connection and makes that participant speak, and only that one
-- S2  a frame every frame for 1.2 s: `voip/heard.at` changes at most every 100 ms, and keeps changing
-- S3  the participant speaks all the while
-- S4  300 ms after the last stamp it no longer speaks, and not before
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local bevy = require("bevy::prelude")
local Time = require("bevy::time::Time")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("VoipSpeakingSuite")
local T = suite.assert_test

local net
local c, p = {}, {}

app:add_systems(Startup, { Commands }, function(commands)
    net = commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzvs", port = 15865 },
        ["core/net/sync"] = false,
    }):id()
    for id = 2, 3 do
        c[id] = commands:spawn({
            ["core/net/connection"] = { client_id = id, observer = false },
            ["core/net/sync"] = false,
            ChildOf = net,
        }):id()
        p[id] = commands:spawn({ player = { client_id = id }, ["core/net/owner"] = c[id], ["core/net/sync"] = false }):id()
    end
    commands:spawn({ voip = {}, ["core/net/sync"] = false })
end)

-- Client 2 talking: one frame a frame, as core writes it on arrival.
local talking = false
app:add_systems(First, { bevy.MessageWriter["core/net/received"] }, function(received)
    if talking then
        received:write({ msg_type = "voip/frame", channel = "voip/frame", net = "zzvs", client_id = 2, codec = 2, data = "UzJ0YWxr" })
    end
end):in_set("zz/voip_speaking_sender")

-- Every stamp, as a consumer sees it: its edge, and the `at` it says.
local stamps = {}
app:add_systems(Update, { Query[{ changed = { "voip/heard" } }] }, function(heard)
    for _, h in ipairs(heard:iter()) do
        stamps[#stamps + 1] = h:get("voip/heard").at
    end
end):in_set("zz/voip_speaking_stamps")

local function speaking(world, id)
    local e = world:get_entity(p[id])
    return ((e and e:get("voip/participant")) or {}).speaking
end

local phase, clock = "start", 0
local seen = {}

app:add_systems(Update, { World, Res[Time] }, function(world, time)
    if phase == "done" then return end
    local now = time:elapsed_secs()
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        talking = false
        phase = "done"
        suite.finish("VOIP_SPEAKING")
    end

    if phase == "start" then
        if (speaking(world, 2) == nil or speaking(world, 3) == nil) and clock < 5 then return end
        seen.quiet = speaking(world, 2) == false and speaking(world, 3) == false
        talking = true
        step("first")

    elseif phase == "first" then
        local heard = world:get_entity(c[2]):get("voip/heard")
        if not (heard and speaking(world, 2)) and clock < 3 then return end
        T("S1_a_first_frame_stamps_its_sender_and_makes_only_them_speak",
            seen.quiet and heard ~= nil and speaking(world, 2) == true and speaking(world, 3) == false
                and world:get_entity(c[3]):get("voip/heard") == nil,
            string.format("quiet before=%s heard=%s speaking 2=%s 3=%s", tostring(seen.quiet), tostring(heard ~= nil),
                tostring(speaking(world, 2)), tostring(speaking(world, 3))))
        stamps = {}
        seen.always = true
        step("talk")

    elseif phase == "talk" then
        if speaking(world, 2) ~= true then seen.always = false end
        if clock < 1.2 then return end
        talking = false
        local gap = math.huge
        for i = 2, #stamps do gap = math.min(gap, stamps[i] - stamps[i - 1]) end
        T("S2_heard_changes_at_most_every_100_ms_and_keeps_changing", #stamps >= 8 and #stamps <= 13 and gap >= 0.099,
            string.format("stamps=%d smallest gap=%.3f s", #stamps, gap))
        T("S3_the_participant_speaks_all_the_while", seen.always, "speaking turned false while frames flowed")
        seen.last = world:get_entity(c[2]):get("voip/heard").at
        step("quiet")

    elseif phase == "quiet" then
        if speaking(world, 2) ~= false and clock < 2 then return end
        local after = now - seen.last
        T("S4_no_longer_speaking_300_ms_after_the_last_stamp", speaking(world, 2) == false and after >= 0.299 and after <= 0.45,
            string.format("speaking=%s after %.3f s", tostring(speaking(world, 2)), after))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/voip_speaking_suite")
