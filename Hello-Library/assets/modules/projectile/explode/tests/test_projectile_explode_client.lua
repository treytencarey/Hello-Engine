-- --host
-- `projectile/explode` on a client, headless, with physics: a client reacts to its own copy's
-- hit at once, and leaves the end to the server.
--
--   C1 it flies through its caster and, on the next thing it enters, shows its own explosion
--      there (never synced)
--   C2 the ball is hidden and marked `projectile/explode/hit`
--   C3 the client does not despawn the ball: the server ends it
--   C4 it reacts once: the hidden ball flies on until the server ends it, and what it
--      enters next shows nothing
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("ProjectileExplodeClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        -- A caster 2 m along +X, in the way, and a wall behind it.
        commands:spawn({
            ["zz/caster"] = {},
            Transform = { translation = { x = 2, y = 50, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 0.5, hy = 1, hz = 1 } },
            ["core/net/sync"] = false,
        })
        commands:spawn({
            Transform = { translation = { x = 6, y = 50, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 0.5, hy = 5, hz = 5 } },
            ["core/net/sync"] = false,
        })
        -- A second wall, 2 m on: the hidden ball reaches it before the server would end it.
        commands:spawn({
            Transform = { translation = { x = 8, y = 50, z = 0 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 0.5, hy = 5, hz = 5 } },
            ["core/net/sync"] = false,
        })
        step("fire")

    elseif phase == "fire" then
        local caster = world:query({ with = { "zz/caster" } })[1]
        if not caster then return end
        commands:spawn({
            ["zz/ball"] = {},
            projectile = { from = { x = 0, y = 50, z = 0 }, velocity = { x = 4, y = 0, z = 0 },
                           gravity = 0, lifetime = 30, radius = 0.2 },
            ["projectile/explode"] = { radius = 1, duration = 5 },
            ["projectile/caster"] = { entity = caster:id() },
        })
        step("hit")

    elseif phase == "hit" then
        local blasts = world:query({ with = { "explosion" }, optional = { "core/net/sync" } })
        if #blasts == 0 and clock < 3 then return end
        local x = blasts[1] and blasts[1]:get("explosion") or {}
        local at = x.at or {}
        -- The wall's face is at x = 5.5; the caster's is at x = 1.5.
        suite.assert_test("C1_it_shows_its_own_explosion_past_its_caster",
            #blasts == 1 and math.abs((at.x or 0) - 5.5) < 0.6 and blasts[1]:get("core/net/sync") == nil,
            string.format("blasts=%d at.x=%s", #blasts, tostring(at.x)))
        local ball = world:query({ with = { "zz/ball" }, optional = { "projectile/explode/hit", "Visibility" } })[1]
        suite.assert_test("C2_the_ball_is_hidden_and_marked",
            ball ~= nil and ball:has("projectile/explode/hit") and (ball:get("Visibility") or {}).Hidden == true,
            "visibility=" .. require("modules/core/dkjson.lua").encode(ball and ball:get("Visibility")))
        step("stays")

    elseif phase == "stays" then
        -- Past the second wall's face (x = 7.5), about 0.5 s on.
        if clock < 1.0 then return end
        suite.assert_test("C3_the_client_leaves_the_end_to_the_server",
            #world:query({ with = { "zz/ball" } }) == 1, "")
        local blasts = #world:query({ with = { "explosion" } })
        suite.assert_test("C4_it_reacts_once", blasts == 1, "explosions=" .. blasts)
        suite.finish("PROJECTILE_EXPLODE_CLIENT")
        phase = "done"
    end
end):in_set("zz/projectile_explode_client_suite")
