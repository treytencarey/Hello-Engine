-- --host (windowed: a headless run has no StandardMaterial assets)
-- `explosion` on a client.
--
--   XC1 it is drawn: a sphere mesh with a glowing material of its color
--   XC2 it grows toward its radius while it burns
--   XC3 taken off an entity that stays: the mesh and material go
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ExplosionClientSuite")

spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/blast" },
        optional = { "explosion", "Mesh3d", "MeshMaterial3d<StandardMaterial>", "Transform" },
    })) do
        if e:get("zz/blast").name == name then return e end
    end
end

local function scale(e) return ((e and e:get("Transform") or {}).scale or {}).x or 0 end

local phase, clock = "spawn", 0
local early

register_system("Update", function(world)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        spawn({ ["zz/blast"] = { name = "big" }, explosion = { radius = 4, duration = 2 } })
        step("drawn")

    elseif phase == "drawn" then
        if clock < 0.3 then return end
        local big = named(world, "big")
        suite.assert_test("XC1_it_is_drawn",
            big ~= nil and big:has("Mesh3d") and big:has("MeshMaterial3d<StandardMaterial>"), "")
        early = scale(big)
        step("grown")

    elseif phase == "grown" then
        if clock < 0.8 then return end
        local big = named(world, "big")
        local now = scale(big)
        suite.assert_test("XC2_it_grows_toward_its_radius", early > 0 and now > early and now < 4,
            string.format("scale %.2f then %.2f", early, now))
        world:get_entity(big:id()):patch({ explosion = null })
        step("removed")

    elseif phase == "removed" then
        if clock < 0.3 then return end
        local big = named(world, "big")
        suite.assert_test("XC3_taken_off_the_mesh_and_material_go",
            big ~= nil and not big:has("Mesh3d") and not big:has("MeshMaterial3d<StandardMaterial>"), "")
        suite.finish("EXPLOSION_CLIENT")
        for _, w in ipairs(world:query({ with = { "Window" } })) do despawn(w:id()) end
        phase = "done"
    end
end, { label = "ExplosionClientSuite" })
