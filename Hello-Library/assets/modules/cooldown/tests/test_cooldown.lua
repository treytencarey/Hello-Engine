-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("CooldownSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

-- The suite's own marker: a `cooldown/<x>` name is a part of the mod, removed with `cooldown`.
local function subject(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/cooldown_subject" },
        optional = {
            "cooldown",
            "cooldown/left",
            "cooldown/test_a",
            "cooldown/test_b",
            "cooldown/test_c",
            "cooldown/test_d",
            "cooldown/test_e",
        },
    })) do
        if e:get("zz/cooldown_subject").name == name then
            return e
        end
    end
end

-- A consumer listening for a timer to end, as a portal or an ability would.
local ended = {}
app:add_systems(Update, { World }, function(world)
    for _, e in ipairs(world:query({
        ["or"] = { removed = { "cooldown/test_a", "cooldown/test_e" } },
        optional = { "cooldown/test_a", "cooldown/test_e", "zz/cooldown_subject" },
    })) do
        ended[#ended + 1] = tostring((e:get("zz/cooldown_subject") or {}).name)
    end
end):in_set("zz/cooldown_suite_ended")

-- Counts how often the shared component of "short" is written.
local writes = 0
app:add_systems(Update, { World }, function(world)
    for _, e in ipairs(world:query({
        changed = { "cooldown" },
        with = { "zz/cooldown_subject" },
    })) do
        if e:get("zz/cooldown_subject").name == "short" then
            writes = writes + 1
        end
    end
end):in_set("zz/cooldown_suite_writes")

local phase, clock = "spawn", 0

-- The suite's clock is the mod's: Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local short, long = subject(world, "short"), subject(world, "long")
    local function step(next_phase)
        phase, clock = next_phase, 0
    end

    if phase == "spawn" then
        commands:spawn({
            ["zz/cooldown_subject"] = { name = "short" },
            cooldown = {
                ["cooldown/test_a"] = { remaining = 0.3 },
                ["cooldown/test_b"] = { remaining = 30 },
            },
            ["core/net/sync"] = false,
        })
        commands:spawn({
            ["zz/cooldown_subject"] = { name = "doomed" },
            cooldown = {
                ["cooldown/test_e"] = { remaining = 0.5 },
            },
            ["core/net/sync"] = false,
        })
        commands:spawn({
            ["zz/cooldown_subject"] = { name = "long" },
            cooldown = {
                ["cooldown/test_c"] = { remaining = 30 },
            },
            ["core/net/sync"] = false,
        })
        step("started")

    elseif phase == "started" and short and long and short:get("cooldown/left") and long:get("cooldown/left") then
        local doomed = subject(world, "doomed")
        if doomed then
            commands:entity(doomed:id()):despawn()
        end
        suite.assert_test("C1_a_running_timer_carries_its_component",
            short:has("cooldown/test_a") and short:has("cooldown/test_b") and long:has("cooldown/test_c"),
            string.format("a=%s b=%s c=%s", tostring(short:has("cooldown/test_a")),
                tostring(short:has("cooldown/test_b")), tostring(long:has("cooldown/test_c"))))
        step("running")

    elseif phase == "running" and not short:has("cooldown/test_a") then
        suite.assert_test("C2_a_timer_ends_on_time_and_takes_its_component", clock > 0.2 and clock < 1.5
            and (short:get("cooldown") or {})["cooldown/test_a"] == nil, string.format("ended after %.2f s", clock))
        suite.assert_test("C3_the_other_timer_keeps_running", short:has("cooldown/test_b"), "b is gone")
        suite.assert_test("C4_shared_component_written_only_at_start_and_end", writes <= 3,
            "cooldown was written " .. writes .. " times")
        short:patch({ cooldown = { ["cooldown/test_d"] = { remaining = 0.2 } } })
        step("second start")

    elseif phase == "second start" and short:has("cooldown/test_d") then
        step("second running")

    elseif phase == "second running" and not short:has("cooldown/test_d") then
        suite.assert_test("C5_starting_while_another_runs_still_ends", clock > 0.1 and clock < 1.5,
            string.format("d ended after %.2f s", clock))
        suite.assert_test("C6_the_running_timer_survives_a_new_start", ((short:get("cooldown/left") or {})["cooldown/test_b"] or 0) > 20,
            "b left: " .. tostring((short:get("cooldown/left") or {})["cooldown/test_b"]))
        short:patch({ cooldown = { ["cooldown/test_b"] = null } })
        commands:entity(long:id()):remove("cooldown")
        step("cancelled")

    elseif phase == "cancelled" and not short:has("cooldown/test_b") and not long:has("cooldown/test_c")
        and not short:has("cooldown/left") and not long:has("cooldown/left") then
        suite.assert_test("C7_cancelling_an_entry_removes_its_component", true, "")
        suite.assert_test("C8_removing_cooldown_removes_every_component", true, "")
        print("[CD] removed-edge rows seen by the consumer: " .. table.concat(ended, ","))
        phase = "done"
        suite.finish("CooldownSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("CooldownSuite")
    end
end):in_set("zz/cooldown_suite")
