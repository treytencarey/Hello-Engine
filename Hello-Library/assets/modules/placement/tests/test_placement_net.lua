-- --host
-- Placement over a real connection. An isolated server world approves a placed entity as the mod
-- that spawns one would, an isolated client world places it, and this VM writes the messages the
-- engine's VR plugin writes, so the client points with the VR pointer's ray. The mouse ray needs a
-- window and is not here.
--
--   PL1 a placing entity binds confirm and a taking cancel on this client's player
--   PL2 it follows the ray onto the ground, past the player's body, and stays there, past its own
--       collider; the server hears where it is
--   PL3 the trigger confirms: the owner's removal of `placement` reaches the server
--   PL4 the server takes the Transform back
--   PL5 the binding goes with the last placing entity
--   PL6 B, held: nothing is cancelled yet, and another binding of Escape does not fire
--   PL7 B let go: the entity is cancelled on both sides, the binding goes, and the other binding of
--       Escape never fired
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local VrInputRaw = require("hello::vr_messages::VrInputRaw")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("PlacementNetSuite")
local T = suite.assert_test

local PORT = 15421

local DEFAULTS = {
    srv_ready = false,
    c_connected = false,
    spawn_one = false,
}
local ts = helpers.shared_state("PlacementNetState", DEFAULTS)

local GROUND = {
    Transform = { translation = { x = 0, y = -0.5, z = 0 } },
    Collider3d = { cuboid = { hx = 50, hy = 0.5, hz = 50 } },
    ["core/net/sync"] = false,
}

helpers.make_fixture("modules/test_fixtures/gen_placement_net_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PlacementNetState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpl", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzpl", port = boot.PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn(boot.GROUND)
end)

-- What the mod that spawns a placed entity does on the server: it vouches for it and approves.
app:add_systems(Update, {
    Query[{ added = { "core/net/predict" } }],
    Commands,
}, function(pending, commands)
    for _, row in ipairs(pending:iter()) do
        local requested = row:get("core/net/predict").requested or {}
        if requested.placement ~= nil then
            local e = commands:entity(row:id())
            e:insert({
                ["zz/placed"] = {},
                placement = {},
                Transform = requested.Transform,
                ["core/net/sync"] = {
                    ["zz/placed"] = { authority = "server" },
                    placement = { authority = "client" },
                    Transform = { authority = "client", reliable = false },
                },
            })
            e:remove("core/net/predict")
        end
    end
end):in_set("zz/placement_approve")

app:add_systems(Update, {
    Query[{
        with = { "zz/placed" },
        optional = { "placement", "core/net/sync", "Transform" },
    }],
}, function(placed)
    ts.srv_ready = true
    local list = placed:iter()
    ts.s_count = #list
    local p = list[#list]
    if p ~= nil then
        ts.s_placement = p:has("placement")
        ts.s_authority = ((p:get("core/net/sync") or {}).Transform or {}).authority or false
        local at = p:get("Transform").translation
        ts.s_x, ts.s_y, ts.s_z = at.x, at.y, at.z
    end
end):in_set("zz/placement_server")
]=])

helpers.make_fixture("modules/test_fixtures/gen_placement_net_client.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local ts = helpers.shared_state("PlacementNetState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn(boot.GROUND)
    -- This client's player: its input, and the VR pointer's ray from its hand, which starts inside
    -- its body.
    local me = commands:spawn({
        ["zz/me"] = {},
        input = {},
        ["input/mode"] = { mode = "input/ui" },
        ["input/ui"] = { zz = { esc = { key = "Escape" } } },
        ["vr/input"] = {},
        ["vr/pointer"] = { pitch = 0, yaw = 0 },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = {},
    }):id()
    commands:entity(me):add_child(commands:spawn({
        ["zz/body"] = {},
        Collider3d = { ball = { radius = 0.3 } },
        Transform = { translation = { x = 0, y = 1.5, z = 0 } },
    }):id())
end)

local joined = false
app:add_systems(Update, {
    Query[{ with = { "core/net", "core/net/state" } }],
    Query[{
        with = { "zz/me" },
        optional = { "input/ui" },
    }],
    Query[{
        with = { "zz/placed" },
        optional = { "placement", "Transform" },
    }],
    Query[{ added = { "input/ui/zz/esc" } }],
    Commands,
}, function(nets, players, placed, escapes, commands)
    if ts.srv_ready and not joined then
        joined = true
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzpl_c", ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzpl_c", ip = "127.0.0.1", port = boot.PORT },
            ["core/net/sync"] = false,
        })
    end
    for _, n in ipairs(nets:iter()) do
        ts.c_connected = n:get("core/net/state").connected == true
    end
    ts.c_escapes = (ts.c_escapes or 0) + #escapes:iter()
    local me = players:iter()[1]
    if me ~= nil then
        local ui = me:get("input/ui") or {}
        local bound = ui.placement
        ts.c_bound = bound ~= nil
        ts.c_takes = bound ~= nil and bound.cancel.take == true and bound.cancel.key == "Escape"
            and bound.cancel.button == "Right" and bound.confirm.button == "Left"
    end
    local placing = 0
    for _, p in ipairs(placed:iter()) do
        if p:has("placement") then
            placing = placing + 1
            local at = p:get("Transform").translation
            ts.c_x, ts.c_y, ts.c_z = at.x, at.y, at.z
        end
    end
    ts.c_placing = placing
    ts.c_count = #placed:iter()
    if ts.spawn_one then
        ts.spawn_one = false
        commands:spawn({
            ["zz/placed"] = {},
            placement = {},
            Collider3d = { cuboid = { hx = 0.25, hy = 0.25, hz = 0.25 } },
            Transform = { translation = { x = 5, y = 0, z = 5 } },
            ["core/net/sync"] = {
                ["zz/placed"] = { authority = "server" },
                placement = { authority = "client" },
                Transform = { authority = "client", reliable = false },
            },
        })
    end
end):in_set("zz/placement_client")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_placement_net_server.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
    GROUND = GROUND,
}, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_placement_net_client.lua", {
    DEFAULTS = DEFAULTS,
    PORT = PORT,
    GROUND = GROUND,
}, { headless = true })

-- The hand, up at 1.5 m, aims down at the ground 1.5 m ahead.
local HAND = { x = 0, y = 1.5, z = 0 }
local TARGET = { x = 0, y = 0, z = -1.5 }
local AIM = Quat.from_rotation_arc({ x = 0, y = 0, z = -1 }, Vec3.normalize(Vec3.sub(TARGET, HAND)))
local raw, pointing = {}, false

local function close(x, y, z, at, within)
    return type(x) == "number" and Vec3.distance({ x = x, y = y, z = z }, at) < (within or 0.05)
end
local function show(x, y, z) return string.format("%s %s %s", tostring(x), tostring(y), tostring(z)) end

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end

step(function() return ts.srv_ready and ts.c_connected end, function()
    ts.spawn_one = true
end)
step(within(8, function() return ts.c_placing == 1 and ts.c_bound end), function()
    T("PL1_a_placing_entity_binds_confirm_and_a_taking_cancel", ts.c_bound and ts.c_takes, tostring(ts.c_bound))
    pointing = true
end)
step(within(5, function() return close(ts.c_x, ts.c_y, ts.c_z, TARGET) end), function()
    T("PL2_it_follows_the_ray_onto_the_ground", close(ts.c_x, ts.c_y, ts.c_z, TARGET), show(ts.c_x, ts.c_y, ts.c_z))
end)
step(after(0.5), function()
    T("PL2_and_stays_there_past_its_own_collider", close(ts.c_x, ts.c_y, ts.c_z, TARGET), show(ts.c_x, ts.c_y, ts.c_z))
end)
step(within(5, function() return close(ts.s_x, ts.s_y, ts.s_z, TARGET) end), function()
    T("PL2_and_the_server_hears_where_it_is", close(ts.s_x, ts.s_y, ts.s_z, TARGET), show(ts.s_x, ts.s_y, ts.s_z))
    raw = { right_trigger = 1 }
end)
step(after(0.3), function() raw = {} end)
step(within(5, function() return ts.s_placement == false and ts.s_authority == "server" end), function()
    T("PL3_the_owners_removal_of_placement_reaches_the_server", ts.s_placement == false and ts.c_placing == 0, tostring(ts.s_placement))
    T("PL4_the_server_takes_the_transform_back", ts.s_authority == "server", tostring(ts.s_authority))
end)
step(after(0.3), function()
    T("PL5_the_binding_goes_with_the_last_placing_entity", not ts.c_bound, "")
    ts.spawn_one = true
end)
step(within(8, function() return ts.c_placing == 1 and ts.c_bound end), function()
    raw = { b = true }
end)
step(after(0.5), function()
    T("PL6_held_nothing_is_cancelled_yet", ts.c_placing == 1, tostring(ts.c_placing))
    T("PL6_and_another_binding_of_escape_does_not_fire", ts.c_escapes == 0, tostring(ts.c_escapes))
    raw = {}
end)
step(within(5, function() return ts.c_count == 1 and ts.s_count == 1 end), function()
    T("PL7_let_go_it_is_cancelled_on_both_sides", ts.c_count == 1 and ts.s_count == 1,
        string.format("client %s, server %s", tostring(ts.c_count), tostring(ts.s_count)))
end)
step(after(0.5), function()
    T("PL7_the_binding_goes", not ts.c_bound, "")
    T("PL7_and_the_other_binding_of_escape_never_fired", ts.c_escapes == 0, tostring(ts.c_escapes))
end)

local done = false
app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter[VrInputRaw],
    bevy.MessageWriter[VrPoseInput],
}, function(world, commands, write_raw, write_pose)
    t = t + world:delta_time()
    write_raw:write(raw)
    if pointing then
        write_pose:write({
            hmd_position = { x = 0, y = 1.7, z = 0.2 },
            hmd_rotation = { x = 0, y = 0, z = 0, w = 1 },
            hmd_forward = { x = 0, y = 0, z = -1 },
            right_position = HAND,
            right_rotation = AIM,
            right_forward = Quat.mul_vec3(AIM, { x = 0, y = 0, z = -1 }),
        })
    end
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("PlacementNetSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 20 then
        T("PL0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("PlacementNetSuite")
    end
end):in_set("zz/placement_drive")
