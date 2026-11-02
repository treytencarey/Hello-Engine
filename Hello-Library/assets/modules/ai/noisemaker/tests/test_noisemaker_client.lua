-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local On = require("bevy::ecs::prelude::On")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("NoisemakerClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/mover"] = {},
        ["ai/noisemaker"] = { interval = 0.1 },
        Transform = {},
        Velocity3d = { linvel = { x = 6, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
end)

app:add_systems(Update, {
    Query[{ with = { "zz/mover", Mut["Velocity3d"] } }],
}, function(movers)
    for _, e in ipairs(movers:iter_mut()) do
        e:patch({ Velocity3d = { linvel = { x = 6 } } })
    end
end):in_set("zz/noisemaker_client_suite_drive")

local heard = 0
app:add_observer(On["ai/noisemaker/sound"], {}, function()
    heard = heard + 1
end)

local clock = 0
local finished = false

app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "zz/mover", "ai/noisemaker" } }],
}, function(time, movers)
    clock = clock + time:delta_secs()
    local mover = movers:iter()[1]
    if clock > 1.5 and not finished then
        finished = true
        suite.assert_test("NC1_a_client_makes_no_sounds", heard == 0, "heard " .. heard)
        -- The fields stay as given: the server half is what fills them.
        suite.assert_test("NC2_a_client_does_not_load_the_mod",
            mover ~= nil and mover:get("ai/noisemaker").quiet_speed == nil, "")
        suite.finish("NoisemakerClientSuite")
    end
end):in_set("zz/noisemaker_client_suite")
