-- --host
-- The three behaviours on real agents with real bodies: what each scores from what the agent knows,
-- what it asks `ai/nav` for while chosen, and that it lets go. Each agent has its own stretch of
-- ground, 200 m apart, so nothing it does reaches another.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("BehaviorsSuite")

local function agent(commands, name, slot, behaviours)
    local bundle = {
        ["zz/name"] = { name = name, x = slot * 200 },
        ["ai/agent"] = { think_hz = 20 },
        ["ai/nav"] = {},
        ["ai/steering"] = {},
        ["ai/perception"] = {},
        Transform = { translation = { x = slot * 200, y = 1, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
    }
    for k, v in pairs(behaviours) do
        bundle[k] = v
    end
    commands:spawn(bundle)
end

local function target(commands, name, slot, x, z)
    commands:spawn({
        ["zz/target"] = { name = name },
        ["ai/perception/target"] = {},
        Transform = { translation = { x = slot * 200 + x, y = 1, z = z } },
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 1500, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 3000, hy = 0.5, hz = 200 } },
    })

    -- chases what is ahead, and has a second target for later
    agent(commands, "chaser", 0, { ["ai/behavior/chase"] = { speed = 3 } })
    target(commands, "prey", 0, 0, 12)
    -- two targets, the nearer picked
    agent(commands, "picker", 1, { ["ai/behavior/chase"] = {} })
    target(commands, "near", 1, 0, 5)
    target(commands, "far", 1, 0, 15)
    -- the one it picked stays unless another is clearly better
    -- standing where it is, so only its choice of target changes
    agent(commands, "loyal", 2, {
        ["ai/behavior/chase"] = { speed = 0, distance_weight = 0.02, switch_margin = 0.5 },
        ["ai/steering"] = { stall_timeout = 1000 },
    })
    target(commands, "first", 2, 0, 10)
    agent(commands, "fickle", 3, {
        ["ai/behavior/chase"] = { speed = 0, distance_weight = 0.02, switch_margin = 0.05 },
        ["ai/steering"] = { stall_timeout = 1000 },
    })
    target(commands, "fickle first", 3, 0, 10)
    -- over a kerb it can see across and not climb: no way there
    agent(commands, "blocked", 4, { ["ai/behavior/chase"] = { speed = 3, give_up_for = 100 } })
    target(commands, "beyond", 4, 0, 6)
    commands:spawn({
        Transform = { translation = { x = 800, y = 0.4, z = 3 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 100, hy = 0.4, hz = 0.5 } },
    })
    -- taken off an agent that stays
    agent(commands, "dropped", 5, { ["ai/behavior/chase"] = {} })
    target(commands, "dropped prey", 5, 0, 5)

    -- hears, walks there, looks, and is done with it
    agent(commands, "listener", 6, { ["ai/behavior/investigate"] = { speed = 4, look_time = 0.4 } })
    -- picks between two sounds
    agent(commands, "torn", 7, { ["ai/behavior/investigate"] = { speed = 0 }, ["ai/steering"] = { stall_timeout = 1000 } })
    -- no way there
    agent(commands, "kerbed", 8, { ["ai/behavior/investigate"] = { speed = 3 } })
    commands:spawn({
        Transform = { translation = { x = 1600, y = 0.4, z = 3 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 100, hy = 0.4, hz = 0.5 } },
    })
    -- taken off
    agent(commands, "dropped listener", 9, { ["ai/behavior/investigate"] = {} })

    -- wanders, with nothing else to do
    agent(commands, "wanderer", 10, { ["ai/behavior/patrol"] = { speed = 4, radius = 6, pause_min = 0.2, pause_max = 0.3 } })
    agent(commands, "dropped wanderer", 11, { ["ai/behavior/patrol"] = {} })

    -- all three on one agent
    agent(commands, "whole", 12, {
        ["ai/behavior/chase"] = { speed = 4, fresh_for = 1 },
        ["ai/behavior/investigate"] = { speed = 4, look_time = 0.2 },
        ["ai/behavior/patrol"] = { speed = 2, radius = 4, pause_min = 0.2, pause_max = 0.3 },
    })

    -- no way there, and it tries again
    agent(commands, "retries", 13, { ["ai/behavior/chase"] = { speed = 3, give_up_for = 0.5 } })
    target(commands, "retry prey", 13, 0, 6)
    commands:spawn({
        Transform = { translation = { x = 2600, y = 0.4, z = 3 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 100, hy = 0.4, hz = 0.5 } },
    })
    -- walled in, so no leg gets anywhere
    agent(commands, "penned", 14, {
        ["ai/behavior/patrol"] = { speed = 3, radius = 6, pause_min = 0.1, pause_max = 0.2 },
        ["ai/steering"] = { stall_timeout = 0.3 },
    })
    for _, side in ipairs({ { 2, 0, 0.3, 2.3 }, { -2, 0, 0.3, 2.3 }, { 0, 2, 2.3, 0.3 }, { 0, -2, 2.3, 0.3 } }) do
        commands:spawn({
            Transform = { translation = { x = 2800 + side[1], y = 0.4, z = side[2] } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = side[3], hy = 0.4, hz = side[4] } },
        })
    end
    -- its behaviours arrive before it is an agent
    commands:spawn({
        ["zz/name"] = { name = "late", x = 3000 },
        ["ai/behavior/chase"] = {},
        ["ai/behavior/investigate"] = {},
        ["ai/behavior/patrol"] = {},
        Transform = { translation = { x = 3000, y = 1, z = 0 } },
    })
    -- a sound it never gets to go stale
    agent(commands, "forgetful", 16, {
        ["ai/behavior/investigate"] = { speed = 0, fresh_for = 0.3 },
        ["ai/steering"] = { stall_timeout = 1000 },
    })
    -- a new sound while it looks at the last
    -- It thinks every frame, as what steering says about the last path can last a frame or two.
    agent(commands, "turned", 17, {
        ["ai/agent"] = { think_hz = 500 },
        ["ai/behavior/investigate"] = { speed = 4, look_time = 3, distance_weight = 0, switch_margin = 0 },
    })
    -- a newer sound further off, over an older one nearer
    agent(commands, "fresher", 18, {
        ["ai/behavior/investigate"] = { speed = 0, fresh_for = 4, switch_margin = 0.05 },
        ["ai/steering"] = { stall_timeout = 1000 },
    })
    agent(commands, "stubborn", 19, {
        ["ai/behavior/investigate"] = { speed = 0, fresh_for = 4, switch_margin = 0.5 },
        ["ai/steering"] = { stall_timeout = 1000 },
    })
    -- a newer sighting further off, over an older one nearer
    agent(commands, "fresh eyes", 20, {
        ["ai/behavior/chase"] = { speed = 0, switch_margin = 0.1 },
        ["ai/steering"] = { stall_timeout = 1000 },
    })
    target(commands, "old near", 20, 0, 5)
end)

-- Sounds to make, each for the agent named: the event as `ai/noisemaker` triggers it.
local to_sound = {}
app:add_systems(Update, { Commands, Query[{ with = { "zz/name" } }] }, function(commands, agents)
    for _, want in ipairs(to_sound) do
        for _, e in ipairs(agents:iter()) do
            local n = e:get("zz/name")
            if n.name == want.name then
                commands:trigger("ai/noisemaker/sound", { entity = e:id(), x = n.x + want.x, y = 1, z = want.z, loudness = 1, kind = "footstep" })
            end
        end
    end
    to_sound = {}
end):in_set("zz/behaviors_suite_sounds")

-- How far a wanderer has been from home, how many legs it has asked for, whether it finished each
-- before asking for the next, and how long it stood between them.
local wander = { reach = 0, legs = 0, last = nil, short = 0, least_pause = 1000, arrived_at = nil }
local penned_legs, penned_last = 0, nil
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "zz/name", "ai/behavior/patrol", "ai/nav/request", "Transform" },
        optional = { "ai/steering/state" },
    }],
}, function(time, agents)
    local now = time:elapsed_secs()
    for _, e in ipairs(agents:iter()) do
        local n = e:get("zz/name")
        local asked = e:get("ai/nav/request").patrol
        if n.name == "wanderer" then
            local at = e:get("Transform").translation
            wander.reach = math.max(wander.reach, math.sqrt((at.x - n.x) ^ 2 + at.z ^ 2))
            local steer = e:get("ai/steering/state")
            if steer ~= nil and steer.status == "arrived" then
                wander.arrived_at = wander.arrived_at or now
            end
            if asked ~= nil and (wander.last == nil or wander.last.x ~= asked.to.x) then
                if wander.last ~= nil then
                    if math.sqrt((at.x - wander.last.x) ^ 2 + (at.z - wander.last.z) ^ 2) > 2 then
                        wander.short = wander.short + 1
                    end
                    wander.least_pause = math.min(wander.least_pause, now - (wander.arrived_at or now))
                end
                wander.last = asked.to
                wander.arrived_at = nil
                wander.legs = wander.legs + 1
            end
        elseif n.name == "penned" and asked ~= nil and (penned_last == nil or penned_last ~= asked.to.x) then
            penned_last = asked.to.x
            penned_legs = penned_legs + 1
        end
    end
end):in_set("zz/behaviors_suite_wander")

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/agent/options", "ai/nav/request", "ai/nav/path", "ai/steering", "ai/steering/state", "Transform", "ai/agent/memory" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function target_of(world, name)
    for _, e in ipairs(world:query({ with = { "zz/target" }, optional = { "Transform" } })) do
        if e:get("zz/target").name == name then
            return e
        end
    end
end

local function option_of(world, name, marker)
    local a = named(world, name)
    for _, o in ipairs(world:query({
        iter_many = a and a:get("ai/agent/options") or {},
        with = { marker, "ai/agent/option" },
        optional = { "ai/agent/chosen", "ai/behavior/chase/state", "ai/behavior/investigate/state", "Name" },
    })) do
        return o
    end
end

local function chosen(world, name, marker)
    local o = option_of(world, name, marker)
    return o ~= nil and o:has("ai/agent/chosen")
end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 0.01) end

local function distance_to(world, name, what)
    local a = world:get_entity(named(world, name):id()).GlobalTransform:compute_transform().translation
    local t = target_of(world, what):get("Transform").translation
    return math.sqrt((a.x - t.x) ^ 2 + (a.z - t.z) ^ 2)
end

local phase, clock = "first", 0
local option_gone = nil
local look_started, retry_gave_up = 0, nil

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local CHASE, LISTEN, WANDER = "ai/behavior/chase/option", "ai/behavior/investigate/option", "ai/behavior/patrol/option"

    if phase == "first" and chosen(world, "chaser", CHASE) then
        local o = option_of(world, "chaser", CHASE)
        suite.assert_test("C1_it_keeps_one_option_linked_to_the_agent", #named(world, "chaser"):get("ai/agent/options") == 1,
            "options " .. #named(world, "chaser"):get("ai/agent/options"))
        suite.assert_test("C2_its_option_has_a_name_for_the_overlay_and_no_other_name", tostring(o:get("Name").name):find("chase", 1, true) ~= nil
            and o:get("ai/agent/option").name == nil, "")
        suite.assert_test("C3_a_fresh_sighting_scores_high", o:get("ai/agent/option").score > 0.9, tostring(o:get("ai/agent/option").score))
        step("asked")

    elseif phase == "asked" and named(world, "chaser"):has("ai/nav/path")
        and option_of(world, "picker", CHASE) ~= nil and option_of(world, "picker", CHASE):has("ai/behavior/chase/state") then
        local request = named(world, "chaser"):get("ai/nav/request")
        suite.assert_test("C4_chosen_it_asks_for_the_way_under_its_own_key", request.chase ~= nil and request.chase.to.z == 12, "")
        suite.assert_test("C5_at_its_own_speed", named(world, "chaser"):get("ai/steering").speed == 3, "")
        local picked = option_of(world, "picker", CHASE):get("ai/behavior/chase/state").target
        suite.assert_test("C6_of_two_it_picks_the_nearer", picked == target_of(world, "near"):id(), "")
        step("caught up")

    elseif phase == "caught up" and distance_to(world, "chaser", "prey") < 1.5 then
        suite.assert_test("C7_a_real_body_walks_to_its_target", true, "")
        commands:entity(target_of(world, "prey"):id()):patch({ Transform = { translation = { z = 24 } } })
        target(commands, "better", 2, 0, 1)
        target(commands, "fickle better", 3, 0, 1)
        step("moved")

    elseif phase == "moved" and clock > 0.5 then
        local request = named(world, "chaser"):get("ai/nav/request")
        suite.assert_test("C8_a_target_that_moves_far_enough_is_asked_for_again", request.chase ~= nil and request.chase.to.z == 24,
            tostring(request.chase and request.chase.to.z))
        suite.assert_test("C9_it_keeps_its_target_unless_another_is_clearly_better",
            option_of(world, "loyal", CHASE):get("ai/behavior/chase/state").target == target_of(world, "first"):id(), "")
        suite.assert_test("C10_and_changes_when_one_is",
            option_of(world, "fickle", CHASE):get("ai/behavior/chase/state").target == target_of(world, "fickle better"):id(), "")
        commands:entity(target_of(world, "prey"):id()):patch({ Transform = { translation = { z = 25 } } })
        step("nudged")

    elseif phase == "nudged" and clock > 0.3 then
        local request = named(world, "chaser"):get("ai/nav/request")
        suite.assert_test("C8b_a_target_that_moves_a_little_is_not", request.chase ~= nil and request.chase.to.z == 24,
            tostring(request.chase and request.chase.to.z))
        step("walled")

    elseif phase == "walled" and option_of(world, "blocked", CHASE):get("ai/behavior/chase/state").gave_up_until ~= nil then
        step("gives up")

    elseif phase == "gives up" and clock > 0.3 then
        suite.assert_test("C11_with_no_way_there_it_gives_up_and_scores_nothing",
            option_of(world, "blocked", CHASE):get("ai/agent/option").score == 0 and not chosen(world, "blocked", CHASE), "")
        suite.assert_test("C12_and_stops_asking", named(world, "blocked"):get("ai/nav/request").chase == nil, "")
        commands:entity(target_of(world, "dropped prey"):id()):remove("ai/perception/target")
        commands:entity(target_of(world, "better"):id()):remove("ai/perception/target")
        commands:entity(target_of(world, "first"):id()):remove("ai/perception/target")
        step("stale")

    elseif phase == "stale" and not chosen(world, "loyal", CHASE) then
        suite.assert_test("C13b_as_soon_as_it_has_gone_stale_not_when_it_is_forgotten", clock < 5, "after " .. clock)
        step("stale settled")

    elseif phase == "stale settled" and clock > 0.2 then
        suite.assert_test("C13_what_it_saw_going_stale_lets_it_go", option_of(world, "loyal", CHASE):get("ai/agent/option").score == 0,
            tostring(option_of(world, "loyal", CHASE):get("ai/agent/option").score))
        suite.assert_test("C14_no_longer_chosen_it_stops_asking", named(world, "loyal"):get("ai/nav/request").chase == nil, "")
        suite.assert_test("C15_and_with_no_path_steering_stands_it_still", not named(world, "loyal"):has("ai/nav/path"), "")
        local option_id = option_of(world, "picker", CHASE):id()
        commands:entity(named(world, "picker"):id()):remove("ai/behavior/chase")
        step("taken off")
        option_gone = option_id

    elseif phase == "taken off" and clock > 0.3 then
        suite.assert_test("C16_taken_off_an_agent_that_stays_its_option_and_key_go",
            world:get_entity(option_gone) == nil and named(world, "picker"):get("ai/nav/request").chase == nil, "")
        to_sound = {
            { name = "listener", x = 0, z = 8 },
            { name = "torn", x = 0, z = 20 },
            { name = "torn", x = 0, z = 4 },
            { name = "kerbed", x = 0, z = 6 },
            { name = "dropped listener", x = 0, z = 5 },
        }
        step("heard")

    elseif phase == "heard" and chosen(world, "listener", LISTEN) and named(world, "listener"):has("ai/nav/path")
        and option_of(world, "torn", LISTEN) ~= nil and option_of(world, "torn", LISTEN):has("ai/behavior/investigate/state") then
        local request = named(world, "listener"):get("ai/nav/request")
        suite.assert_test("I1_a_sound_scores_and_it_asks_the_way_there", request.investigate ~= nil and request.investigate.to.z == 8, "")
        local o = option_of(world, "listener", LISTEN)
        suite.assert_test("I2_a_fresh_sound_scores_between_patrol_and_chase",
            o:get("ai/agent/option").score > 0.5 and o:get("ai/agent/option").score <= 0.8, tostring(o:get("ai/agent/option").score))
        suite.assert_test("I3_of_two_sounds_it_picks_the_nearer", option_of(world, "torn", LISTEN):get("ai/behavior/investigate/state").at.z == 4, "")
        suite.assert_test("I4_at_its_own_speed", named(world, "listener"):get("ai/steering").speed == 4, "")
        step("walking there")

    elseif phase == "walking there" and option_of(world, "listener", LISTEN):has("ai/behavior/investigate/state")
        and option_of(world, "listener", LISTEN):get("ai/behavior/investigate/state").look_until ~= nil then
        local at = named(world, "listener"):get("Transform").translation
        suite.assert_test("I5_a_real_body_walks_there_and_looks", math.abs(at.z - 8) < 1.2, "z " .. at.z)
        look_started = time:elapsed_secs()
        suite.assert_test("I6_it_is_still_chosen_while_it_looks", chosen(world, "listener", LISTEN), "")
        step("looked")

    elseif phase == "looked" and not chosen(world, "listener", LISTEN) then
        local looked = time:elapsed_secs() - look_started
        suite.assert_test("I6b_it_looks_for_its_look_time_and_no_longer", looked >= 0.3 and looked < 1.5, "looked " .. looked)
        step("looked settled")

    elseif phase == "looked settled" and clock > 0.2 then
        suite.assert_test("I7_having_looked_it_is_done_with_the_sound_though_it_is_still_in_memory",
            option_of(world, "listener", LISTEN):get("ai/agent/option").score == 0 and #named(world, "listener"):get("ai/agent/memory").sound == 1, "")
        suite.assert_test("I8_and_stops_asking", named(world, "listener"):get("ai/nav/request").investigate == nil, "")
        to_sound = { { name = "listener", x = 0, z = -8 } }
        step("heard again")

    elseif phase == "heard again" and chosen(world, "listener", LISTEN) then
        suite.assert_test("I9_a_newer_sound_is_news", true, "")
        step("kerb")

    elseif phase == "kerb" and option_of(world, "kerbed", LISTEN):get("ai/agent/option").score == 0 then
        suite.assert_test("I10_with_no_way_there_it_is_done_with_the_sound",
            option_of(world, "kerbed", LISTEN):get("ai/behavior/investigate/state").done_at ~= nil, "")
        local option_id = option_of(world, "dropped listener", LISTEN):id()
        commands:entity(named(world, "dropped listener"):id()):remove("ai/behavior/investigate")
        option_gone = option_id
        step("listener off")

    elseif phase == "listener off" and clock > 0.3 then
        suite.assert_test("I11_taken_off_its_option_and_key_go",
            world:get_entity(option_gone) == nil and named(world, "dropped listener"):get("ai/nav/request").investigate == nil, "")
        step("wandering")

    elseif phase == "wandering" and wander.legs >= 3 then
        suite.assert_test("W1_with_nothing_else_it_wanders_leg_after_leg", chosen(world, "wanderer", WANDER), "")
        suite.assert_test("W2_a_real_body_walks_out_from_home_within_its_radius", wander.reach > 1.5 and wander.reach < 7.5, "reach " .. wander.reach)
        suite.assert_test("W2b_it_finishes_each_leg_before_the_next", wander.short == 0, "short " .. wander.short)
        suite.assert_test("W2c_it_stands_between_them", wander.least_pause >= 0.15, "least " .. wander.least_pause)
        suite.assert_test("W2d_a_leg_with_no_way_there_is_picked_again", penned_legs >= 3, "legs " .. penned_legs)
        suite.assert_test("W3_its_score_is_flat_and_low", near(option_of(world, "wanderer", WANDER):get("ai/agent/option").score, 0.2), "")
        suite.assert_test("W4_at_its_own_speed", named(world, "wanderer"):get("ai/steering").speed == 4, "")
        commands:entity(named(world, "wanderer"):id()):patch({ ["ai/behavior/patrol"] = { base_score = 0.3 } })
        local option_id = option_of(world, "dropped wanderer", WANDER):id()
        commands:entity(named(world, "dropped wanderer"):id()):remove("ai/behavior/patrol")
        option_gone = option_id
        step("wanderer off")

    elseif phase == "wanderer off" and clock > 0.3 then
        suite.assert_test("W5_a_changed_score_applies", near(option_of(world, "wanderer", WANDER):get("ai/agent/option").score, 0.3), "")
        suite.assert_test("W6_taken_off_its_option_and_key_go",
            world:get_entity(option_gone) == nil and named(world, "dropped wanderer"):get("ai/nav/request").patrol == nil, "")
        step("whole")

    elseif phase == "whole" and chosen(world, "whole", WANDER) then
        local options = named(world, "whole"):get("ai/agent/options")
        suite.assert_test("X1_three_behaviours_three_options", #options == 3, "options " .. #options)
        suite.assert_test("X2_only_one_key_while_it_wanders", named(world, "whole"):get("ai/nav/request").chase == nil
            and named(world, "whole"):get("ai/nav/request").investigate == nil, "")
        to_sound = { { name = "whole", x = 0, z = 6 } }
        step("whole hears")

    elseif phase == "whole hears" and chosen(world, "whole", LISTEN) then
        suite.assert_test("X3_a_sound_outbids_wandering", not chosen(world, "whole", WANDER), "")
        step("whole hears settled")

    elseif phase == "whole hears settled" and clock > 0.2 then
        local request = named(world, "whole"):get("ai/nav/request")
        suite.assert_test("X4_the_old_key_goes_and_the_new_one_stays", request.patrol == nil and request.investigate ~= nil, "")
        target(commands, "whole prey", 12, 0, 12)
        step("whole sees")

    elseif phase == "whole sees" and chosen(world, "whole", CHASE) then
        suite.assert_test("X5_something_seen_outbids_a_sound", not chosen(world, "whole", LISTEN), "")
        commands:entity(target_of(world, "whole prey"):id()):remove("ai/perception/target")
        step("whole loses it")

    elseif phase == "whole loses it" and not chosen(world, "whole", CHASE) then
        suite.assert_test("X6_losing_sight_falls_back_with_no_transition_written_anywhere", true, "")
        step("whole back")

    elseif phase == "whole back" and chosen(world, "whole", WANDER) then
        suite.assert_test("X7_and_in_the_end_it_wanders_again", true, "")
        commands:entity(named(world, "late"):id()):patch({ ["ai/agent"] = {} })
        commands:entity(target_of(world, "old near"):id()):remove("ai/perception/target")
        retry_gave_up = option_of(world, "retries", CHASE):get("ai/behavior/chase/state").gave_up_until
        to_sound = {
            { name = "forgetful", x = 0, z = 4 },
            { name = "fresher", x = 0, z = 4 },
            { name = "stubborn", x = 0, z = 4 },
            { name = "turned", x = 0, z = 8 },
        }
        step("late")

    elseif phase == "late" and clock > 0.3 then
        suite.assert_test("X8_an_agent_that_comes_later_gets_its_options", #(named(world, "late"):get("ai/agent/options") or {}) == 3, "")
        suite.assert_test("X9_each_named_for_the_overlay",
            tostring(option_of(world, "late", CHASE):get("Name").name):find("chase", 1, true) ~= nil
                and tostring(option_of(world, "late", LISTEN):get("Name").name):find("investigate", 1, true) ~= nil
                and tostring(option_of(world, "late", WANDER):get("Name").name):find("patrol", 1, true) ~= nil, "")
        step("first sounds")

    elseif phase == "first sounds" and clock > 1.2 then
        local o = option_of(world, "forgetful", LISTEN)
        suite.assert_test("I12_a_sound_too_old_scores_nothing", o:get("ai/agent/option").score == 0, tostring(o:get("ai/agent/option").score))
        suite.assert_test("I13_and_is_let_go", (o:get("ai/behavior/investigate/state") or {}).at == nil, "")
        to_sound = {
            { name = "fresher", x = 0, z = 10 },
            { name = "stubborn", x = 0, z = 10 },
        }
        target(commands, "fresh far", 20, 0, 8)
        step("second sounds")

    elseif phase == "second sounds" and clock > 0.5 then
        suite.assert_test("I14_a_newer_sound_further_off_can_be_better",
            option_of(world, "fresher", LISTEN):get("ai/behavior/investigate/state").at.z == 10, "")
        suite.assert_test("I15_and_it_asks_for_the_way_there", named(world, "fresher"):get("ai/nav/request").investigate.to.z == 10, "")
        suite.assert_test("I16_it_keeps_its_sound_unless_another_is_clearly_better",
            option_of(world, "stubborn", LISTEN):get("ai/behavior/investigate/state").at.z == 4, "")
        suite.assert_test("C18_a_newer_sighting_further_off_can_be_better",
            option_of(world, "fresh eyes", CHASE):get("ai/behavior/chase/state").target == target_of(world, "fresh far"):id(), "")
        step("turning")

    elseif phase == "turning" and option_of(world, "turned", LISTEN):get("ai/behavior/investigate/state").look_until ~= nil then
        to_sound = { { name = "turned", x = 0, z = -8 } }
        step("turned")

    elseif phase == "turned" and option_of(world, "turned", LISTEN):get("ai/behavior/investigate/state").at ~= nil
        and option_of(world, "turned", LISTEN):get("ai/behavior/investigate/state").at.z == -8
        and option_of(world, "turned", LISTEN):get("ai/behavior/investigate/state").look_until ~= nil then
        local z = named(world, "turned"):get("Transform").translation.z
        suite.assert_test("I17_a_new_sound_while_it_looks_is_walked_to_first", math.abs(z + 8) < 1.5, "z " .. z)
        suite.assert_test("C17_having_given_up_it_tries_again_in_time",
            option_of(world, "retries", CHASE):get("ai/behavior/chase/state").gave_up_until ~= retry_gave_up, "")
        phase = "done"
        suite.finish("BehaviorsSuite")
    end

    if phase ~= "done" and clock > 25 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 25 s")
        phase = "done"
        suite.finish("BehaviorsSuite")
    end
end):in_set("zz/behaviors_suite")
