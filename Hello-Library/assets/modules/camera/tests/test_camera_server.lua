-- --host
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("CameraServerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)

    if phase == "spawn" then
        commands:spawn({ ["zz/subject"] = {}, camera = {} })
        phase, clock = "check", 0

    elseif phase == "check" then
        for _, e in ipairs(world:query({
            with = { "camera", "zz/subject", "core/net/sync" },
        })) do
            local sync = e:get("core/net/sync").camera
            if sync and clock > 0.3 then
                suite.assert_test("S1_the_camera_declares_client_authority_sent_to_its_owner",
                    sync.authority == "client" and sync.target == "owner",
                    string.format("authority=%s target=%s", tostring(sync.authority), tostring(sync.target)))
                suite.assert_test("S2_the_server_sets_no_defaults", e:get("camera").yaw == nil,
                    "yaw=" .. tostring(e:get("camera").yaw))
                phase = "done"
                suite.finish("CameraServerSuite")
            end
        end
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("CameraServerSuite")
    end
end):in_set("zz/camera_server_suite")
