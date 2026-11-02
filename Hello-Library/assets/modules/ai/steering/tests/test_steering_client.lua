-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("SteeringClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/agent"] = {},
        ["ai/steering"] = {},
        ["ai/nav/path"] = { solved_id = 1, status = "ready", path = { { x = 10, y = 0, z = 0 } }, regions = {} },
        Transform = {},
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
end)

local clock = 0
local finished = false

app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "zz/agent", "ai/steering", "Velocity3d" },
        optional = { "ai/steering/state" },
    }],
}, function(time, agents)
    clock = clock + time:delta_secs()
    if clock > 1 and not finished then
        finished = true
        local agent = agents:iter()[1]
        suite.assert_test("SCL1_a_client_does_not_load_the_mod",
            agent ~= nil and agent:get("ai/steering").speed == nil and not agent:has("ai/steering/state"), "")
        suite.assert_test("SCL2_a_client_writes_no_velocity", agent ~= nil and agent:get("Velocity3d").linvel.x == 0, "")
        suite.finish("SteeringClientSuite")
    end
end):in_set("zz/steering_client_suite")
