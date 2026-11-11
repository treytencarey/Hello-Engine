-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("CollisionTriggerSuite")

local function zone(commands, x, name)
    commands:spawn({
        Transform = { translation = { x = x, y = 0, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { ball = { radius = 1.0 } },
        collision_trigger = {},
        ["zz/zone"] = { name = name },
        ["core/net/sync"] = false,
    })
end

local function body(commands, x, marker, data)
    commands:spawn({
        Transform = { translation = { x = x, y = 0, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { ball = { radius = 0.15 } },
        GravityScale3d = { value = 0 },
        [marker] = data,
        ["core/net/sync"] = false,
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    zone(commands, 0, "main")
    zone(commands, 100, "spare")
    for i, name in ipairs({ "one", "two", "three", "four" }) do
        body(commands, 10 * i, "zz/probe", { name = name })
    end
    body(commands, -10, "core/net/peer/mirror", { stable_id = "zz", source_peer = "zz", via = "zz" })
end)

-- A portal-shaped consumer: it reads in Update what the trigger wrote in First.
local log = {}
app:add_systems(Update, { World }, function(world)
    for _, z in ipairs(world:query({
        changed = { "collision_trigger" },
        with = { "zz/zone" },
    })) do
        local ct = z:get("collision_trigger")
        for _, kind in ipairs({ "entered", "exited" }) do
            local ids = ct[kind] or {}
            if #ids > 0 then
                for _, probe in ipairs(world:query({
                    iter_many = ids,
                    with = { "zz/probe" },
                    without = { "core/net/peer/mirror" },
                })) do
                    log[#log + 1] = kind .. " " .. probe:get("zz/probe").name
                end
            end
        end
    end
end):in_set("zz/collision_trigger_suite_consumer")

-- T6 to T8: what a reload of the mod writes on a zone that came with its own list, and that the
-- watcher has seen the file change.
local reloads, rewrites = 0, 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("collision_trigger/shared/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/collision_trigger_suite_reloads")
app:add_systems(Update, {
    Query[{
        changed = { "Sensor3d" },
        with = { "zz/carried" },
    }],
    Query[{
        changed = { "ActiveEvents3d" },
        with = { "zz/carried" },
    }],
    Query[{
        changed = { "CollidingEntities3d" },
        with = { "zz/carried" },
    }],
    Query[{
        changed = { "ActiveCollisionTypes3d" },
        with = { "zz/carried" },
    }],
}, function(sensors, events, lists, types)
    rewrites = rewrites + #sensors:iter() + #events:iter() + #lists:iter() + #types:iter()
end):in_set("zz/collision_trigger_suite_rewrites")

local function zones(world)
    local found = {}
    for _, z in ipairs(world:query({
        with = { "zz/zone" },
        optional = { "collision_trigger", "Sensor3d", "CollidingEntities3d", "ActiveEvents3d", "ActiveCollisionTypes3d" },
    })) do
        found[z:get("zz/zone").name] = z
    end
    return found
end

local function move(world, name, x)
    for _, e in ipairs(world:query({ with = { "zz/probe" } })) do
        if e:get("zz/probe").name == name then
            e:patch({ Transform = { translation = { x = x, y = 0, z = 0 } } })
        end
    end
end

local function expect(name, want)
    local copy = { table.unpack(log) }
    table.sort(copy)
    local got = table.concat(copy, "|")
    suite.assert_test(name, got == want, "log: " .. got)
    log = {}
end

local phase, clock, burst = "setup", 0, 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local z = zones(world)
    local function step(next_phase)
        phase, clock = next_phase, 0
    end

    if phase == "setup" and clock > 0.5 and z.main and z.main:has("Sensor3d") then
        log = {}
        move(world, "one", 0)
        for _, m in ipairs(world:query({ with = { "core/net/peer/mirror" } })) do
            m:patch({ Transform = { translation = { x = 0.5, y = 0, z = 0 } } })
        end
        step("one in")

    elseif phase == "one in" and clock > 0.5 then
        expect("T1_entering_is_seen_once_and_a_mirror_never", "entered one")
        step("burst")

    elseif phase == "burst" and clock > 0.1 then
        -- One body every 0.1 s: several physics steps apart, so each lands in its own write.
        burst = burst + 1
        local order = { { "two", -0.6 }, { "three", 0.6 }, { "four", 0 }, { "one", 30 } }
        if order[burst] then
            move(world, order[burst][1], order[burst][2])
            clock = 0
        else
            step("settle")
        end

    elseif phase == "settle" and clock > 0.5 then
        expect("T2_back_to_back_changes_are_never_missed",
            "entered four|entered three|entered two|exited one")
        step("staying")

    elseif phase == "staying" and clock > 1 then
        expect("T3_nothing_while_nothing_changes", "")
        commands:entity(z.main:id()):remove("collision_trigger")
        step("removed")

    elseif phase == "removed" and not z.main:has("Sensor3d") and not z.main:has("CollidingEntities3d")
        and not z.main:has("ActiveEvents3d") and not z.main:has("ActiveCollisionTypes3d") then
        suite.assert_test("T4_removing_the_trigger_removes_what_it_added", true, "")
        commands:entity(z.spare:id()):despawn()
        step("despawned")

    elseif phase == "despawned" and clock > 0.5 and not z.spare then
        suite.assert_test("T5_a_despawned_trigger_leaves_nothing_behind", true, "")
        commands:spawn({
            Transform = { translation = { x = 200, y = 0, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { ball = { radius = 1.0 } },
            CollidingEntities3d = {},
            collision_trigger = {},
            ["zz/zone"] = { name = "carried" },
            ["zz/carried"] = {},
            ["core/net/sync"] = false,
        })
        body(commands, 200, "zz/probe", { name = "five" })
        step("carried")

    elseif phase == "carried" and z.carried and z.carried:has("Sensor3d") and z.carried:has("ActiveEvents3d")
        and #(z.carried:get("CollidingEntities3d") or {}) == 1
        and #(z.carried:get("collision_trigger").inside or {}) == 1 then
        suite.assert_test("T6_an_entity_with_its_own_list_gets_the_other_two", true, "")
        -- Let the first writes settle: the case below counts only the reload's.
        step("carried settled")

    elseif phase == "carried settled" and clock > 0.5 then
        log, rewrites, reloads = {}, 0, 0
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/collision_trigger/shared/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloading")

    elseif phase == "reloading" and reloads > 0 then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 then
        local list = z.carried:get("CollidingEntities3d") or {}
        local inside = z.carried:get("collision_trigger").inside or {}
        suite.assert_test("T7_it_keeps_its_list_through_a_reload", #list == 1 and #inside == 1,
            string.format("list %d inside %d", #list, #inside))
        expect("T7_and_nothing_reads_as_exited", "")
        suite.assert_test("T8_a_reload_writes_none_of_the_four", rewrites == 0, "writes " .. rewrites)
        -- A body the server moves by its Transform, as a player's is there, into a fixed trigger.
        zone(commands, 300, "kinematic")
        commands:spawn({
            Transform = { translation = { x = 310, y = 0, z = 0 } },
            RigidBody3d = "KinematicPositionBased",
            Collider3d = { ball = { radius = 0.15 } },
            ["zz/probe"] = { name = "walker" },
            ["core/net/sync"] = false,
        })
        step("kinematic")

    elseif phase == "kinematic" and z.kinematic and z.kinematic:has("Sensor3d") and clock > 0.5 then
        log = {}
        move(world, "walker", 300)
        step("walked")

    elseif phase == "walked" and clock > 0.5 then
        expect("T9_a_kinematic_body_moved_into_a_fixed_trigger_enters_it", "entered walker")
        phase = "done"
        suite.finish("CollisionTriggerSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("T0_reached_" .. phase, false, "log: " .. table.concat(log, "|"))
        phase = "done"
        suite.finish("CollisionTriggerSuite")
    end
end):in_set("zz/collision_trigger_suite")
