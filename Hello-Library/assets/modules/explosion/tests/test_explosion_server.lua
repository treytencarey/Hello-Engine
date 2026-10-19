-- --host
-- `explosion` on the server, headless.
--
--   X1 missing fields get defaults
--   X2 it is placed at `at`
--   X3 it burns (`explosion/burning`) for its duration, and despawns itself at the end
--   X4 taken off an entity that stays: its timer stops
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ExplosionServerSuite")

spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })

local function named(world, name)
    for _, e in ipairs(world:query({ with = { "zz/blast" }, optional = { "explosion", "explosion/burning", "cooldown" } })) do
        if e:get("zz/blast").name == name then return e end
    end
end

local phase, clock = "spawn", 0

register_system("Update", function(world)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        spawn({ ["zz/blast"] = { name = "short" }, explosion = { at = { x = 3, y = 4, z = 5 }, duration = 0.5 } })
        spawn({ ["zz/blast"] = { name = "long" }, explosion = { duration = 30 } })
        step("burning")

    elseif phase == "burning" then
        if clock < 0.2 then return end
        local short = named(world, "short")
        local x = short and short:get("explosion") or {}
        suite.assert_test("X1_missing_fields_get_defaults",
            x.radius == 1.5 and x.duration == 0.5 and x.color ~= nil, "radius=" .. tostring(x.radius))
        local t = world:call_component_method(short:id(), "GlobalTransform", "compute_transform").translation
        suite.assert_test("X2_placed_at_its_point",
            math.abs(t.x - 3) < 1e-3 and math.abs(t.y - 4) < 1e-3 and math.abs(t.z - 5) < 1e-3, "")
        suite.assert_test("X3a_it_burns", short:has("explosion/burning"), "")
        step("ended")

    elseif phase == "ended" then
        if clock < 0.6 then return end
        suite.assert_test("X3b_it_despawns_itself_when_it_ends", named(world, "short") == nil, "")
        world:get_entity(named(world, "long"):id()):patch({ explosion = null })
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
end, { label = "ExplosionServerSuite" })
