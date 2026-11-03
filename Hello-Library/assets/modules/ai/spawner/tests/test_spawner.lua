-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("SpawnerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 1000, hy = 0.5, hz = 1000 } },
    })
    commands:spawn({ ["zz/name"] = { name = "tall" }, ["ai/spawner"] = { center_x = 700, body_radius = 0.6, body_half_height = 0.8 } })
    commands:spawn({ ["zz/name"] = { name = "spawner" }, ["ai/spawner"] = { count = 3, radius = 10, center_x = 100, y = 2, model = "zz/model" } })
    commands:spawn({ ["zz/name"] = { name = "plain" }, ["ai/spawner"] = {} })
    commands:spawn({ ["zz/name"] = { name = "doomed" }, ["ai/spawner"] = { count = 2, center_x = 300 } })
    commands:spawn({ ["zz/name"] = { name = "taken off" }, ["ai/spawner"] = { count = 2, center_x = 500 } })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/spawner", "ai/spawner/agents" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function bodies(world, name)
    local list = named(world, name):get("ai/spawner/agents") or {}
    return world:query({
        iter_many = list,
        with = { "ai/spawner/agent", "Transform", "RigidBody3d", "Collider3d", "LockedAxes3d", "Velocity3d", "movement", "animation", "core/net/sync" },
        optional = { "player" },
    })
end

local function all_bodies(world)
    -- By what makes it a body: a link gone doesn't mean the body has.
    return #world:query({ with = { "movement" } })
end

local fw_changes = 0
local MessageReader = require("bevy::prelude").MessageReader
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/spawner/server/init.lua", 1, true) then
            fw_changes = fw_changes + 1
        end
    end
end):in_set("zz/spawner_suite_reload")

local phase, clock = "spawned", 0
local first_ids, before = {}, 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawned" and all_bodies(world) == 9 and clock > 2 then
        local list = bodies(world, "spawner")
        suite.assert_test("SP1_it_makes_count_bodies_linked_to_itself", #list == 3, "bodies " .. #list)
        suite.assert_test("SP2_one_by_default", #bodies(world, "plain") == 1, "")
        local b = list[1]
        local at = world:get_entity(b:id()).GlobalTransform:compute_transform().translation
        suite.assert_test("SP3_around_its_centre_at_its_radius", math.abs(math.sqrt((at.x - 100) ^ 2 + at.z ^ 2) - 10) < 0.1, "")
        local second = world:get_entity(list[2]:id()).GlobalTransform:compute_transform().translation
        suite.assert_test("SP3b_each_in_its_own_place", math.abs(at.x - second.x) + math.abs(at.z - second.z) > 2, "")
        -- A capsule rests with its centre a half height and a radius up: the ground proves the shape.
        suite.assert_test("SP4_each_falls_as_a_dynamic_body_and_rests_on_the_capsule_a_player_has",
            b:get("RigidBody3d") == "Dynamic" and math.abs(at.y - 0.9) < 0.05, "y " .. at.y)
        local tall = world:get_entity(bodies(world, "tall")[1]:id()).GlobalTransform:compute_transform().translation
        suite.assert_test("SP4b_its_size_comes_from_the_spawner", math.abs(tall.y - 1.4) < 0.05, "y " .. tall.y)
        suite.assert_test("SP5_with_its_model_and_movement_and_no_player",
            b:get("animation").model == "zz/model" and b:get("movement").speed ~= nil and not b:has("player"), "")
        suite.assert_test("SP5b_an_unset_model_is_animations_default", bodies(world, "plain")[1]:get("animation").model == "Placeholder-Character/Model", "")
        local sync = b:get("core/net/sync")
        suite.assert_test("SP6_body_collider_and_place_sync_from_the_server",
            sync.RigidBody3d.authority == "server" and sync.Collider3d.authority == "server" and sync.Transform.authority == "server", "")
        for i, one in ipairs(list) do
            first_ids[i] = one:id()
        end
        commands:entity(named(world, "spawner"):id()):patch({ ["ai/spawner"] = { count = 5 } })
        step("raised")

    elseif phase == "raised" and #bodies(world, "spawner") == 5 then
        local list = bodies(world, "spawner")
        suite.assert_test("SP8_raising_count_adds_only_the_difference",
            list[1]:id() == first_ids[1] and list[3]:id() == first_ids[3], "")
        commands:entity(named(world, "spawner"):id()):patch({ ["ai/spawner"] = { count = 1 } })
        step("lowered")

    elseif phase == "lowered" and clock > 0.3 then
        suite.assert_test("SP9_lowering_it_despawns_nobody", #bodies(world, "spawner") == 5, "bodies " .. #bodies(world, "spawner"))
        before = fw_changes
        commands:entity(named(world, "spawner"):id()):patch({ ["ai/spawner"] = { count = 5 } })
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/spawner/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and fw_changes > before then
        step("after reload")

    elseif phase == "after reload" and clock > 0.5 then
        suite.assert_test("SP10_a_reload_keeps_its_bodies_and_makes_no_more",
            #bodies(world, "spawner") == 5 and all_bodies(world) == 11 and bodies(world, "spawner")[1]:id() == first_ids[1],
            string.format("bodies %d of %d", #bodies(world, "spawner"), all_bodies(world)))
        commands:entity(named(world, "doomed"):id()):despawn()
        commands:entity(named(world, "taken off"):id()):remove("ai/spawner")
        step("gone")

    elseif phase == "gone" and all_bodies(world) == 7 then
        suite.assert_test("SP11_its_bodies_go_with_it_despawned_or_taken_off", #bodies(world, "spawner") == 5, "")
        phase = "done"
        suite.finish("SpawnerSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("SP0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s, bodies " .. all_bodies(world))
        phase = "done"
        suite.finish("SpawnerSuite")
    end
end):in_set("zz/spawner_suite")
