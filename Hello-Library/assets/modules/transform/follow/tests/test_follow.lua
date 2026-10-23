-- --host
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("FollowSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

-- A quarter turn about Y, as a body that turned to face sideways.
local QUARTER = { x = 0, y = 0.70710678, z = 0, w = 0.70710678 }

local function find(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name", "Transform" },
        optional = { "transform/follow" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function world_transform(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform()
end

local function near(a, b) return math.abs(a - b) < 1e-3 end

-- The child is spawned with an identity Transform; the mod has run once it is not.
local function written(e)
    local t = e:get("Transform").translation
    return not (t.x == 0 and t.y == 0 and t.z == 0)
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local body, child = find(world, "body"), find(world, "child")
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        local parent = commands:spawn({
            ["zz/name"] = { name = "body" },
            ["core/net/sync"] = false,
            Transform = { translation = { x = 5, y = 0, z = 0 }, rotation = QUARTER },
        })
        local child_id = commands:spawn({
            ["zz/name"] = { name = "child" },
            ["core/net/sync"] = false,
            Transform = {},
            ["transform/follow"] = {
                rotation = { x = 0, y = 0, z = 0, w = 1 },
                offset = { x = 0, y = 1.5, z = 2 },
            },
        }):id()
        commands:entity(parent:id()):add_child(child_id)
        step("placed")

    -- The mod loads when the child appears and its first run can come frames later than its
    -- load (its system is moved to its own place before propagation), so wait for that run.
    elseif phase == "placed" and child and clock > 0.3 and written(child) then
        local t = world_transform(world, child)
        suite.assert_test("T1_the_child_keeps_its_own_world_rotation",
            near(t.rotation.x, 0) and near(t.rotation.y, 0) and near(t.rotation.z, 0) and near(math.abs(t.rotation.w), 1),
            string.format("rotation %.3f %.3f %.3f %.3f", t.rotation.x, t.rotation.y, t.rotation.z, t.rotation.w))
        suite.assert_test("T2_the_child_sits_at_its_world_offset",
            near(t.translation.x, 5) and near(t.translation.y, 1.5) and near(t.translation.z, 2),
            string.format("at %.3f %.3f %.3f", t.translation.x, t.translation.y, t.translation.z))
        body:patch({ Transform = { translation = { x = -3, y = 0, z = 1 } } })
        step("moved")

    elseif phase == "moved" and clock > 0.3 then
        local t = world_transform(world, child)
        suite.assert_test("T3_the_child_follows_when_the_parent_moves",
            near(t.translation.x, -3) and near(t.translation.y, 1.5) and near(t.translation.z, 3)
                and near(math.abs(t.rotation.w), 1),
            string.format("at %.3f %.3f %.3f", t.translation.x, t.translation.y, t.translation.z))
        phase = "done"
        suite.finish("FollowSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("T0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("FollowSuite")
    end
end):in_set("zz/follow_suite")
