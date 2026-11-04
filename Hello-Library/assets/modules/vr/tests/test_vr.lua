-- --host
-- `vr/active` waits for its sync. The net client sends a client-authority component in the frame it
-- changes, so one added before its entry arrives would never reach the server. `player/vr`'s suites
-- run the rest of this mod over a real connection.
--
--   V1 poses with no sync yet state nothing, while the time of the last pose is kept
--   V2 poses after the sync arrives state it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("VrSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/player"] = {},
        vr = {},
        ["core/net/local"] = {},
        ["core/net/sync"] = { ["zz/player"] = { authority = "server" } },
    })
end)

local function me(world)
    return world:query({
        with = { "zz/player" },
        optional = { "vr/active", "vr/tracking" },
    })[1]
end

local phase, t, mark = "wait", 0, 0

app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter[VrPoseInput],
}, function(world, commands, poses)
    t = t + world:delta_time()
    poses:write({ hmd_position = { x = 0, y = 1.6, z = 0 } })
    local e = me(world)
    if phase == "wait" and e ~= nil and e:has("vr/tracking") then
        phase, mark = "unsynced", t
    elseif phase == "unsynced" and t - mark > 0.5 then
        suite.assert_test("V1_no_sync_no_vr_active", not e:has("vr/active"), "")
        commands:entity(e:id()):patch({ ["core/net/sync"] = { ["vr/active"] = { authority = "client" } } })
        phase, mark = "synced", t
    elseif phase == "synced" and t - mark > 0.5 then
        suite.assert_test("V2_with_its_sync_it_is_stated", e:has("vr/active"), "")
        phase = "done"
        suite.finish("VrSuite")
    elseif phase ~= "done" and t - mark > 15 then
        suite.assert_test("V0_reached_" .. phase, false, "")
        phase = "done"
        suite.finish("VrSuite")
    end
end):in_set("zz/vr_drive")
