-- test_voip_panel.lua: voip's items in the people panel's rows, on this client's world net,
-- unconnected. The suite stands in for the people panel (its rows, each with
-- `sidebar/people/row/player` naming its player, built and rebuilt as the panel does, and the
-- relationship declared as the panel declares it), for the server (each player's synced
-- `voip/participant`, the local player's owned by this client's net) and for core/permission (the
-- grants on this client's own net entity). Clicks are real `Pointer<Click>` events.
--
-- V1  a remote participant's row gets the speaking dot and Mute, and no Silence without the
--     grant; the local player's row gets the microphone, its level and the mode; a row whose
--     player is no participant gets nothing
-- V2  a click on Mute mutes that participant here, on Mute mic mutes the microphone, on the mode
--     switches to open mic; each label follows
-- V3  with "writer" in this client's grants, Silence comes on each remote row, and goes with it
-- V4  a click on Silence writes that participant's entry into the local player's `voip/silence`;
--     the label waits for the server's `silenced`, and follows it
-- V5  the speaking dot follows `speaking`
-- V6  a rebuilt row gets its items again, once each, showing the state as it stands
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local Net = require("modules/core/net/shared/net.lua")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("VoipPanelSuite")
local T = suite.assert_test

local net, camera

app:add_systems(Startup, { Commands }, function(commands)
    net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzvpanel" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({ voip = {}, ["core/net/sync"] = false })
    camera = commands:spawn({ ["zz/voip_panel/camera"] = {} }):id()
    commands:spawn({
        LuaRelationship = { source = "sidebar/people/row/player", target = "sidebar/people/row/players", linked_spawn = true },
    })
end)

local me, other, plain
local rows = {}

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

-- Rows by the suite's name for their player: "me", "other", "plain".
local function build(commands)
    for name, player in pairs({ me = me, other = other, plain = plain }) do
        rows[name] = commands:spawn({
            ["sidebar/people/row"] = {},
            ["sidebar/people/row/player"] = { entity = player },
            ["core/net/sync"] = false,
        }):id()
    end
end

-- The voip items on the row of the player the suite calls `name`, as kind -> { id, label,
-- enabled, button }, and how many.
local function controls(world, name)
    local out, n = {}, 0
    local row = world:get_entity(rows[name])
    for _, item in ipairs(world:query({
        with = { "voip/control", "sidebar/people/row/item" },
        iter_many = row and row:get("Children") or {},
    })) do
        local shown = item:get("sidebar/people/row/item")
        out[item:get("voip/control").kind] = { id = item:id(), label = shown.label, enabled = shown.enabled, button = shown.button }
        n = n + 1
    end
    return out, n
end

local function label(world, name, kind)
    return (controls(world, name)[kind] or {}).label
end

local function get(world, id, name)
    local e = world:get_entity(id)
    return e and e:get(name)
end

local phase, clock = "spawn", 0
local seen = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        suite.finish("VOIP_PANEL")
    end
    local function participant(id, fields)
        local value = { client_id = id, login = "u" .. id, speaking = false, silenced = false }
        for k, v in pairs(fields or {}) do value[k] = v end
        return value
    end

    if phase == "spawn" then
        if clock < 0.2 then return end
        Net.declare_ownership(world, commands)
        me = commands:spawn({
            ["voip/participant"] = participant(1),
            ["core/net/owner"] = net,
            ["core/net/sync"] = false,
        }):id()
        other = commands:spawn({
            ["voip/participant"] = participant(7),
            ["core/net/owner"] = commands:spawn({ ["zz/voip_panel/connection"] = {}, ["core/net/sync"] = false }):id(),
            ["core/net/sync"] = false,
        }):id()
        plain = commands:spawn({ ["zz/voip_panel/plain"] = {}, ["core/net/sync"] = false }):id()
        -- The first rows come with their players, as the panel builds a row for a player
        -- arriving; only the rebuild below rests on the rows' own edge alone.
        build(commands)
        step("items")

    elseif phase == "items" then
        local _, n = controls(world, "other")
        if n < 2 and clock < 3 then return end
        if clock < 0.3 then return end
        local theirs, n_theirs = controls(world, "other")
        local mine, n_mine = controls(world, "me")
        local _, n_plain = controls(world, "plain")
        T("V1_remote_and_local_rows_get_their_items_and_a_non_participant_none",
            n_theirs == 2 and theirs.speaking and theirs.speaking.label == "*" and theirs.speaking.enabled == false
                and theirs.speaking.button == false and theirs.mute and theirs.mute.label == "Mute"
                and theirs.mute.button == true and theirs.silence == nil
                and n_mine == 3 and (mine.mic or {}).label == "Mute mic" and (mine.level or {}).label == ""
                and (mine.mode or {}).label == "Push to talk (V)" and n_plain == 0,
            string.format("remote %d [%s %s %s] local %d [%s|%s|%s] plain %d", n_theirs,
                tostring((theirs.speaking or {}).label), tostring((theirs.mute or {}).label), tostring(theirs.silence ~= nil),
                n_mine, tostring((mine.mic or {}).label), tostring((mine.level or {}).label),
                tostring((mine.mode or {}).label), n_plain))
        if not (theirs.mute and mine.mic and mine.mode) then
            finish()
            return
        end
        click(commands, theirs.mute.id)
        click(commands, mine.mic.id)
        click(commands, mine.mode.id)
        step("clicked")

    elseif phase == "clicked" then
        if label(world, "other", "mute") ~= "Unmute" and clock < 3 then return end
        if clock < 0.3 then return end
        local mic = get(world, me, "voip/mic") or {}
        T("V2_mute_mic_and_mode_clicks_write_their_fields_and_labels_follow",
            (get(world, other, "voip/participant/local") or {}).local_muted == true and mic.muted == true
                and mic.mode == "voice" and label(world, "other", "mute") == "Unmute"
                and label(world, "me", "mic") == "Unmute mic" and label(world, "me", "mode") == "Open mic",
            string.format("local_muted=%s muted=%s mode=%s labels %s / %s / %s",
                tostring((get(world, other, "voip/participant/local") or {}).local_muted), tostring(mic.muted),
                tostring(mic.mode), tostring(label(world, "other", "mute")), tostring(label(world, "me", "mic")),
                tostring(label(world, "me", "mode"))))
        commands:entity(net):insert({ ["core/permission/grants"] = { names = { "writer" } } })
        step("granted")

    elseif phase == "granted" then
        if label(world, "other", "silence") == nil and clock < 3 then return end
        if clock < 0.2 then return end
        seen.shown = label(world, "other", "silence")
        seen.mine = controls(world, "me").silence
        click(commands, controls(world, "other").silence.id)
        step("silence clicked")

    elseif phase == "silence clicked" then
        if get(world, me, "voip/silence") == nil and clock < 3 then return end
        if clock < 0.3 then return end
        local wishes = get(world, me, "voip/silence") or {}
        T("V4_a_click_on_silence_writes_the_entry_and_the_label_waits_for_the_server",
            seen.shown == "Silence" and seen.mine == nil and wishes["7"] == true and label(world, "other", "silence") == "Silence",
            string.format("shown=%s on own row=%s entry=%s label now=%s", tostring(seen.shown), tostring(seen.mine ~= nil),
                tostring(wishes["7"]), tostring(label(world, "other", "silence"))))
        commands:entity(other):insert({ ["voip/participant"] = participant(7, { silenced = true, speaking = true }) })
        step("silenced")

    elseif phase == "silenced" then
        if label(world, "other", "silence") ~= "Unsilence" and clock < 3 then return end
        if clock < 0.2 then return end
        seen.followed = label(world, "other", "silence")
        T("V5_the_speaking_dot_follows_speaking", (controls(world, "other").speaking or {}).enabled == true,
            tostring((controls(world, "other").speaking or {}).enabled))
        commands:entity(net):insert({ ["core/permission/grants"] = { names = {} } })
        step("ungranted")

    elseif phase == "ungranted" then
        if label(world, "other", "silence") ~= nil and clock < 3 then return end
        if clock < 0.2 then return end
        T("V3_silence_comes_with_the_writer_grant_and_goes_with_it",
            seen.shown == "Silence" and seen.followed == "Unsilence" and label(world, "other", "silence") == nil,
            string.format("with=%s after the server=%s without=%s", tostring(seen.shown), tostring(seen.followed),
                tostring(label(world, "other", "silence"))))
        seen.old = { rows.me, rows.other, rows.plain }
        for _, row in ipairs(seen.old) do
            commands:entity(row):despawn()
        end
        build(commands)
        step("rebuilt")

    elseif phase == "rebuilt" then
        local _, n = controls(world, "other")
        if n < 2 and clock < 3 then return end
        if clock < 0.5 then return end
        local theirs, n_theirs = controls(world, "other")
        local mine, n_mine = controls(world, "me")
        local _, n_plain = controls(world, "plain")
        T("V6_a_rebuilt_row_gets_its_items_again_once_each_showing_the_state",
            rows.other ~= seen.old[2] and n_theirs == 2 and n_mine == 3 and n_plain == 0
                and (theirs.mute or {}).label == "Unmute" and (theirs.speaking or {}).enabled == true
                and (mine.mic or {}).label == "Unmute mic" and (mine.mode or {}).label == "Open mic",
            string.format("remote %d [%s] local %d [%s|%s] plain %d", n_theirs, tostring((theirs.mute or {}).label),
                n_mine, tostring((mine.mic or {}).label), tostring((mine.mode or {}).label), n_plain))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("V0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/voip_panel_suite")
