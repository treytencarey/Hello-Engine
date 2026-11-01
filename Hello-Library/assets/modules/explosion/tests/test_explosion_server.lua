-- --host
-- `explosion` on the server, headless.
--
--   X1 missing fields get defaults
--   X2 it is placed at `at`
--   X3 it burns (`explosion/burning`) for its duration, and despawns itself at the end
--   X3c one without a duration burns for the default
--   X4 taken off an entity that stays: its timer stops
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ExplosionServerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function named(world, name)
    for _, e in ipairs(world:query({ with = { "zz/blast" }, optional = { "explosion", "explosion/burning", "cooldown" } })) do
        if e:get("zz/blast").name == name then return e end
    end
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["zz/blast"] = { name = "short" }, explosion = { at = { x = 3, y = 4, z = 5 }, duration = 0.5 } })
        commands:spawn({ ["zz/blast"] = { name = "long" }, explosion = { duration = 30 } })
        commands:spawn({ ["zz/blast"] = { name = "bare" }, explosion = { at = { x = -3, y = 0, z = 0 } } })
        step("burning")

    -- Writes land after the system that makes them, and an early frame can take half a
    -- second: wait for the timer to start (at most 2 s) rather than a fixed time.
    elseif phase == "burning" then
        local short = named(world, "short")
        if not (short and short:has("explosion/burning")) and clock < 2 then return end
        local x = short and short:get("explosion") or {}
        suite.assert_test("X1_missing_fields_get_defaults",
            x.radius == 1.5 and x.duration == 0.5 and x.color ~= nil, "radius=" .. tostring(x.radius))
        local t = world:get_entity(short:id()).GlobalTransform:compute_transform().translation
        suite.assert_test("X2_placed_at_its_point",
            math.abs(t.x - 3) < 1e-3 and math.abs(t.y - 4) < 1e-3 and math.abs(t.z - 5) < 1e-3, "")
        suite.assert_test("X3a_it_burns", short:has("explosion/burning"), "")
        -- Spawned with `short`, it starts burning in the same frame.
        local bare = named(world, "bare")
        suite.assert_test("X3c_one_without_a_duration_burns_for_the_default",
            bare ~= nil and bare:has("explosion/burning") and (bare:get("explosion") or {}).duration == 0.4, "")
        step("ended")

    elseif phase == "ended" then
        if clock < 0.6 then return end
        suite.assert_test("X3b_it_despawns_itself_when_it_ends", named(world, "short") == nil, "")
        commands:entity(named(world, "long"):id()):remove("explosion")
        step("removed")

    elseif phase == "removed" then
        if clock < 0.2 then return end
        local long = named(world, "long")
        suite.assert_test("X4_taken_off_its_timer_stops",
            long ~= nil and not long:has("explosion/burning")
                and ((long:get("cooldown") or {})["explosion/burning"]) == nil, "")
        suite.finish("EXPLOSION_SERVER")
        phase = "done"
    end
end):in_set("zz/explosion_server_suite")
