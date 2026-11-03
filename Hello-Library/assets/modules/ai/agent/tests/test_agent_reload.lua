-- --host
-- Each mod an agent is made of, reloaded in turn while it works: what it built is still there, once.
-- Nothing here walks, so a behaviour stays chosen through its reload.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("AgentReloadSuite")

local function agent(commands, name, slot, behaviours)
    local bundle = {
        ["zz/name"] = { name = name, x = slot * 200 },
        ["ai/agent"] = { think_hz = 20 },
        ["ai/nav"] = {},
        ["ai/steering"] = { stall_timeout = 1000 },
        ["ai/perception"] = { forget_sound_after = 1000 },
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

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 200, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 200 } },
    })
    agent(commands, "chaser", 0, { ["ai/behavior/chase"] = { speed = 0 } })
    commands:spawn({
        ["ai/perception/target"] = {},
        Transform = { translation = { x = 0, y = 1, z = 8 } },
    })
    agent(commands, "listener", 1, { ["ai/behavior/investigate"] = { speed = 0, fresh_for = 1000 } })
    agent(commands, "walker", 2, { ["ai/behavior/patrol"] = { speed = 0, radius = 6 } })
end)

local changes = {}
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        local path = tostring(event.path)
        changes[path] = (changes[path] or 0) + 1
    end
end):in_set("zz/agent_reload_watch")

local function changed_count(file)
    for path, n in pairs(changes) do
        if path:find(file, 1, true) then
            return n
        end
    end
    return 0
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/agent/options", "ai/agent/memory", "ai/agent/tick", "ai/nav/request" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function options(world, name, marker)
    return world:query({
        iter_many = named(world, name):get("ai/agent/options") or {},
        with = { marker },
        optional = { "ai/agent/chosen", marker .. "/state" },
    })
end

local function chosen_count(world, name)
    return #world:query({
        iter_many = named(world, name):get("ai/agent/options") or {},
        with = { "ai/agent/chosen" },
    })
end

-- What each check compares to: the world as it was before its reload.
local function snapshot(world)
    local snap = {}
    for _, row in ipairs({
        { "chaser", "ai/behavior/chase/option", "ai/behavior/chase", "chase" },
        { "listener", "ai/behavior/investigate/option", "ai/behavior/investigate", "investigate" },
        { "walker", "ai/behavior/patrol/option", "ai/behavior/patrol", "patrol" },
    }) do
        local name, marker = row[1], row[2]
        local list = world:query({
            iter_many = named(world, name):get("ai/agent/options") or {},
            with = { marker },
            optional = { "ai/agent/chosen", row[3] .. "/state" },
        })
        snap[name] = {
            count = #list,
            chosen = list[1] and list[1]:has("ai/agent/chosen"),
            id = list[1] and list[1]:id(),
            state = list[1] and list[1]:get(row[3] .. "/state"),
            asked = named(world, name):get("ai/nav/request")[row[4]],
        }
    end
    return snap
end

local function all_kept(world, before)
    local now = snapshot(world)
    for name, was in pairs(before) do
        local is = now[name]
        if is.count ~= 1 or not is.chosen or is.id ~= was.id or is.asked == nil or chosen_count(world, name) ~= 1 then
            return false, string.format("%s: options %d, chosen %s, same %s, asked %s, chosen count %d",
                name, is.count, tostring(is.chosen), tostring(is.id == was.id), tostring(is.asked ~= nil), chosen_count(world, name))
        end
    end
    return true, ""
end

local BASE = "assets/modules/ai/"
local RELOADS = {
    { "chase", "behavior/chase/server/init.lua" },
    { "investigate", "behavior/investigate/server/init.lua" },
    { "patrol", "behavior/patrol/server/init.lua" },
    { "agent", "agent/server/init.lua" },
    { "perception", "perception/server/init.lua" },
}

local phase, clock, turn = "settling", 0, 1
local before, seen_before, sounds_before, ticks_before, count_before

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function reload()
        local path = BASE .. RELOADS[turn][2]
        count_before = changed_count(RELOADS[turn][2])
        ticks_before = named(world, "chaser"):get("ai/agent/tick").n
        seen_before = #named(world, "chaser"):get("ai/agent/memory").seen
        write_file_bytes(path, read_file_bytes(path))
        step("reloading")
    end

    if phase == "settling" and clock > 1 then
        local listener = named(world, "listener")
        if listener ~= nil then
            commands:trigger("ai/noisemaker/sound", { entity = listener:id(), x = 200, y = 1, z = 6, loudness = 1, kind = "footstep" })
            step("working")
        end

    elseif phase == "working" and clock > 1 then
        local _, why = all_kept(world, snapshot(world))
        suite.assert_test("RL0_all_working_before_any_reload", why == "", why)
        before = snapshot(world)
        reload()

    elseif phase == "reloading" and changed_count(RELOADS[turn][2]) > count_before then
        step("reloaded")

    elseif phase == "reloaded" and clock > 0.5 then
        local name = RELOADS[turn][1]
        local kept, why = all_kept(world, before)
        suite.assert_test("RL1_" .. name .. "_reload_keeps_each_option_chosen_and_asking_once", kept, why)
        local now = snapshot(world)
        if name == "chase" then
            suite.assert_test("RL2_chase_keeps_its_target", now.chaser.state ~= nil and now.chaser.state.target ~= nil, "")
        elseif name == "investigate" then
            suite.assert_test("RL3_investigate_keeps_its_sound", now.listener.state ~= nil and now.listener.state.at ~= nil, "")
        elseif name == "patrol" then
            suite.assert_test("RL4_patrol_keeps_its_home", now.walker.state ~= nil and now.walker.state.home.x == 400 and now.walker.state.home.z == 0, "")
        elseif name == "agent" then
            local chaser = named(world, "chaser")
            suite.assert_test("RL5_agent_keeps_its_memory_and_its_clock",
                #chaser:get("ai/agent/memory").seen == seen_before and chaser:get("ai/agent/tick").n > ticks_before, "")
        elseif name == "perception" then
            local chaser = named(world, "chaser")
            suite.assert_test("RL6_perception_still_sees", chaser:get("ai/agent/memory").seen[1].seen_at > time:elapsed_secs() - 0.5, "")
            sounds_before = #named(world, "listener"):get("ai/agent/memory").sound
            local listener = named(world, "listener")
            commands:trigger("ai/noisemaker/sound", { entity = listener:id(), x = 200, y = 1, z = 7, loudness = 1, kind = "footstep" })
            step("after sound")
            return
        end
        turn = turn + 1
        reload()

    elseif phase == "after sound" and clock > 0.3 then
        local sounds = #named(world, "listener"):get("ai/agent/memory").sound
        suite.assert_test("RL7_after_a_reload_a_sound_is_heard_once", sounds == sounds_before + 1, sounds_before .. " to " .. sounds)
        phase = "done"
        suite.finish("AgentReloadSuite")
    end

    if phase ~= "done" and clock > 12 then
        suite.assert_test("RL_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s, turn " .. turn)
        phase = "done"
        suite.finish("AgentReloadSuite")
    end
end):in_set("zz/agent_reload_suite")
