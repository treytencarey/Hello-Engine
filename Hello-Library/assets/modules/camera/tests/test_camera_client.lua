-- --host
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("CameraClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local function subject(world, name)
    for _, e in ipairs(world:query({
        with = { "camera", "zz/subject" },
    })) do
        if e:get("zz/subject").name == name then
            return e
        end
    end
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local fresh, carried, partial = subject(world, "fresh"), subject(world, "carried"), subject(world, "partial")

    if phase == "spawn" then
        commands:spawn({ ["zz/subject"] = { name = "fresh" }, camera = {}, ["core/net/sync"] = false })
        commands:spawn({
            ["zz/subject"] = { name = "carried" },
            camera = {
                yaw = 1.25,
                pitch = 0.5,
                distance = 3,
                height = 2,
                offset = { x = 0, y = 1, z = 0 },
            },
            ["core/net/sync"] = false,
        })
        commands:spawn({ ["zz/subject"] = { name = "partial" }, camera = { distance = 12 }, ["core/net/sync"] = false })
        phase, clock = "check", 0

    elseif phase == "check" and fresh and fresh:get("camera").yaw ~= nil
        and partial and partial:get("camera").yaw ~= nil and clock > 0.3 then
        local f, c, p = fresh:get("camera"), carried:get("camera"), partial:get("camera")
        suite.assert_test("C1_an_empty_camera_gets_every_default",
            f.yaw == 0 and f.pitch == -0.3 and f.distance == 8.0 and f.height == 1.5
                and f.offset and f.offset.x == 1.0,
            string.format("yaw=%s pitch=%s distance=%s height=%s", tostring(f.yaw), tostring(f.pitch),
                tostring(f.distance), tostring(f.height)))
        suite.assert_test("C2_carried_state_is_kept",
            c.yaw == 1.25 and c.pitch == 0.5 and c.distance == 3 and c.height == 2 and c.offset.y == 1,
            string.format("yaw=%s distance=%s", tostring(c.yaw), tostring(c.distance)))
        suite.assert_test("C3_a_partial_camera_keeps_its_fields_and_fills_the_rest",
            p.distance == 12 and p.yaw == 0 and p.height == 1.5,
            string.format("distance=%s yaw=%s", tostring(p.distance), tostring(p.yaw)))
        phase = "done"
        suite.finish("CameraClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("CameraClientSuite")
    end
end):in_set("zz/camera_client_suite")
