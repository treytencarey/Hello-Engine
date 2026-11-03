-- --host
-- Each behaviour when `ai/nav` answers that there is no way: each agent stands on a small region,
-- with what it wants on regions around it that nothing joins. A region anywhere means every agent
-- is routed, which is why this is apart from the other behaviours' suite.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("BehaviorsNoWaySuite")

local function region(commands, x, min_x, max_x, min_z, max_z)
    commands:spawn({
        ["ai/nav/region"] = { min_x = x + min_x, max_x = x + max_x, min_z = min_z, max_z = max_z, y = 0 },
        ["core/net/sync"] = false,
    })
end

local function place(commands, name, slot, behaviours)
    local x = slot * 200
    local bundle = {
        ["zz/name"] = { name = name, x = x },
        ["ai/agent"] = { think_hz = 20 },
        ["ai/nav"] = {},
        ["ai/steering"] = {},
        ["ai/perception"] = {},
        Transform = { translation = { x = x, y = 1, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
    }
    for k, v in pairs(behaviours) do
        bundle[k] = v
    end
    commands:spawn(bundle)
    region(commands, x, -2, 2, -2, 2)
    region(commands, x, -14, 14, 10, 14)
    region(commands, x, -14, 14, -14, -10)
    region(commands, x, 10, 14, -10, 10)
    region(commands, x, -14, -10, -10, 10)
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 200, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 200 } },
    })
    place(commands, "chaser", 0, { ["ai/behavior/chase"] = { give_up_for = 100 } })
    commands:spawn({ ["ai/perception/target"] = {}, Transform = { translation = { x = 0, y = 1, z = 12 } } })
    place(commands, "listener", 1, { ["ai/behavior/investigate"] = {} })
    place(commands, "wanderer", 2, { ["ai/behavior/patrol"] = { radius = 12, near_share = 1, pause_min = 0.1, pause_max = 0.2 } })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/agent/options", "ai/nav/request", "ai/nav/path" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function state_of(world, name, marker, state)
    local list = world:query({
        iter_many = named(world, name):get("ai/agent/options") or {},
        with = { marker },
        optional = { state },
    })
    return list[1] and list[1]:get(state)
end

local legs, last, saw_unreachable = 0, nil, false
app:add_systems(Update, {
    Query[{ with = { "zz/name", "ai/nav/request" }, optional = { "ai/nav/path" } }],
}, function(agents)
    for _, e in ipairs(agents:iter()) do
        if e:get("zz/name").name == "wanderer" then
            local asked = e:get("ai/nav/request").patrol
            if asked ~= nil and asked.to.x ~= last then
                last = asked.to.x
                legs = legs + 1
            end
            local path = e:get("ai/nav/path")
            saw_unreachable = saw_unreachable or (path ~= nil and path.status == "unreachable")
        end
    end
end):in_set("zz/no_way_suite_legs")

local phase, clock = "settling", 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "settling" and clock > 0.5 then
        local listener = named(world, "listener")
        commands:trigger("ai/noisemaker/sound", { entity = listener:id(), x = 200, y = 1, z = 12, loudness = 1, kind = "footstep" })
        step("waiting")

    elseif phase == "waiting" and clock > 2 then
        local chase = state_of(world, "chaser", "ai/behavior/chase/option", "ai/behavior/chase/state")
        suite.assert_test("N1_chase_gives_up", chase ~= nil and chase.gave_up_until ~= nil, "")
        suite.assert_test("N2_and_stops_asking", named(world, "chaser"):get("ai/nav/request").chase == nil, "")
        local investigate = state_of(world, "listener", "ai/behavior/investigate/option", "ai/behavior/investigate/state")
        suite.assert_test("N3_investigate_is_done_with_the_sound", investigate ~= nil and investigate.done_at ~= nil, "")
        suite.assert_test("N4_and_stops_asking", named(world, "listener"):get("ai/nav/request").investigate == nil, "")
        suite.assert_test("N5_patrol_is_told_there_is_no_way", saw_unreachable, "")
        suite.assert_test("N6_and_picks_another_leg", legs >= 3, "legs " .. legs)
        phase = "done"
        suite.finish("BehaviorsNoWaySuite")
    end
end):in_set("zz/no_way_suite")
