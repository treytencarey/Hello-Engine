-- --host (windowed: a headless run has no StandardMaterial assets)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local Assets = require("bevy::asset::Assets")
local StandardMaterial = require("bevy::pbr::StandardMaterial")

local suite = helpers.create_suite("ProjectileClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

-- What was drawn is read back from Bevy: the mesh's bounds (`Aabb`, which Bevy computes from
-- the mesh) and the material behind the ball's handle.
local function shot(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/shot" },
        optional = { "projectile", "Mesh3d", "MeshMaterial3d<StandardMaterial>", "Aabb", "RigidBody3d", "projectile/flying", "cooldown/left" },
    })) do
        if e:get("zz/shot").name == name then
            return e
        end
    end
end

local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-3 end
-- an icosphere's vertices reach its radius at the poles, and within 1% of it around them
local function near_radius(a, r) return a ~= nil and math.abs(a - r) <= 0.01 * r end

--- What a shot was drawn with: its mesh's half extents and its material's colors (a `Color`
--- reads as its variant: `{ Srgba = { <Srgba> } }`).
local function drawn(materials, e)
    local bounds = (e:get("Aabb") or {}).half_extents
    local handle = e:get("MeshMaterial3d<StandardMaterial>")
    local material = handle and materials:get(handle)
    local base = material and ((material.base_color or {}).Srgba or {})[1]
    return bounds, base, material and material.emissive or {}
end

local phase, clock = "spawn", 0

-- The suite's clock is the mods': Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Res[Assets[StandardMaterial]], Commands }, function(world, time, materials, commands)
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
        local bounds, base, emissive = drawn(materials, ball)
        suite.assert_test("C1_it_is_drawn_as_a_sphere_of_its_radius",
            ball:get("Mesh3d") ~= nil and bounds ~= nil
                and near_radius(bounds.x, 0.7) and near_radius(bounds.y, 0.7) and near_radius(bounds.z, 0.7),
            bounds and string.format("half extents %.3f %.3f %.3f", bounds.x, bounds.y, bounds.z) or "no bounds")
        suite.assert_test("C2_it_glows_in_its_color",
            ball:get("MeshMaterial3d<StandardMaterial>") ~= nil and base ~= nil and near(base.green, 0.8)
                and near(emissive.green, 0.8),
            string.format("base %s emissive %s", tostring(base and base.green), tostring(emissive.green)))
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
        commands:spawn({
            ["zz/shot"] = { name = "bare" },
            ["core/net/sync"] = false,
            projectile = { from = { x = -5, y = 5, z = 0 }, gravity = 0 },
        })
        step("bare")

    -- Its draw lands after the system that makes it: wait for it (at most 2 s).
    elseif phase == "bare" then
        local bare = shot(world, "bare")
        -- Bevy computes the mesh's bounds a schedule after the mesh lands: wait for those too
        if not (bare and bare:has("Mesh3d") and bare:has("Aabb")) and clock < 2 then return end
        local bounds, base = drawn(materials, bare or { get = function() end })
        suite.assert_test("C6_missing_radius_and_color_are_drawn_with_the_defaults",
            bare ~= nil and bare:has("Mesh3d") and bounds ~= nil and near_radius(bounds.x, 0.2)
                and near_radius(bounds.y, 0.2) and near_radius(bounds.z, 0.2)
                and base ~= nil and near(base.red, 1) and near(base.green, 0.3),
            string.format("bounds %s base %s,%s", bounds and string.format("%.3f", bounds.y) or "nil",
                tostring(base and base.red), tostring(base and base.green)))
        phase = "done"
        suite.finish("ProjectileClientSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ProjectileClientSuite")
    end
end):in_set("zz/projectile_client_suite")
