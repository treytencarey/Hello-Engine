-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("PerceptionSuite")

-- An agent looks along +z from its slot. Slots are 100 m apart.
local function agent(commands, name, slot, perception)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/agent"] = { think_hz = 20 },
        ["ai/perception"] = perception or {},
        Transform = { translation = { x = slot * 100, y = 1, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
    })
end

local function target(commands, name, slot, z, x)
    commands:spawn({
        ["zz/target"] = { name = name },
        ["ai/perception/target"] = {},
        Transform = { translation = { x = slot * 100 + (x or 0), y = 1, z = z } },
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    agent(commands, "sees", 1)
    target(commands, "ahead", 1, 10)
    target(commands, "beside", 1, 0, 25)

    agent(commands, "behind", 2)
    target(commands, "at back", 2, -10)
    target(commands, "at elbow", 2, -2)

    agent(commands, "too far", 3)
    target(commands, "far", 3, 30)

    agent(commands, "walled", 4)
    target(commands, "hidden", 4, 10)
    commands:spawn({
        Transform = { translation = { x = 400, y = 1, z = 5 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 5, hy = 5, hz = 0.5 } },
    })

    agent(commands, "forgets", 5, { forget_seen_after = 0.5 })
    target(commands, "goes", 5, 10)
    agent(commands, "remembers", 6)
    target(commands, "stops being seen", 6, 10)
    agent(commands, "two", 7)
    target(commands, "first", 7, 8)
    target(commands, "second", 7, 9)
    commands:spawn({
        ["zz/name"] = { name = "mirrored" },
        ["ai/agent"] = { think_hz = 20 },
        ["ai/perception"] = {},
        Transform = { translation = { x = 800, y = 1, z = 0 } },
    })
    commands:spawn({ ["ai/perception/target"] = {}, WorldMirror = {}, Transform = { translation = { x = 800, y = 1, z = 5 } } })
    agent(commands, "self", 9)
    commands:spawn({ ["zz/name"] = { name = "looks at itself" }, ["ai/agent"] = { think_hz = 20 }, ["ai/perception"] = {},
        ["ai/perception/target"] = {}, Transform = { translation = { x = 950, y = 1, z = 0 } } })

    agent(commands, "hears", 10, { forget_sound_after = 1 })
    agent(commands, "deaf", 11)

    -- to one side, past half the cone and inside all of it
    agent(commands, "narrow", 12)
    target(commands, "to one side", 12, 3.4, 9.4)
    -- eyes inside its own body, which is no wall
    agent(commands, "low eyes", 13, { eye_height = 0.5 })
    target(commands, "from inside", 13, 6)
    -- over two low walls, one by each end of the look
    agent(commands, "over walls", 14)
    target(commands, "beyond walls", 14, 10)
    for _, z in ipairs({ 1, 9 }) do
        commands:spawn({
            Transform = { translation = { x = 1400, y = 0.75, z = z } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 5, hy = 0.5, hz = 0.05 } },
        })
    end
    -- a target with a body, as a player has: its own body is not what hides it
    agent(commands, "at a body", 15)
    commands:spawn({
        ["zz/target"] = { name = "with a body" },
        ["ai/perception/target"] = {},
        Transform = { translation = { x = 1500, y = 1, z = 8 } },
        RigidBody3d = "Fixed",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
    })
    -- nearer than the look stops short of
    agent(commands, "touching", 16, { eye_height = 0.5 })
    target(commands, "at its nose", 16, 0.2)
    -- the last of what it holds goes
    agent(commands, "tail", 17)
    target(commands, "tail first", 17, 8)
    target(commands, "tail last", 17, 9)
    -- sees nothing, and thinks slowly at something
    agent(commands, "blind", 18)
    commands:spawn({
        ["zz/name"] = { name = "slow" },
        ["ai/agent"] = { think_hz = 2 },
        ["ai/perception"] = {},
        Transform = { translation = { x = 1900, y = 1, z = 0 } },
    })
    target(commands, "slowly seen", 19, 6)
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/perception", "ai/agent/memory" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function target_of(world, name)
    for _, e in ipairs(world:query({ with = { "zz/target" } })) do
        if e:get("zz/target").name == name then
            return e
        end
    end
end

local function seen_of(world, name)
    return named(world, name):get("ai/agent/memory").seen
end

local function sound_of(world, name)
    return named(world, name):get("ai/agent/memory").sound
end

local function saw(world, name, what)
    local id = target_of(world, what):id()
    for _, entry in ipairs(seen_of(world, name)) do
        if entry.entity == id then
            return entry
        end
    end
end

local sounding = nil
app:add_systems(Update, { Commands, Query[{ with = { "zz/name" } }] }, function(commands, names)
    if sounding then
        for _, e in ipairs(names:iter()) do
            if e:get("zz/name").name == "hears" then
                for i, loudness in ipairs(sounding) do
                    commands:trigger("ai/noisemaker/sound", {
                        entity = e:id(),
                        x = 1000 + i,
                        y = 1,
                        z = 10,
                        loudness = loudness,
                        kind = "footstep",
                    })
                end
            end
        end
        sounding = nil
    end
end):in_set("zz/perception_suite_sounds")

-- Writes to the memory of the agents that should write little.
local writes = { blind = 0, slow = 0, deaf = 0 }
app:add_systems(Update, {
    Query[{
        changed = { "ai/agent/memory" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        local name = e:get("zz/name").name
        if writes[name] ~= nil then
            writes[name] = writes[name] + 1
        end
    end
end):in_set("zz/perception_suite_writes")

local phase, clock = "looking", 0
local seen_at_before = nil

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "looking" and clock > 1 then
        local p = named(world, "sees"):get("ai/perception")
        suite.assert_test("P1_missing_fields_get_defaults", p.vision_range == 18 and p.vision_fov_deg == 100 and p.hearing_range == 25, "")
        local e = saw(world, "sees", "ahead")
        suite.assert_test("P2_it_sees_what_is_ahead", e ~= nil and e.at.z == 10 and e.at.x == 100 and e.seen_at > 0, "")
        suite.assert_test("P3_its_memory_is_a_list_once_per_target", #seen_of(world, "sees") == 1, "entries " .. #seen_of(world, "sees"))
        suite.assert_test("P4_nothing_outside_the_cone", saw(world, "behind", "at back") == nil, "")
        suite.assert_test("P5_except_close_by", saw(world, "behind", "at elbow") ~= nil, "")
        suite.assert_test("P6_nothing_out_of_range", saw(world, "too far", "far") == nil, "")
        -- A collider counts from the physics step after it lands, so the very first look can get through.
        local hidden = saw(world, "walled", "hidden")
        suite.assert_test("P7_nothing_behind_a_wall", hidden == nil or hidden.seen_at < time:elapsed_secs() - 0.5, "")
        suite.assert_test("P8_it_holds_several", saw(world, "two", "first") ~= nil and saw(world, "two", "second") ~= nil, "")
        suite.assert_test("P9_no_mirror_of_a_target_elsewhere", #seen_of(world, "mirrored") == 0, "")
        suite.assert_test("P10_it_does_not_see_itself", #seen_of(world, "looks at itself") == 0, "")

        seen_at_before = saw(world, "sees", "ahead").seen_at
        suite.assert_test("P21_past_half_the_cone_is_outside_it", saw(world, "narrow", "to one side") == nil, "")
        suite.assert_test("P22_its_own_body_hides_nothing", saw(world, "low eyes", "from inside") ~= nil, "")
        suite.assert_test("P23_it_looks_from_its_eyes_at_a_targets_height", saw(world, "over walls", "beyond walls") ~= nil, "")
        suite.assert_test("P24_a_targets_own_body_does_not_hide_it", saw(world, "at a body", "with a body") ~= nil, "")
        suite.assert_test("P25_it_sees_what_is_at_its_nose", saw(world, "touching", "at its nose") ~= nil, "")
        commands:entity(target_of(world, "tail last"):id()):despawn()
        writes.blind, writes.slow, writes.deaf = 0, 0, 0
        commands:entity(target_of(world, "goes"):id()):remove("ai/perception/target")
        commands:entity(target_of(world, "stops being seen"):id()):remove("ai/perception/target")
        commands:entity(target_of(world, "first"):id()):despawn()
        step("later")

    elseif phase == "later" and clock > 1 then
        suite.assert_test("P11_each_look_freshens_what_it_sees", saw(world, "sees", "ahead").seen_at > seen_at_before, "")
        suite.assert_test("P12_what_it_no_longer_sees_is_forgotten_in_time", #seen_of(world, "forgets") == 0,
            "entries " .. #seen_of(world, "forgets"))
        local kept = saw(world, "remembers", "stops being seen")
        suite.assert_test("P13_and_until_then_it_stays_where_it_was_seen", kept ~= nil and kept.at.z == 10 and kept.seen_at <= seen_at_before + 0.2, "")
        suite.assert_test("P14_an_entity_that_goes_leaves_memory_and_the_list_closes_up",
            #seen_of(world, "two") == 1 and saw(world, "two", "second") ~= nil, "entries " .. #seen_of(world, "two"))
        suite.assert_test("P26_when_the_last_it_holds_goes_it_is_not_kept",
            #seen_of(world, "tail") == 1 and saw(world, "tail", "tail first") ~= nil, "entries " .. #seen_of(world, "tail"))
        suite.assert_test("P27_nothing_seen_nothing_written", writes.blind == 0, "writes " .. writes.blind)
        suite.assert_test("P28_it_looks_only_when_it_thinks", writes.slow >= 1 and writes.slow <= 3, "writes " .. writes.slow)
        sounding = { 1, 1 }
        writes.deaf = 0
        step("two sounds")

    elseif phase == "two sounds" and clock > 0.2 then
        local s = sound_of(world, "hears")
        suite.assert_test("P15_two_sounds_in_one_frame_both_survive", #s == 2 and s[1].at.x == 1001 and s[2].at.x == 1002,
            "sounds " .. #s)
        suite.assert_test("P16_a_sound_says_where_and_when", s[1] ~= nil and s[1].at.z == 10 and s[1].heard_at > 0, "")
        suite.assert_test("P17_out_of_range_it_is_not_heard", #sound_of(world, "deaf") == 0, "sounds " .. #sound_of(world, "deaf"))
        suite.assert_test("P29_nothing_heard_nothing_written", writes.deaf == 0, "writes " .. writes.deaf)
        sounding = { 0.1 }
        step("quiet sound")

    elseif phase == "quiet sound" and clock > 0.2 then
        suite.assert_test("P18_a_quiet_sound_carries_less_far", #sound_of(world, "hears") == 2, "sounds " .. #sound_of(world, "hears"))
        step("expiring")

    elseif phase == "expiring" and clock > 1.2 then
        sounding = { 1 }
        step("expired")

    elseif phase == "expired" and clock > 0.2 then
        local s = sound_of(world, "hears")
        suite.assert_test("P19_old_sounds_expire_and_the_list_closes_up", #s == 1 and s[1].at.x == 1001, "sounds " .. #s)
        suite.assert_test("P20_seen_and_sound_do_not_disturb_each_other", #seen_of(world, "sees") == 1, "")
        phase = "done"
        suite.finish("PerceptionSuite")
    end

    if phase ~= "done" and clock > 8 then
        suite.assert_test("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 8 s")
        phase = "done"
        suite.finish("PerceptionSuite")
    end
end):in_set("zz/perception_suite")
