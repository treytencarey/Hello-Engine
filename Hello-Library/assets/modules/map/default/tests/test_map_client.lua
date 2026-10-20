-- --host (windowed: a headless run has no StandardMaterial assets)
local Quat = require("bevy::math::Quat")

require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("MapClientSuite")

spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })

-- Asset contents cannot be read back, so record each request; the real call is still made.
local made = {}
local real_create_asset = create_asset
create_asset = function(type_path, fields)
    made[#made + 1] = { type_path = type_path, fields = fields }
    return real_create_asset(type_path, fields)
end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "map/default", "RigidBody3d", "Mesh3d", "MeshMaterial3d<StandardMaterial>" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function suns(world, map)
    return world:query({ entities = { map:id() }, with = { "map/default/sun", "DirectionalLight" } })
end

local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-3) end

local phase, clock = "spawn", 0

register_system("Update", function(world)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        spawn({
            ["zz/name"] = { name = "map" },
            ["map/default"] = { size = { x = 10, y = 1, z = 6 }, color = { r = 0.1, g = 0.2, b = 0.9 }, sun = 5000 },
            ["core/net/sync"] = false,
        })
        -- A second map keeps the mod loaded when the first loses its component, so the
        -- first's sun has to go by this mod's removal, not by the mod unloading.
        spawn({ ["zz/name"] = { name = "other" }, ["map/default"] = {}, ["core/net/sync"] = false })
        spawn({
            ["zz/name"] = { name = "ball" },
            Transform = { translation = { x = 0, y = 2, z = 0 } },
            RigidBody3d = "Dynamic",
            Collider3d = { ball = { radius = 0.5 } },
        })
        step("drawn")

    elseif phase == "drawn" and clock > 2.0 then
        local map = named(world, "map")
        local mesh, material
        for _, m in ipairs(made) do
            -- the first map's, not the second's (default size and color)
            if m.type_path == "bevy_mesh::mesh::Mesh" and m.fields.primitive.Cuboid.half_size.x ~= 50 then mesh = m.fields end
            if m.type_path == "bevy_pbr::pbr_material::StandardMaterial" and m.fields.base_color.b ~= 0.3 then material = m.fields end
        end
        suite.assert_test("C1_the_ground_is_drawn_as_a_box_of_its_size_in_its_color",
            map:has("Mesh3d") and map:has("MeshMaterial3d<StandardMaterial>") and mesh ~= nil and material ~= nil
                and near(mesh.primitive.Cuboid.half_size.x, 5) and near(mesh.primitive.Cuboid.half_size.z, 3)
                and near(material.base_color.b, 0.9), "")
        local sun = suns(world, map)[1]
        local down = sun and Quat.mul_vec3(world:call_component_method(sun:id(), "GlobalTransform", "compute_transform").rotation,
            { x = 0, y = 0, z = -1 })
        suite.assert_test("C2_the_sun_shines_down_at_its_strength",
            sun ~= nil and sun:get("DirectionalLight").illuminance == 5000 and down.y < -0.3,
            string.format("down.y=%s", tostring(down and down.y)))
        local y = world:call_component_method(named(world, "ball"):id(), "GlobalTransform", "compute_transform").translation.y
        suite.assert_test("C3_the_client_builds_the_ground_too", near(y, 1.0, 0.05), string.format("y=%.3f", y))
        made = {}
        map:patch({ ["map/default"] = { sun = 2000, color = { r = 0.9, g = 0.1, b = 0.1 } } })
        step("changed")

    elseif phase == "changed" and clock > 0.3 then
        local map = named(world, "map")
        local list = suns(world, map)
        local material
        for _, m in ipairs(made) do
            if m.type_path == "bevy_pbr::pbr_material::StandardMaterial" then material = m.fields end
        end
        suite.assert_test("C5_a_change_relights_the_same_sun_and_redraws_the_box",
            #list == 1 and list[1]:get("DirectionalLight").illuminance == 2000
                and material ~= nil and near(material.base_color.r, 0.9), "suns=" .. #list)
        map:remove("map/default")
        step("undrawn")

    elseif phase == "undrawn" and clock > 0.3 then
        local map = named(world, "map")
        suite.assert_test("C4_removing_map_default_takes_off_the_box_and_the_sun",
            map ~= nil and not map:has("Mesh3d") and not map:has("MeshMaterial3d<StandardMaterial>") and #suns(world, map) == 0
                and #suns(world, named(world, "other")) == 1, "")
        phase = "done"
        suite.finish("MapClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("MapClientSuite")
    end
end, { label = "MapClientSuite" })
