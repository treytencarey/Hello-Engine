-- Two local players holding `sidebar` at once, as a predicted crossing makes them: the stand-in
-- builds the sidebar, the real player arrives to find it built, and the stand-in goes. Headless:
-- it reads only which UI entities exist and their `Node.display`, never their layout.
--
-- H1  the stand-in going leaves the real player its sidebar, one container with its bar
-- H2  ...hidden, as the stand-in had it open and the real player has not (the stand-in's
--     `sidebar/open` goes with it, and closing hides it)
-- H3  the last local player's `sidebar` removed takes the container
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")

local suite = helpers.create_suite("SidebarHandoverSuite")

local own_net

app:add_systems(Startup, { Commands }, function(commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzsidebarhandover" },
        ["core/net/sync"] = false,
    }):id()
end)

local function player(world, name)
    for _, e in ipairs(world:query({ with = { "zz/player" } })) do
        if e:get("zz/player").name == name then
            return e
        end
    end
end

local function containers(world)
    return world:query({ with = { "sidebar/container" }, optional = { "Node" } })
end

local function shown(c) return c:get("Node").display == "Flex" end

local function local_player(name)
    return {
        ["zz/player"] = { name = name },
        ["core/net/owner"] = own_net,
        ["core/net/sync"] = false,
        input = {},
        ["input/mode"] = { mode = "input/game" },
        sidebar = {},
    }
end

local phase, clock, frames = "spawn", 0, 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    if phase == "spawn" then
        Net.declare_ownership(world, commands)
        commands:spawn(local_player("standin"))
        step("built")

    elseif phase == "built" and #containers(world) == 1 and frames > 3 then
        commands:spawn(local_player("real"))
        commands:entity(player(world, "standin"):id()):insert({ ["sidebar/open"] = {} })
        step("both")

    elseif phase == "both" and shown(containers(world)[1]) and frames > 3 then
        commands:entity(player(world, "standin"):id()):despawn()
        step("handed over")

    elseif phase == "handed over" and frames > 5 then
        local list = containers(world)
        local bars = world:query({ with = { "sidebar/bar" } })
        suite.assert_test("H1_the_stand_in_going_leaves_the_real_player_its_sidebar",
            #list == 1 and #bars == 1,
            string.format("containers=%d bars=%d", #list, #bars))
        suite.assert_test("H2_hidden_as_the_real_player_has_it_closed",
            #list == 1 and not shown(list[1]),
            "display=" .. tostring(list[1] and list[1]:get("Node").display))
        player(world, "real"):remove("sidebar")
        step("removed")

    elseif phase == "removed" and frames > 5 then
        suite.assert_test("H3_the_last_local_players_sidebar_removed_takes_the_container",
            #containers(world) == 0, "containers=" .. #containers(world))
        phase = "done"
        suite.finish("SidebarHandoverSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("H0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("SidebarHandoverSuite")
    end
end):in_set("zz/sidebar_handover_suite")
