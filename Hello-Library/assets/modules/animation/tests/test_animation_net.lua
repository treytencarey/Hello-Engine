-- --host
-- `animation` over a real connection: what a character plays is worked out by the side that moves
-- it and played by every other copy. An isolated server world moves a character no client owns,
-- another client's VM walks its own player straight on, and this VM is a third, watching both
-- copies while its own player walks too. A remote copy's velocity, from its synced Transform, jumps
-- about however steadily it walks, so a copy working out its own state would flicker.
--
--   AN1 another client's player, walking steadily, plays one state here for 10 s: walk, at its
--       owner's speed, no clip dropping to 0 and back
--   AN2 a character the server moves, walking steadily, the same
--   AN3 the way each moves against where it faces (the angle a set of directions plays by) reaches
--       this client with what it plays
--   AN4 this client's own player, walking steadily, plays one state for those 10 s too
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("AnimationNetSuite")
local T = suite.assert_test

local PORT = 15195
local DEFAULTS = { srv_ready = false, other_walking = false }
local ts = helpers.shared_state("AnimationNetState", DEFAULTS)
local MODEL = "modules/animation/tests/fixtures/Model"
-- a run clip, so a speed read wrong would show as walk and run taking turns
local ANIM = { model = MODEL, scene = "-Idle.glb#Scene0", offset = { x = 0, y = -0.9, z = 0 },
    clips = { idle = "-Idle.glb#Animation0", walk = "-Walk.glb#Animation0", run = "-Jump.glb#Animation0" },
    walk_speed = 3, run_speed = 6 }
local GROUND = { Transform = { translation = { x = 0, y = -0.5, z = 0 } }, RigidBody3d = "Fixed",
    Collider3d = { cuboid = { hx = 500, hy = 0.5, hz = 500 } }, ["core/net/sync"] = false }
-- Two places to start, so the two players do not stand in each other.
local POINTS = { { name = "zz_a", x = 0 }, { name = "zz_b", x = 6 } }

helpers.make_fixture("modules/test_fixtures/gen_animation_net_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("AnimationNetState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server", name = "zzan", port = boot.PORT },
        ["core/net"] = { mode = "server", name = "zzan", port = boot.PORT }, ["core/net/sync"] = false })
    commands:spawn(boot.GROUND)
    -- a character no client owns, as `ai/spawner` makes one: the server moves it
    commands:spawn({ movement = {}, animation = boot.ANIM, Transform = { translation = { x = 0, y = 1, z = 20 } },
        RigidBody3d = "Dynamic", Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } }, LockedAxes3d = "ROTATION_LOCKED",
        ["zz/npc"] = {},
        ["core/net/sync"] = { Transform = { authority = "server", reliable = false }, RigidBody3d = { authority = "server" },
            Collider3d = { authority = "server" }, LockedAxes3d = { authority = "server" }, ["zz/npc"] = { authority = "server" } } })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    for _, p in ipairs(boot.POINTS) do
        commands:spawn({ Name = p.name, Transform = { translation = { x = p.x, y = 0, z = 0 } }, ["player/spawner/point"] = {},
            ["core/net/sync"] = false })
    end
end)
-- as a world's spawn half gives its players their model
app:add_systems(First, { Query[{ added = { "player" } }], Commands }, function(players, commands)
    local anim = boot.ANIM
    for _, p in ipairs(players:iter()) do
        commands:entity(p:id()):entry("animation"):or_default():and_modify(function(a)
            for k, v in pairs(anim) do a[k] = v end
        end)
        commands:entity(p:id()):entry("movement"):or_default():and_modify(function(m) m.speed = 2 end)
    end
end)
app:add_systems(Update, { Query[{ with = { "zz/npc", Mut["Velocity3d"] } }] }, function(bodies)
    for _, e in ipairs(bodies:iter_mut()) do e:patch({ Velocity3d = { linvel = { x = 2 } } }) end
    ts.srv_ready = true
end)
]=])

-- Another client: once its player is here, it walks straight on, KeyW held.
helpers.make_fixture("modules/test_fixtures/gen_animation_net_other.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("AnimationNetState", boot.DEFAULTS)
local started, frames = false, 0
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn(boot.GROUND)
    for _, p in ipairs(boot.POINTS) do
        commands:spawn({ Name = p.name, Transform = { translation = { x = p.x, y = 0, z = 0 } }, ["player/spawner/point"] = {},
            ["core/net/sync"] = false })
    end
end)
app:add_systems(Update, { World, Commands }, function(world, commands)
    if not started and ts.srv_ready then
        started = true
        commands:spawn({ ["core/world/net"] = { mode = "client", name = "zzan_o", ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzan_o", ip = "127.0.0.1", port = boot.PORT }, ["core/net/sync"] = false })
    end
    for _, n in ipairs(world:query({ with = { "core/net", "core/net/owns" } })) do
        if #(n:get("core/net/owns") or {}) > 0 then
            frames = frames + 1
            if frames == 30 then world:write_message("input/synthetic_key", { key_code = "KeyW", state = "Pressed" }) end
            if frames > 60 then ts.other_walking = true end
        end
    end
end)
]=])

helpers.spawn_vm("modules/test_fixtures/gen_animation_net_server.lua",
    { DEFAULTS = DEFAULTS, PORT = PORT, GROUND = GROUND, ANIM = ANIM, POINTS = POINTS }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_animation_net_other.lua",
    { DEFAULTS = DEFAULTS, PORT = PORT, GROUND = GROUND, POINTS = POINTS }, { headless = true })

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn(GROUND)
    for _, p in ipairs(POINTS) do
        commands:spawn({ Name = p.name, Transform = { translation = { x = p.x, y = 0, z = 0 } }, ["player/spawner/point"] = {},
            ["core/net/sync"] = false })
    end
end)

local phase, t, mark = "wait", 0, 0
local seen = {}

--- This client's own player.
local function mine(world)
    for _, n in ipairs(world:query({ with = { "core/net", "core/net/owns" } })) do
        local p = world:query({ with = { "player" }, iter_many = n:get("core/net/owns") })[1]
        if p ~= nil then return p end
    end
end

--- What a character plays this frame, counted: its state changes, its clips dropping to 0 and back.
local function watch(world, who, e)
    local s = seen[who] or { changes = 0, drops = 0, frames = 0, angled = 0, weights = {}, dropped = {} }
    seen[who] = s
    if e == nil then return end
    local full = world:get_entity(e:id())
    local playing = full:get("animation/playing")
    s.frames = s.frames + 1
    if playing ~= nil and playing.angle ~= nil then s.angled = s.angled + 1 end
    if playing ~= nil and s.state ~= nil and playing.state ~= s.state then s.changes = s.changes + 1 end
    s.state = playing and playing.state
    s.speed = playing and playing.speed
    local model = world:query({ iter_many = full:get("Children") or {}, with = { "animation/model", "animation/clip" } })[1]
    for clip, w in pairs(model and model:get("animation/clip").clips or {}) do
        local was = s.weights[clip]
        if was ~= nil and was > 0 and w == 0 then s.dropped[clip] = true end
        if s.dropped[clip] and w > 0 then s.dropped[clip] = nil; s.drops = s.drops + 1 end
        s.weights[clip] = w
    end
end

local function steady(name, s)
    T(name, s ~= nil and s.frames > 0 and s.changes == 0 and s.drops == 0 and s.state == "walk",
        s and string.format("%d changes, %d drops, playing %s at %s", s.changes, s.drops, tostring(s.state), tostring(s.speed)) or "not seen")
end

app:add_systems(Update, { World, Commands }, function(world, commands)
    t = t + world:delta_time()
    local since = t - mark
    if phase == "wait" and ts.srv_ready then
        commands:spawn({ ["core/world/net"] = { mode = "client", name = "zzan_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzan_c", ip = "127.0.0.1", port = PORT }, ["core/net/sync"] = false })
        phase, mark = "connecting", t
    elseif phase == "connecting" and ts.other_walking and mine(world) ~= nil and #world:query({ with = { "player" } }) >= 2 then
        world:write_message("input/synthetic_key", { key_code = "KeyW", state = "Pressed" })
        phase, mark = "warm", t
    elseif phase == "warm" and since > 2 then
        seen = {}
        phase, mark = "measure", t
    elseif phase == "measure" then
        local me = mine(world)
        for _, p in ipairs(world:query({ with = { "player" } })) do
            if me == nil or p:id() ~= me:id() then watch(world, "remote", p) end
        end
        watch(world, "npc", world:query({ with = { "zz/npc" } })[1])
        watch(world, "own", me)
        if since > 10 then
            steady("AN1_another_client_s_player_plays_one_state_walking_steadily", seen.remote)
            steady("AN2_a_character_the_server_moves_plays_one_state_walking_steadily", seen.npc)
            T("AN3_the_angle_each_moves_at_reaches_this_client", seen.remote and seen.npc and seen.remote.angled == seen.remote.frames
                and seen.npc.angled == seen.npc.frames and seen.npc.frames > 0,
                string.format("remote %s/%s, npc %s/%s", tostring(seen.remote and seen.remote.angled), tostring(seen.remote and seen.remote.frames),
                    tostring(seen.npc and seen.npc.angled), tostring(seen.npc and seen.npc.frames)))
            steady("AN4_this_client_s_own_player_plays_one_state_walking_steadily", seen.own)
            phase = "done"
            suite.finish("AnimationNetSuite")
        end
    end
    if phase ~= "done" and since > 40 then
        T("AN0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("AnimationNetSuite")
    end
end):in_set("zz/animation_net")
