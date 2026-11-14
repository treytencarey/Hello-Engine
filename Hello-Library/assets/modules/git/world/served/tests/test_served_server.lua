-- git/world/served on a server: its carrier states the world's commit to its players through one
-- `git/world/head` child, and puts git/ignore on the endpoint serving the world's tree.
--
-- H1  each carrier gets one git/world/head, a child of it
-- H2  git/world/served taken off one entity that stays takes its head, and the other carrier's
--     stays. Two carriers, as the last one leaving unloads the mod, which reaps what it spawned
--     whatever this mod's own cleanup does.
-- H3  a despawned carrier takes its head with it
-- I1  the endpoint serving the world's tree carries git/ignore and the core/library/filter base it
--     brings; a read-only endpoint (a library front) carries neither
-- I2  ...an endpoint arriving after the carriers gets it too
-- I3  ...it stays while a carrier is left
-- I4  ...and leaves with the last carrier
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldServedServerSuite")
local T = suite.assert_test

local TREE = "test_fixtures/zz_served_server"
write_file_bytes("assets/" .. TREE .. "/assets/a.txt", "a")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/asset"] = { mode = "server", port = 15731, asset_root = TREE },
        ["zz/served/tree"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/asset"] = { mode = "server", port = 15732, asset_root = TREE, read_only = true },
        ["zz/served/front"] = {}, ["core/net/sync"] = false })
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

--- Whether the endpoint marked `marker` carries git/ignore, and the filter base it brings.
local function ignored(world, marker)
    local e = world:query({ with = { "core/asset", marker }, optional = { "git/ignore", "core/library/filter" } })[1]
    return e ~= nil and e:has("git/ignore"), e ~= nil and e:has("core/library/filter")
end

local phase, clock, first, second = "carriers", 0, nil, nil

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "carriers" and clock > 0.5 then
        first = commands:spawn({ ["git/world/served"] = {}, ["core/net/sync"] = false }):id()
        second = commands:spawn({ ["git/world/served"] = {}, ["core/net/sync"] = false }):id()
        step("h1")

    elseif phase == "h1" and (heads(world) >= 2 and select(2, ignored(world, "zz/served/tree")) and clock > 0.5 or clock > 5) then
        local a, b = heads_under(world, first), heads_under(world, second)
        T("H1_each_carrier_gets_one_head_as_its_child", a == 1 and b == 1,
            string.format("first %d, second %d", a, b))
        local ig, base = ignored(world, "zz/served/tree")
        local fig, fbase = ignored(world, "zz/served/front")
        T("I1_the_endpoint_serving_the_tree_carries_git_ignore", ig and base and not fig and not fbase,
            string.format("tree: git/ignore %s, base %s; front: git/ignore %s, base %s",
                tostring(ig), tostring(base), tostring(fig), tostring(fbase)))
        commands:spawn({ ["core/asset"] = { mode = "server", port = 15733, asset_root = TREE },
            ["zz/served/late"] = {}, ["core/net/sync"] = false })
        step("i2")

    elseif phase == "i2" and (ignored(world, "zz/served/late") and clock > 0.3 or clock > 5) then
        T("I2_an_endpoint_arriving_later_gets_it", ignored(world, "zz/served/late"), "the late endpoint has no git/ignore")
        commands:entity(first):remove("git/world/served")
        step("h2")

    elseif phase == "h2" and (heads_under(world, first) == 0 and clock > 0.5 or clock > 5) then
        local a, b = heads_under(world, first), heads_under(world, second)
        T("H2_taking_served_off_one_takes_its_head_only", a == 0 and b == 1,
            string.format("first %d, second %d", a, b))
        T("I3_it_stays_while_a_carrier_is_left", ignored(world, "zz/served/tree"), "git/ignore left with one carrier still here")
        commands:entity(second):despawn()
        step("h3")

    elseif phase == "h3" and ((heads(world) == 0 and not ignored(world, "zz/served/tree")) and clock > 0.3 or clock > 5) then
        T("H3_a_despawned_carrier_takes_its_head", heads(world) == 0, heads(world) .. " heads left")
        local ig, base = ignored(world, "zz/served/tree")
        T("I4_it_leaves_with_the_last_carrier", not ig and not base and not ignored(world, "zz/served/late"),
            string.format("git/ignore %s, base %s", tostring(ig), tostring(base)))
        phase = "done"
        os.remove_dir("assets/" .. TREE)
        suite.finish("GIT_WORLD_SERVED_SERVER")
    end

    if phase ~= "done" and clock > 15 then
        T("H0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        phase = "done"
        os.remove_dir("assets/" .. TREE)
        suite.finish("GIT_WORLD_SERVED_SERVER")
    end
end):in_set("zz/served_server_suite")
