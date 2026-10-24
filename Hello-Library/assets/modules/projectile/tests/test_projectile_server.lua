-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ProjectileServerSuite")
local Time = require("bevy::time::Time")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function shot(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/shot" },
        optional = { "projectile", "RigidBody3d", "Collider3d", "GravityScale3d", "Velocity3d", "projectile/flying" },
    })) do
        if e:get("zz/shot").name == name then
            return e
        end
    end
end

local function at(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform().translation
end

local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-3) end

local phase, clock = "spawn", 0
local flown

-- The suite's clock is the mods': Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            ["zz/shot"] = { name = "level" },
            ["core/net/sync"] = false,
            projectile = { from = { x = 0, y = 50, z = 0 }, velocity = { x = 10, y = 0, z = 0 }, gravity = 0, lifetime = 0.8, radius = 0.5 },
        })
        commands:spawn({
            ["zz/shot"] = { name = "falling" },
            ["core/net/sync"] = false,
            projectile = { from = { x = 20, y = 50, z = 0 } },
        })
        commands:spawn({
            ["zz/shot"] = { name = "kept" },
            ["core/net/sync"] = false,
            projectile = { from = { x = -20, y = 50, z = 0 }, lifetime = 5 },
        })
        -- A fixed ball whose top is at y = 0: a projectile dropped on it rests one radius above.
        commands:spawn({
            ["zz/shot"] = { name = "floor" },
            ["core/net/sync"] = false,
            Transform = { translation = { x = 100, y = -10, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { ball = { radius = 10 } },
        })
        commands:spawn({
            ["zz/shot"] = { name = "resting" },
            ["core/net/sync"] = false,
            projectile = { from = { x = 100, y = 2, z = 0 }, radius = 0.5, gravity = 1, lifetime = 5 },
        })
        step("flying")

    elseif phase == "flying" and clock > 0.4 then
        local level, falling = shot(world, "level"), shot(world, "falling")
        local p = falling:get("projectile")
        suite.assert_test("P1_missing_fields_get_defaults",
            p.radius == 0.2 and p.gravity == 0.3 and p.lifetime == 3 and p.color.r == 1
                and p.velocity.x == 0 and p.from.x == 20, "")
        local body = level:get("RigidBody3d")
        suite.assert_test("P2_it_gets_a_dynamic_body", body ~= nil and body.Dynamic == true, "")
        local pos = at(world, level)
        flown = pos.x
        suite.assert_test("P3_it_starts_at_from_and_moves_at_its_velocity_without_gravity",
            pos.x > 2 and near(pos.y, 50, 0.01) and near(pos.z, 0, 0.01),
            string.format("at %.2f %.2f", pos.x, pos.y))
        local drop = 50 - at(world, falling).y
        suite.assert_test("P4_gravity_is_scaled", drop > 0.05 and drop < 0.5,
            string.format("dropped %.3f", drop))
        shot(world, "kept"):remove("projectile")
        step("landed")

    -- The lifetime timer starts a frame or two after the spawn, which the first, long frames
    -- stretch: wait for the end, well before the 3 s lifetime P6 checks.
    elseif phase == "landed" and clock > 0.8 and (shot(world, "level") == nil or clock > 1.5) then
        suite.assert_test("P5_it_is_despawned_when_its_lifetime_ends", shot(world, "level") == nil, "")
        local falling = shot(world, "falling")
        suite.assert_test("P6_a_longer_lifetime_is_still_flying",
            falling ~= nil and falling:has("projectile/flying"), "")
        local kept = shot(world, "kept")
        suite.assert_test("P7_removing_projectile_takes_off_the_body_and_does_not_despawn",
            kept ~= nil and kept:get("RigidBody3d") == nil and kept:get("Collider3d") == nil
                and kept:get("Velocity3d") == nil and kept:get("projectile/flying") == nil, "")
        local rest = at(world, shot(world, "resting")).y
        suite.assert_test("P8_its_collider_is_a_ball_of_its_radius", near(rest, 0.5, 0.05),
            string.format("rests at y=%.3f", rest))
        phase = "done"
        suite.finish("ProjectileServerSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ProjectileServerSuite")
    end
end):in_set("zz/projectile_server_suite")
