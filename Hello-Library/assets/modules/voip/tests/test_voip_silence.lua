-- test_voip_silence.lua: the server half of voip applies a `voip/silence` entry only from a user
-- whose connection's `core/permission/grants` name "writer", never of themself. The suite stands
-- in for the permission provider (it writes each connection's grants, as a provider names
-- `core/permission` and writes them; no git permission provider loads), for core/net (a real
-- world net, each client's `core/net/connection` under it, a client's `voip/silence` as core
-- applies its owner's update, and the `core/net/received` core writes for each frame) and for the
-- player spawner (players owned by their connection).
--
-- X1  a writer's entry silences another: their connection gets `voip/silenced`, their participant
--     says so, and their frames stop going
-- X2  the writer's false entry unsilences them, and their frames go again
-- X3  a writer's entry naming themself changes nothing
-- X6  writer A silences 4, writer B unsilences 4, then A silences 6 as well: 4 stays unsilenced
--     (A's standing entry for 4 is not applied again) and 6 is silenced; A's connection holds
--     what was applied
-- X4  an entry from a user whose grants do not name "writer", or who has none, changes nothing
-- X5  a writer whose grants lose "writer" is ignored from then on
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local bevy = require("bevy::prelude")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("VoipSilenceSuite")
local T = suite.assert_test

local net
local c, p = {}, {}

app:add_systems(Startup, { Commands }, function(commands)
    net = commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzvx", port = 15867 },
        ["core/net/sync"] = false,
    }):id()
    -- 1 and 5 may write the world's files; 2's grants name nothing; 3 has none; 4 and 6 are whom
    -- they silence.
    local grants = { { names = { "writer" } }, { names = {} }, nil, nil, { names = { "writer" } } }
    for id = 1, 6 do
        c[id] = commands:spawn({
            ["core/net/connection"] = { client_id = id, observer = false },
            ["core/permission/grants"] = grants[id],
            ["core/net/sync"] = false,
            ChildOf = net,
        }):id()
        p[id] = commands:spawn({ player = { client_id = id }, ["core/net/owner"] = c[id], ["core/net/sync"] = false }):id()
    end
    commands:spawn({ voip = {}, ["core/net/sync"] = false })
end)

local outbox = {}
app:add_systems(First, { bevy.MessageWriter["core/net/received"] }, function(received)
    for _, m in ipairs(outbox) do
        received:write(m)
    end
    outbox = {}
end):in_set("zz/voip_silence_senders")

local function frame(client_id, data)
    outbox[#outbox + 1] = { msg_type = "voip/frame", channel = "voip/frame", net = "zzvx", client_id = client_id, codec = 2, data = data }
end

-- data -> how many forwards it got
local sent = {}
app:add_systems(Last, { bevy.MessageReader["core/net/send_to_client"] }, function(sends)
    for _, s in ipairs(sends:read()) do
        local data = tostring((s.msg or {}).data)
        sent[data] = (sent[data] or 0) + 1
    end
end):in_set("zz/voip_silence_forwards")

local function silenced(world, id)
    return world:get_entity(c[id]):has("voip/silenced")
end

local function says(world, id)
    return ((world:get_entity(p[id]):get("voip/participant")) or {}).silenced
end

local phase, clock = "start", 0
local seen = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        suite.finish("VOIP_SILENCE")
    end
    local function wish(id, entries)
        commands:entity(p[id]):insert({ ["voip/silence"] = entries })
    end

    if phase == "start" then
        -- The players were owned before the net started, so their connections list them only once
        -- it has declared ownership.
        local listed = world:get_entity(c[4]):get("core/net/owns") and world:get_entity(c[1]):get("core/net/owns")
        if (says(world, 4) == nil or not listed) and clock < 5 then return end
        frame(4, "WDBiZWZvcmU=")
        step("x1 before")

    elseif phase == "x1 before" then
        if sent["WDBiZWZvcmU="] == nil and clock < 3 then return end
        wish(1, { ["4"] = true })
        step("x1")

    elseif phase == "x1" then
        if not (silenced(world, 4) and says(world, 4)) and clock < 3 then return end
        if not seen.x1 then
            seen.x1 = true
            seen.x1_clock = clock
            frame(4, "WDFzaWxlbmNlZA==")
        end
        if clock < seen.x1_clock + 0.5 then return end
        T("X1_a_writer_silences_another_and_their_frames_stop",
            silenced(world, 4) and says(world, 4) == true and (sent["WDBiZWZvcmU="] or 0) > 0 and sent["WDFzaWxlbmNlZA=="] == nil,
            string.format("silenced=%s participant says=%s forwards before=%s after=%s", tostring(silenced(world, 4)),
                tostring(says(world, 4)), tostring(sent["WDBiZWZvcmU="]), tostring(sent["WDFzaWxlbmNlZA=="])))
        wish(1, { ["4"] = false })
        step("x2")

    elseif phase == "x2" then
        if not (not silenced(world, 4) and says(world, 4) == false) and clock < 3 then return end
        if not seen.x2 then
            seen.x2 = true
            seen.x2_clock = clock
            frame(4, "WDJiYWNr")
        end
        if clock < seen.x2_clock + 0.5 then return end
        T("X2_the_writers_false_entry_unsilences_and_frames_go_again",
            not silenced(world, 4) and says(world, 4) == false and (sent["WDJiYWNr"] or 0) > 0,
            string.format("silenced=%s participant says=%s forwards=%s", tostring(silenced(world, 4)),
                tostring(says(world, 4)), tostring(sent["WDJiYWNr"])))
        wish(1, { ["4"] = false, ["1"] = true })
        step("x3")

    elseif phase == "x3" then
        if clock < 0.5 then return end
        T("X3_a_writer_never_silences_themself", not silenced(world, 1) and says(world, 1) == false,
            string.format("silenced=%s participant says=%s", tostring(silenced(world, 1)), tostring(says(world, 1))))
        wish(1, { ["4"] = true })
        step("x6 a")

    elseif phase == "x6 a" then
        if not silenced(world, 4) and clock < 3 then return end
        seen.x6_a = silenced(world, 4)
        wish(5, { ["4"] = false })
        step("x6 b")

    elseif phase == "x6 b" then
        if silenced(world, 4) and clock < 3 then return end
        seen.x6_b = not silenced(world, 4)
        wish(1, { ["4"] = true, ["6"] = true })
        step("x6")

    elseif phase == "x6" then
        if not silenced(world, 6) and clock < 3 then return end
        if clock < 0.5 then return end
        local applied = world:get_entity(c[1]):get("voip/silence/applied") or {}
        T("X6_a_standing_entry_is_not_applied_again_over_another_writers_change",
            seen.x6_a and seen.x6_b and not silenced(world, 4) and says(world, 4) == false and silenced(world, 6)
                and applied["4"] == true and applied["6"] == true,
            string.format("A silenced 4=%s B unsilenced 4=%s; now 4 silenced=%s 6 silenced=%s applied 4=%s 6=%s",
                tostring(seen.x6_a), tostring(seen.x6_b), tostring(silenced(world, 4)), tostring(silenced(world, 6)),
                tostring(applied["4"]), tostring(applied["6"])))
        wish(2, { ["4"] = true })
        wish(3, { ["4"] = true, ["1"] = true })
        step("x4")

    elseif phase == "x4" then
        if clock < 0.5 then return end
        T("X4_an_entry_from_a_user_without_writer_changes_nothing",
            not silenced(world, 4) and not silenced(world, 1) and says(world, 4) == false,
            string.format("4 silenced=%s 1 silenced=%s", tostring(silenced(world, 4)), tostring(silenced(world, 1))))
        commands:entity(c[1]):insert({ ["core/permission/grants"] = { names = {} } })
        step("x5 grants")

    elseif phase == "x5 grants" then
        if clock < 0.3 then return end
        wish(1, { ["4"] = true })
        step("x5")

    elseif phase == "x5" then
        if clock < 0.5 then return end
        T("X5_a_writer_who_loses_writer_is_ignored", not silenced(world, 4) and says(world, 4) == false,
            string.format("4 silenced=%s", tostring(silenced(world, 4))))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("X0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/voip_silence_suite")
