-- --host
-- A carrier switched from first person to a third person whose client half has never loaded here,
-- as on an owner's client. Both camera mods write `camera/3d.offset` and nothing orders the two,
-- so while both are on the carrier a `camera` change runs both, and the one that runs last wins.
-- The suite changes `camera` in every frame both are there and pins first person's write last.
--
-- SW1 the eye ends on the orbit
-- SW2 once settled, nothing writes `camera/3d` again
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

local suite = helpers.create_suite("CameraSwitchToThirdPersonSuite")

local world_net

app:add_systems(Startup, { Commands }, function(commands)
    world_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzsw3" },
        ["core/net/sync"] = false,
    }):id()
end)

local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-4 end

local function orbit(cam)
    local back = Quat.mul_vec3(Quat.from_rotation_x(cam.pitch), { x = 0, y = 0, z = cam.distance })
    return Quat.mul_vec3(Quat.from_rotation_y(cam.yaw),
        Vec3.add(Vec3.add(back, cam.offset), { x = 0, y = cam.height, z = 0 }))
end

local me
local phase, clock, settled_writes = "spawn", 0, 0

app:add_systems(PreUpdate, { World }, function(world)
    local e = me and world:get_entity(me)
    if e and e:has("camera/first_person") and e:has("camera/third_person") then
        e:patch({ camera = { yaw = e:get("camera").yaw } })
    end
end):in_set("zz/switch_third_look")

-- The losing order: first person's write after third person's.
app:add_systems(Update, {}, function() end)
    :in_set("zz/switch_third_pin")
    :after("camera/third_person/aim")
    :before("camera/first_person/aim")

app:add_systems(Last, { Query[{ changed = { "camera/3d" }, with = { "zz/carrier" } }] }, function(rows)
    if phase == "settled" then settled_writes = settled_writes + #rows:iter() end
end):in_set("zz/switch_third_count")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local e = me and world:get_entity(me)
    local c3d = e and e:get("camera/3d")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        Net.declare_ownership(world, commands)
        me = commands:spawn({
            ["zz/carrier"] = {},
            ["core/net/owner"] = world_net,
            input = {},
            ["core/net/sync"] = false,
            Transform = {},
            ["camera/first_person"] = {},
        }):id()
        step("head")

    elseif phase == "head" and c3d and c3d.offset and c3d.offset.y > 0 and clock > 0.5 then
        e:patch({ ["camera/third_person"] = {} })
        step("switched")

    elseif phase == "switched" and clock > 0.5 then
        step("settled")

    elseif phase == "settled" and clock > 0.5 then
        local o, want = c3d.offset, orbit(e:get("camera"))
        suite.assert_test("SW1_the_eye_ends_on_the_orbit",
            not e:has("camera/first_person") and near(o.x, want.x) and near(o.y, want.y) and near(o.z, want.z),
            string.format("offset %s %s %s, orbit %s %s %s", tostring(o.x), tostring(o.y), tostring(o.z),
                tostring(want.x), tostring(want.y), tostring(want.z)))
        suite.assert_test("SW2_once_settled_nothing_writes_camera_3d_again", settled_writes == 0,
            "writes " .. settled_writes)
        phase = "done"
        suite.finish("CameraSwitchToThirdPersonSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("SW0_reached_" .. phase, false, "stuck in '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("CameraSwitchToThirdPersonSuite")
    end
end):in_set("zz/switch_third_suite")
