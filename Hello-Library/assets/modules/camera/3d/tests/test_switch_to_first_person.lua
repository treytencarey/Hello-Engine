-- --host
-- A carrier switched from third person to a first person whose client half has never loaded here,
-- as on an owner's client. Both camera mods write `camera/3d.offset` and nothing orders the two,
-- so while both are on the carrier a `camera` change runs both, and the one that runs last wins.
-- The suite changes `camera` in every frame both are there and pins third person's write last.
--
-- SW1 the eye ends at the head
-- SW2 once settled, nothing writes `camera/3d` again
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")

local suite = helpers.create_suite("CameraSwitchToFirstPersonSuite")

local world_net

app:add_systems(Startup, { Commands }, function(commands)
    world_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzsw1" },
        ["core/net/sync"] = false,
    }):id()
end)

local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-4 end

local me
local phase, clock, settled_writes = "spawn", 0, 0

app:add_systems(PreUpdate, { World }, function(world)
    local e = me and world:get_entity(me)
    if e and e:has("camera/first_person") and e:has("camera/third_person") then
        e:patch({ camera = { yaw = e:get("camera").yaw } })
    end
end):in_set("zz/switch_first_look")

-- The losing order: third person's write after first person's.
app:add_systems(Update, {}, function() end)
    :in_set("zz/switch_first_pin")
    :after("camera/first_person/aim")
    :before("camera/third_person/aim")

app:add_systems(Last, { Query[{ changed = { "camera/3d" }, with = { "zz/carrier" } }] }, function(rows)
    if phase == "settled" then settled_writes = settled_writes + #rows:iter() end
end):in_set("zz/switch_first_count")

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
            ["camera/third_person"] = {},
        }):id()
        step("orbit")

    elseif phase == "orbit" and c3d and c3d.offset and c3d.offset.y > 2 and clock > 0.5 then
        e:patch({ ["camera/first_person"] = {} })
        step("switched")

    elseif phase == "switched" and clock > 0.5 then
        step("settled")

    elseif phase == "settled" and clock > 0.5 then
        local o, h = c3d.offset, e:get("camera").height
        suite.assert_test("SW1_the_eye_ends_at_the_head",
            not e:has("camera/third_person") and near(o.x, 0) and near(o.y, h) and near(o.z, 0),
            string.format("offset %s %s %s, height %s", tostring(o.x), tostring(o.y), tostring(o.z), tostring(h)))
        suite.assert_test("SW2_once_settled_nothing_writes_camera_3d_again", settled_writes == 0,
            "writes " .. settled_writes)
        phase = "done"
        suite.finish("CameraSwitchToFirstPersonSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("SW0_reached_" .. phase, false, "stuck in '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("CameraSwitchToFirstPersonSuite")
    end
end):in_set("zz/switch_first_suite")
