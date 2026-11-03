-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AgentSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/name"] = { name = "agent" }, ["ai/agent"] = {} })
    commands:spawn({ ["zz/name"] = { name = "given" }, ["ai/agent"] = { think_hz = 20 } })
    commands:spawn({ ["zz/name"] = { name = "other" }, ["ai/agent"] = {} })
    for i = 1, 4 do
        commands:spawn({ ["zz/batch"] = {}, ["ai/agent"] = { think_hz = 1 } })
    end
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/agent", "ai/agent/memory", "ai/agent/tick", "ai/agent/options", "ai/agent/option", "ai/agent/chosen" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function option(commands, world, name, agent, score)
    commands:spawn({ ["zz/name"] = { name = name }, ["ai/agent/option"] = { entity = named(world, agent):id(), score = score } })
end

local function score(commands, world, name, value)
    commands:entity(named(world, name):id()):patch({ ["ai/agent/option"] = { score = value } })
end

local function chosen(world, name)
    local e = named(world, name)
    return e ~= nil and e:has("ai/agent/chosen")
end

-- Ticks of the two agents, counted from their edges.
local ticks = { agent = 0, given = 0 }
app:add_systems(Update, {
    Query[{
        changed = { "ai/agent/tick" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        local name = e:get("zz/name").name
        if ticks[name] then
            ticks[name] = ticks[name] + 1
        end
    end
end):in_set("zz/agent_suite_ticks")

-- Writes to `ai/agent/chosen`, to prove a choice that stays is not rewritten.
local chosen_writes = 0
app:add_systems(Update, {
    Query[{
        changed = { "ai/agent/chosen" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _ in ipairs(changed:iter()) do
        chosen_writes = chosen_writes + 1
    end
end):in_set("zz/agent_suite_chosen")

local phase, clock = "setup", 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local agent = named(world, "agent")

    if phase == "setup" and agent and agent:has("ai/agent/memory") and agent:has("ai/agent/tick") then
        local a = agent:get("ai/agent")
        local memory = agent:get("ai/agent/memory")
        local next_ats, same = {}, false
        for _, b in ipairs(world:query({ with = { "zz/batch", "ai/agent/tick" } })) do
            local at = b:get("ai/agent/tick").next_at
            same = same or next_ats[at] == true
            next_ats[at] = true
        end
        suite.assert_test("A19_a_batch_spawned_together_does_not_think_together", not same, "")
        suite.assert_test("A1_missing_fields_get_defaults", a.think_hz == 5 and math.abs(a.hysteresis - 0.15) < 1e-6, "")
        suite.assert_test("A2_it_has_a_memory_empty_of_what_it_saw_and_heard",
            next(memory.seen) == nil and next(memory.sound) == nil, "")
        step("ticking")

    elseif phase == "ticking" and clock > 2 then
        suite.assert_test("A3_it_thinks_at_its_rate", ticks.agent >= 8 and ticks.agent <= 12, "ticks " .. ticks.agent)
        suite.assert_test("A4_a_rate_given_stays", ticks.given >= 30 and ticks.given <= 42, "ticks " .. ticks.given)
        option(commands, world, "low", "agent", 0.2)
        option(commands, world, "high", "agent", 0.8)
        option(commands, world, "elsewhere", "other", 0.1)
        step("first choice")

    elseif phase == "first choice" and chosen(world, "high") then
        suite.assert_test("A5_the_highest_is_chosen", not chosen(world, "low"), "")
        suite.assert_test("A6_each_agent_chooses_for_itself", chosen(world, "elsewhere"), "")
        local options = agent:get("ai/agent/options")
        suite.assert_test("A7_the_engine_lists_an_agents_options", #options == 2, "options " .. #options)
        score(commands, world, "low", 0.85)
        step("close")

    elseif phase == "close" and clock > 0.2 then
        suite.assert_test("A8_a_little_more_does_not_take_over", chosen(world, "high") and not chosen(world, "low"), "")
        score(commands, world, "low", 0.95)
        step("over")

    elseif phase == "over" and chosen(world, "low") then
        suite.assert_test("A9_clearly_more_takes_over_and_the_last_loses_it", not chosen(world, "high"), "")
        step("taken over")

    elseif phase == "taken over" and clock > 0.2 then
        chosen_writes = 0
        score(commands, world, "high", 0.95)
        step("tied")

    elseif phase == "tied" and clock > 0.2 then
        suite.assert_test("A10_between_equals_the_chosen_stays", chosen(world, "low") and not chosen(world, "high"), "")
        suite.assert_test("A11_a_choice_that_stays_is_not_rewritten", chosen_writes == 0, "writes " .. chosen_writes)
        score(commands, world, "low", 0)
        step("dropped")

    elseif phase == "dropped" and chosen(world, "high") then
        suite.assert_test("A12_a_chosen_option_at_nothing_gives_way_to_any_above", not chosen(world, "low"), "")
        score(commands, world, "high", 0)
        step("none")

    elseif phase == "none" and not chosen(world, "high") and not chosen(world, "low") then
        suite.assert_test("A13_with_every_option_at_nothing_nothing_is_chosen", true, "")
        option(commands, world, "tie_b", "other", 0.5)
        score(commands, world, "elsewhere", 0)
        step("settled")

    elseif phase == "settled" and chosen(world, "tie_b") then
        option(commands, world, "tie_c", "other", 0.5)
        score(commands, world, "tie_b", 0.5)
        step("tie")

    elseif phase == "tie" and clock > 0.2 then
        suite.assert_test("A14_equal_newcomers_do_not_take_over", chosen(world, "tie_b") and not chosen(world, "tie_c"), "")
        commands:entity(named(world, "tie_b"):id()):despawn()
        step("chosen gone")

    elseif phase == "chosen gone" and chosen(world, "tie_c") then
        suite.assert_test("A15_a_chosen_option_going_hands_over_at_once", true, "")
        commands:entity(named(world, "other"):id()):despawn()
        step("agent gone")

    elseif phase == "agent gone" and named(world, "tie_c") == nil and named(world, "elsewhere") == nil then
        suite.assert_test("A16_an_agents_options_go_with_it", true, "")
        score(commands, world, "high", 0.5)
        step("rechosen")

    elseif phase == "rechosen" and chosen(world, "high") then
        commands:entity(named(world, "given"):id()):remove("ai/agent")
        commands:entity(agent:id()):remove("ai/agent")
        step("taken off")

    elseif phase == "taken off" and clock > 0.2 then
        local a = named(world, "agent")
        suite.assert_test("A17_taken_off_an_entity_that_stays_its_memory_and_clock_go",
            not a:has("ai/agent") and not a:has("ai/agent/memory") and not a:has("ai/agent/tick"), "")
        suite.assert_test("A18_and_nothing_is_chosen", not chosen(world, "high"), "")
        phase = "done"
        suite.finish("AgentSuite")
    end

    if phase ~= "done" and clock > 8 then
        suite.assert_test("A0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 8 s")
        phase = "done"
        suite.finish("AgentSuite")
    end
end):in_set("zz/agent_suite")
