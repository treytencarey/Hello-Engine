-- git/world/served on a server: its carrier states the world's commit to its players through one
-- `git/world/head` child.
--
-- H1  each carrier gets one git/world/head, a child of it
-- H2  git/world/served taken off one entity that stays takes its head, and the other carrier's
--     stays. Two carriers, as the last one leaving unloads the mod, which reaps what it spawned
--     whatever this mod's own cleanup does.
-- H3  a despawned carrier takes its head with it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldServedServerSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function heads_under(world, id)
    local n = 0
    for _, h in ipairs(world:query({ with = { "git/world/head", "ChildOf" } })) do
        if h:get("ChildOf") == id then n = n + 1 end
    end
    return n
end

local function heads(world)
    return #world:query({ with = { "git/world/head" } })
end

local phase, clock, first, second = "carriers", 0, nil, nil

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "carriers" and clock > 0.2 then
        first = commands:spawn({ ["git/world/served"] = {}, ["core/net/sync"] = false }):id()
        second = commands:spawn({ ["git/world/served"] = {}, ["core/net/sync"] = false }):id()
        step("h1")

    elseif phase == "h1" and (heads(world) >= 2 and clock > 0.5 or clock > 5) then
        local a, b = heads_under(world, first), heads_under(world, second)
        T("H1_each_carrier_gets_one_head_as_its_child", a == 1 and b == 1,
            string.format("first %d, second %d", a, b))
        commands:entity(first):remove("git/world/served")
        step("h2")

    elseif phase == "h2" and (heads_under(world, first) == 0 and clock > 0.5 or clock > 5) then
        local a, b = heads_under(world, first), heads_under(world, second)
        T("H2_taking_served_off_one_takes_its_head_only", a == 0 and b == 1,
            string.format("first %d, second %d", a, b))
        commands:entity(second):despawn()
        step("h3")

    elseif phase == "h3" and (heads(world) == 0 or clock > 5) then
        T("H3_a_despawned_carrier_takes_its_head", heads(world) == 0, heads(world) .. " heads left")
        phase = "done"
        suite.finish("GIT_WORLD_SERVED_SERVER")
    end

    if phase ~= "done" and clock > 15 then
        T("H0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        phase = "done"
        suite.finish("GIT_WORLD_SERVED_SERVER")
    end
end):in_set("zz/served_server_suite")
