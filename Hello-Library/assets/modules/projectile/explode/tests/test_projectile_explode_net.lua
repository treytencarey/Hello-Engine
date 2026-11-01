-- --host (windowed: an isolated server world needs one)
-- `projectile/explode` over a real connection: an isolated server world fires exploding
-- projectiles at a wall, as `abilities/fireball` does, and this VM is a client of it. Each
-- side has the wall, as a map gives each side its ground.
--
--   N1 every shot the server ends on the wall shows an explosion on the client
--
-- Per shot it prints, on the client, when its copy appeared, when its sensor was ready, when
-- `collision_trigger` first fired, when explode reacted and when the server's despawn arrived
-- (seconds after the copy appeared), with the copy's z then. The wall's face is z = -9.5.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ProjectileExplodeNetSuite")
local T = suite.assert_test

local PORT = 15161
local SHOTS = 6

local DEFAULTS = { srv_ready = false, srv_fired = 0, srv_ends = 0, go_fire = false }
local ts = helpers.shared_state("ProjectileExplodeNetState", DEFAULTS)

-- The wall, as each side spawns it.
local WALL = {
    Transform = { translation = { x = 0, y = 50, z = -10 } },
    RigidBody3d = "Fixed",
    Collider3d = { cuboid = { hx = 5, hy = 5, hz = 0.5 } },
    ["core/net/sync"] = false,
}

-- ═══ The server: an isolated world that fires ═══════════════════════════
helpers.make_fixture("modules/test_fixtures/gen_projectile_explode_net_vm1.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")

local boot = Instances.boot_data()
local DEFAULTS = boot.DEFAULTS
local PORT = boot.PORT
local WALL = boot.WALL
local SHOTS = boot.SHOTS
local ts = helpers.shared_state("ProjectileExplodeNetState", DEFAULTS)
local shooter
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzpen", port = PORT },
        ["core/net"] = { mode = "server", name = "zzpen", port = PORT },
        ["core/net/sync"] = false,
    })
    commands:spawn(WALL)
    shooter = commands:spawn({ ["zz/shooter"] = { v = 1 }, Transform = { translation = { x = 0, y = 49, z = 0 } },
                               ["core/net/sync"] = { ["zz/shooter"] = {} } }):id()
end)
local clock, last = 0, -10
app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + world:delta_time()
    if not ts.srv_ready then ts.srv_ready = true end
    if ts.go_fire and ts.srv_fired < SHOTS and clock - last >= 1.0 then
        last = clock
        ts.srv_fired = ts.srv_fired + 1
        commands:spawn({
            ["abilities/projectile"] = { at = { x = 0, y = 50, z = 0 }, yaw = 0, pitch = 0, speed = 25,
                                         radius = 0.25, gravity = 0, lifetime = 5,
                                         color = { r = 1, g = 0.3, b = 0.1 } },
            ["projectile/explode"] = { radius = 1.5, color = { r = 1, g = 0.3, b = 0.1 } },
            ["projectile/caster"] = { entity = shooter },
            ["core/net/sync"] = { ["projectile/caster"] = { authority = "server" } },
        })
    end
    -- Its own explosions: the ball that hit is despawned in the same frame.
    ts.srv_ends = ts.srv_ends + #world:query({ added = { "explosion" } })
end):in_set("zz/explode_net_server")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_projectile_explode_net_vm1.lua", { DEFAULTS = DEFAULTS, PORT = PORT, WALL = WALL, SHOTS = SHOTS })

-- ═══ The client: this VM ════════════════════════════════════════════════
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn(WALL)
end)

local t, frame = 0, 0
local shots = {}          -- the client's copies, in the order they appeared, each naming its entity
local explosions = 0
local phase, mark = "wait_srv", 0

local function z_of(world, e)
    local ok, tr = pcall(function()
        return world:get_entity(e).GlobalTransform:compute_transform().translation
    end)
    return ok and tr and tr.z or nil
end

app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    frame = frame + 1

    -- The trace: every edge of each copy, as it happens.
    for _, e in ipairs(world:query({ added = { "projectile/explode" }, with = { "core/net/id" } })) do
        shots[#shots + 1] = { entity = e:id(), seen = t, seen_frame = frame }
    end
    for _, e in ipairs(world:query({ with = { "projectile/explode", "Sensor3d" } })) do
        for _, r in ipairs(shots) do
            if r.entity == e:id() and not r.sensor then r.sensor = t; r.sensor_z = z_of(world, e:id()) end
        end
    end
    for _, e in ipairs(world:query({ changed = { "collision_trigger" }, with = { "projectile/explode" } })) do
        local entered = e:get("collision_trigger").entered or {}
        for _, r in ipairs(shots) do
            if r.entity == e:id() and #entered > 0 and not r.trigger then r.trigger = t; r.trigger_z = z_of(world, e:id()) end
        end
    end
    for _, e in ipairs(world:query({ added = { "projectile/explode/hit" } })) do
        for _, r in ipairs(shots) do
            if r.entity == e:id() then r.hit = t end
        end
    end
    for _, r in ipairs(shots) do
        if not r.gone then
            local z = z_of(world, r.entity)
            if z then r.last_z = z end
        end
    end
    for _, e in ipairs(world:query({ removed = { "projectile/explode" } })) do
        for _, r in ipairs(shots) do
            if r.entity == e:id() and not r.gone then r.gone = t end
        end
    end
    explosions = explosions + #world:query({ added = { "explosion" } })

    if phase == "wait_srv" then
        if not ts.srv_ready and t < 15 then return end
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzpen_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzpen_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        phase, mark = "wait_conn", t
        return
    end

    if phase == "wait_conn" then
        -- Connected once the server's shooter has replicated here.
        if #world:query({ with = { "zz/shooter" } }) == 0 and t - mark < 15 then return end
        ts.go_fire = true
        phase, mark = "firing", t
        return
    end

    if phase == "firing" then
        local done = ts.srv_fired >= SHOTS and #shots >= SHOTS
        for _, r in ipairs(shots) do if not r.gone then done = false end end
        if not done and t - mark < 20 then return end
        local function rel(r, k) return r[k] and string.format("%.3f", r[k] - r.seen) or "-" end
        local function z(v) return v and string.format("%.2f", v) or "-" end
        for i, r in ipairs(shots) do
            print(string.format(
                "[ZZTRACE] shot %d: seen(frame %d) sensor=+%s(z %s) trigger=+%s(z %s) hit=+%s despawn=+%s last_z=%s",
                i, r.seen_frame, rel(r, "sensor"), z(r.sensor_z), rel(r, "trigger"), z(r.trigger_z),
                rel(r, "hit"), rel(r, "gone"), z(r.last_z)))
        end
        print(string.format("[ZZTRACE] server fired %d, ended %d on a hit; client copies %d, client explosions %d",
            ts.srv_fired, ts.srv_ends, #shots, explosions))
        T("N1_every_shot_the_server_ends_shows_an_explosion_on_the_client",
            ts.srv_ends == SHOTS and explosions == SHOTS,
            string.format("server ends=%d client explosions=%d of %d", ts.srv_ends, explosions, SHOTS))
        suite.finish("PROJECTILE_EXPLODE_NET")
        phase = "done"
    end
end):in_set("zz/explode_net_client")
