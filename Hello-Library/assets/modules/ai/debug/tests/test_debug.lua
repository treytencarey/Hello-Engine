-- --host
-- What a real agent publishes as it thinks, chosen and all.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("DebugSuite")

local function agent(commands, name, slot, extra)
    local bundle = {
        ["zz/name"] = { name = name },
        ["ai/agent"] = { think_hz = 20 },
        ["ai/nav"] = {},
        ["ai/steering"] = {},
        ["ai/perception"] = { vision_range = 22, hearing_range = 30 },
        Transform = { translation = { x = slot * 200, y = 1, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        ["core/net/sync"] = false,
    }
    for k, v in pairs(extra) do
        bundle[k] = v
    end
    commands:spawn(bundle)
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 200, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 200 } },
    })
    -- Two regions that touch, so its path turns where they meet.
    commands:spawn({ ["ai/nav/region"] = { min_x = -5, max_x = 5, min_z = -5, max_z = 5, y = 0 }, ["core/net/sync"] = false })
    commands:spawn({ ["ai/nav/region"] = { min_x = -5, max_x = 5, min_z = 5, max_z = 20, y = 0 }, ["core/net/sync"] = false })
    agent(commands, "drawn", 0, { ["ai/debug"] = {}, ["ai/behavior/chase"] = { speed = 3, give_up_for = 0 } })
    commands:spawn({
        ["ai/perception/target"] = {},
        Transform = { translation = { x = 0, y = 1, z = 12 } },
        ["core/net/sync"] = false,
    })
    agent(commands, "left alone", 1, { ["ai/behavior/chase"] = {} })
    agent(commands, "idle", 2, { ["ai/debug"] = {} })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/debug", "ai/agent/memory", "ai/nav/path", "ai/steering/state", "core/net/sync" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

-- Writes to each agent's `ai/debug`, to prove it publishes at each thought and no faster.
local writes = 0
app:add_systems(Update, {
    Query[{
        changed = { "ai/debug" },
        with = { "zz/name" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        if e:get("zz/name").name == "idle" then
            writes = writes + 1
        end
    end
end):in_set("zz/debug_suite_writes")

local phase, clock, sounded = "thinking", 0, false

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "thinking" and clock > 0.5 and not sounded then
        sounded = true
        commands:trigger("ai/noisemaker/sound", { entity = named(world, "drawn"):id(), x = 3, y = 1, z = 3, loudness = 1, kind = "footstep" })

    elseif phase == "thinking" and clock > 1 then
        local d = named(world, "drawn"):get("ai/debug")
        suite.assert_test("DB1_it_names_what_is_chosen_from_its_name", d.chosen == "chase", "chosen " .. tostring(d.chosen))
        suite.assert_test("DB2_its_ranges", d.vision_range == 22 and d.hearing_range == 30 and d.vision_fov_deg == 100 and d.awareness_range == 3, "")
        suite.assert_test("DB3_where_it_saw_something", #d.seen == 1 and d.seen[1].z == 12 and d.seen[1].entity == nil and d.seen[1].seen_at == nil, "")
        suite.assert_test("DB4_where_it_heard_something", #d.sound == 1 and d.sound[1].x == 3, "")
        local path = named(world, "drawn"):get("ai/nav/path")
        suite.assert_test("DB5_the_path_it_has_left", path ~= nil and #d.path > 0 and d.path[#d.path].z == path.path[#path.path].z, "")
        local idle = named(world, "idle"):get("ai/debug")
        suite.assert_test("DB6_nothing_chosen_says_nothing", idle.chosen == nil and #idle.path == 0 and #idle.seen == 0, "")
        suite.assert_test("DB7_an_agent_without_it_publishes_nothing", not named(world, "left alone"):has("ai/debug"), "")
        writes = 0
        step("counting")

    elseif phase == "walked on" and clock > 8 then
        suite.assert_test("DB10_reached_a_later_waypoint", false, "")
        phase = "done"
        suite.finish("DebugSuite")

    elseif phase == "walked on" and (named(world, "drawn"):get("ai/steering/state") or {}).cursor ~= nil
        and named(world, "drawn"):get("ai/steering/state").cursor > 1 and clock > 0.2 then
        local e = named(world, "drawn")
        local path = e:get("ai/nav/path")
        local d = e:get("ai/debug")
        suite.assert_test("DB10_what_it_has_walked_is_not_drawn", #d.path < #path.path, #d.path .. " of " .. #path.path)
        phase = "done"
        suite.finish("DebugSuite")

    elseif phase == "counting" and clock > 1 then
        suite.assert_test("DB9_it_publishes_at_each_thought", writes >= 14 and writes <= 26, "writes " .. writes)
        step("walked on")
    end

    if phase ~= "done" and clock > 8 then
        suite.assert_test("DB0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 8 s")
        phase = "done"
        suite.finish("DebugSuite")
    end
end):in_set("zz/debug_suite")
