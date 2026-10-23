-- --host (windowed: a headless run has no StandardMaterial assets)
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ProjectileClientSuite")
local Time = require("bevy::time::Time")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

-- Asset contents cannot be read back, so record each request; the real call is still made.
local made = {}
local real_create_asset = create_asset
create_asset = function(type_path, fields)
    made[#made + 1] = { type_path = type_path, fields = fields }
    return real_create_asset(type_path, fields)
end

local function shot(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/shot" },
        optional = { "projectile", "Mesh3d", "MeshMaterial3d<StandardMaterial>", "RigidBody3d", "projectile/flying", "cooldown/left" },
    })) do
        if e:get("zz/shot").name == name then
            return e
        end
    end
end

local function near(a, b) return math.abs(a - b) < 1e-3 end

local phase, clock, mark = "spawn", 0, 0

-- The suite's clock is the mods': Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local current = shot(world, "ball")
    local running = ((current and current:get("cooldown/left")) or {})["projectile/flying"]

    if phase == "spawn" then
        commands:spawn({
            ["zz/shot"] = { name = "ball" },
            ["core/net/sync"] = false,
            projectile = {
                lifetime = 0.6,
                from = { x = 0, y = 5, z = 0 },
                velocity = { x = 4, y = 0, z = 0 },
                gravity = 0,
                radius = 0.7,
                color = { r = 0.1, g = 0.8, b = 0.2 },
            },
        })
        step("drawn")

    -- The lifetime timer starts a frame or two after the spawn, which the first, long frames
    -- stretch: wait for it to run, within the 0.6 s lifetime.
    elseif phase == "drawn" and clock > 0.3 and ((running or 1) < 0.6 or clock > 1.0) then
        local ball = shot(world, "ball")
        local mesh, material
        for _, m in ipairs(made) do
            if m.type_path == "bevy_mesh::mesh::Mesh" then mesh = m.fields end
            if m.type_path == "bevy_pbr::pbr_material::StandardMaterial" then material = m.fields end
        end
        suite.assert_test("C1_it_is_drawn_as_a_sphere_of_its_radius",
            ball:get("Mesh3d") ~= nil and mesh ~= nil and near(mesh.primitive.Sphere.radius, 0.7), "")
        suite.assert_test("C2_it_glows_in_its_color",
            ball:get("MeshMaterial3d<StandardMaterial>") ~= nil and material ~= nil
                and near(material.base_color.g, 0.8) and near(material.emissive.g, 0.8), "")
        local pos = world:get_entity(ball:id()).GlobalTransform:compute_transform().translation
        local left = ball:get("cooldown/left")
        suite.assert_test("C3_the_client_flies_it_and_runs_its_lifetime_from_its_launch_state",
            ball:has("RigidBody3d") and pos.x > 0.8 and math.abs(pos.y - 5) < 0.01
                and ball:has("projectile/flying") and left ~= nil and left["projectile/flying"] < 0.6,
            string.format("at %.2f %.2f", pos.x, pos.y))
        step("lifetime over")

    elseif phase == "lifetime over" and clock > 0.6
        and (not current or not current:has("projectile/flying") or clock > 2) then
        local ball = shot(world, "ball")
        suite.assert_test("C5_the_lifetime_ends_on_the_client_but_only_the_server_despawns",
            ball ~= nil and not ball:has("projectile/flying"), "")
        ball:patch({ cooldown = { ["projectile/flying"] = { remaining = 5 } } })
        ball:remove("projectile")
        step("undrawn")

    elseif phase == "undrawn" and clock > 0.3 then
        local ball = shot(world, "ball")
        suite.assert_test("C4_removing_projectile_takes_off_the_mesh_material_body_and_timer",
            ball ~= nil and not ball:has("Mesh3d") and not ball:has("MeshMaterial3d<StandardMaterial>")
                and not ball:has("RigidBody3d") and not ball:has("projectile/flying"), "")
        -- One that comes without a radius or a color is drawn with the defaults.
        mark = #made
        commands:spawn({
            ["zz/shot"] = { name = "bare" },
            ["core/net/sync"] = false,
            projectile = { from = { x = -5, y = 5, z = 0 }, gravity = 0 },
        })
        step("bare")

    -- Its draw lands after the system that makes it: wait for it (at most 2 s).
    elseif phase == "bare" then
        local bare = shot(world, "bare")
        if not (bare and bare:has("Mesh3d")) and clock < 2 then return end
        local mesh, material
        for i = mark + 1, #made do
            local m = made[i]
            if m.type_path == "bevy_mesh::mesh::Mesh" then mesh = m.fields end
            if m.type_path == "bevy_pbr::pbr_material::StandardMaterial" then material = m.fields end
        end
        suite.assert_test("C6_missing_radius_and_color_are_drawn_with_the_defaults",
            bare ~= nil and bare:has("Mesh3d") and mesh ~= nil and near(mesh.primitive.Sphere.radius, 0.2)
                and material ~= nil and near(material.base_color.r, 1) and near(material.base_color.g, 0.3), "")
        phase = "done"
        suite.finish("ProjectileClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ProjectileClientSuite")
    end
end):in_set("zz/projectile_client_suite")
