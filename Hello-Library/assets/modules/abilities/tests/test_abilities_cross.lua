-- --host
-- A cast by a player who is mirrored in a linked world, between two worlds, each its own isolated
-- VM, as two worlds of one process are: the source world shares its player with the other over a
-- real peer link, and the press reaches the mirror there. Each world's wall stands at its own
-- distance: world 1's face at z = -11.5, world 2's at z = -3.5, 3 m thick. A ball at 25 m/s
-- is seen inside the wall a frame or so after it meets it.
--
--   X1 a press in world 1 casts there, and the mirror casts in world 2, from the mirror's place
--   X2 each projectile explodes on its own world's wall, once
--   X3 neither world casts twice, and nothing casts back into world 1
--   X4 a second press, after the cooldown, casts again in both worlds
--   X5 a player with no mirror casts in its own world only
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("AbilitiesCrossSuite")
local T = suite.assert_test

local DEFAULTS = {
    s_ready = false, t_mirror = false, press = "",
    s_casts = 0, t_casts = 0, s_booms = 0, t_booms = 0,
    s_boom_z = 0, t_boom_z = 0, t_cast_x = 0,
}
local ts = helpers.shared_state("AbilitiesCrossState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_abilities_cross_s.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("AbilitiesCrossState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server", name = "zzac_s", port = 15531 },
        ["core/net"] = { mode = "server", name = "zzac_s", port = 15531 }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zzac_s_peer", port = 15532, scope_key = "zz:ac:s", world_port = 15531 },
        ["core/net/peer"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/link"] = { name = "zzac_s_to_t", port = 15534, scope_key = "zz:ac:t", server_addr = "127.0.0.1" },
        ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/sync"] = false })
    commands:spawn({ Transform = { translation = { x = 0, y = 1, z = -12 } }, RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 30, hy = 5, hz = 0.5 } }, ["core/net/sync"] = false })
    for _, p in ipairs({ { 41, 3, true }, { 42, 10, false } }) do
        commands:spawn({
            player = { client_id = p[1], spawn_index = 0 },
            Transform = { translation = { x = p[2], y = 0, z = 0 } },
            camera = { yaw = 0, pitch = 0 },
            ["core/net/owner"] = { client_id = p[1] },
            ["core/net/peer/share"] = p[3] and { stable_id = "player_" .. p[1] } or nil,
            ["core/net/sync"] = {
                Transform = { authority = "server", reliable = false },
                camera = { authority = "client", target = "owner" },
            },
            ["core/script/owner"] = false,
            ["zz/ac/player"] = { client_id = p[1] },
        })
    end
end)

app:add_systems(Update, {
    Query[{ with = { "core/net/peer/link/state" } }],
    Query[{
        with = { "zz/ac/player" },
        optional = { "input/game/abilities/fireball", "abilities/fireball" },
    }],
    Query[{ added = { "abilities/projectile" } }],
    Query[{ added = { "explosion" } }],
    Commands,
}, function(links, players, casts, booms, commands)
    local l = links:iter()[1]
    ts.s_ready = l ~= nil and l:get("core/net/peer/link/state").welcomed == true
    for _, _ in ipairs(casts:iter()) do ts.s_casts = ts.s_casts + 1 end
    for _, b in ipairs(booms:iter()) do
        ts.s_booms = ts.s_booms + 1
        ts.s_boom_z = b:get("explosion").at.z
    end
    -- What the net server writes for the owner's press and release.
    local want = ts.press
    for _, p in ipairs(players:iter()) do
        local who = tostring(p:get("zz/ac/player").client_id)
        if want == "down:" .. who and p:has("abilities/fireball") and not p:has("input/game/abilities/fireball") then
            commands:entity(p:id()):insert({ ["input/game/abilities/fireball"] = {} })
        elseif want == "up" and p:has("input/game/abilities/fireball") then
            commands:entity(p:id()):remove("input/game/abilities/fireball")
        end
    end
end):in_set("zz/ac_s")
]=])

helpers.make_fixture("modules/test_fixtures/gen_abilities_cross_t.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("AbilitiesCrossState", boot.DEFAULTS)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server", name = "zzac_t", port = 15533 },
        ["core/net"] = { mode = "server", name = "zzac_t", port = 15533 }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = "zzac_t_peer", port = 15534, scope_key = "zz:ac:t", world_port = 15533 },
        ["core/net/peer"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/accept"] = { components = "all" }, ["core/net/sync"] = false })
    commands:spawn({ Transform = { translation = { x = 0, y = 1, z = -5 } }, RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 30, hy = 5, hz = 1.5 } }, ["core/net/sync"] = false })
end)

app:add_systems(Update, {
    Query[{ with = { "player", "core/net/peer/mirror" }, optional = { "abilities/fireball" } }],
    Query[{ added = { "abilities/projectile" } }],
    Query[{ added = { "explosion" } }],
}, function(mirrors, casts, booms)
    local m = mirrors:iter()[1]
    ts.t_mirror = m ~= nil and m:has("abilities/fireball")
    for _, c in ipairs(casts:iter()) do
        ts.t_casts = ts.t_casts + 1
        ts.t_cast_x = c:get("abilities/projectile").at.x
    end
    for _, b in ipairs(booms:iter()) do
        ts.t_booms = ts.t_booms + 1
        ts.t_boom_z = b:get("explosion").at.z
    end
end):in_set("zz/ac_t")
]=])

helpers.spawn_vm("modules/test_fixtures/gen_abilities_cross_t.lua", { DEFAULTS = DEFAULTS }, { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_abilities_cross_s.lua", { DEFAULTS = DEFAULTS }, { headless = true })

local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function within(seconds, cond) return function() return cond() or t - mark > seconds end end
local function after(seconds) return function() return t - mark > seconds end end
local function counts() return string.format("casts %d/%d booms %d/%d", ts.s_casts, ts.t_casts, ts.s_booms, ts.t_booms) end

step(within(20, function() return ts.s_ready and ts.t_mirror end), function()
    ts.press = "down:41"
end)
step(within(5, function() return ts.s_booms >= 1 and ts.t_booms >= 1 end), function()
    T("X1_a_press_casts_in_world_1_and_the_mirror_casts_in_world_2", ts.s_casts == 1 and ts.t_casts == 1, counts())
    T("X1_from_the_mirror_s_place", math.abs(ts.t_cast_x - 3) < 0.01, tostring(ts.t_cast_x))
    T("X2_each_explodes_on_its_own_world_s_wall", ts.s_boom_z < -11.4 and ts.t_boom_z > -8 and ts.t_boom_z < -3.4,
        string.format("world 1 at z=%.2f, world 2 at z=%.2f", ts.s_boom_z, ts.t_boom_z))
    ts.press = "up"
end)
step(after(1.5), function()
    T("X3_neither_world_casts_twice_and_nothing_casts_back", ts.s_casts == 1 and ts.t_casts == 1
        and ts.s_booms == 1 and ts.t_booms == 1, counts())
    ts.press = "down:41"
end)
step(within(5, function() return ts.s_casts >= 2 and ts.t_casts >= 2 end), function()
    T("X4_a_second_press_casts_again_in_both_worlds", ts.s_casts == 2 and ts.t_casts == 2, counts())
    ts.press = "up"
end)
step(after(1.5), function()
    ts.press = "down:42"
end)
step(after(1.5), function()
    T("X5_a_player_with_no_mirror_casts_in_its_own_world_only", ts.s_casts == 3 and ts.t_casts == 2, counts())
    ts.press = "up"
end)

local done = false
app:add_systems(Update, { World }, function(world)
    t = t + world:delta_time()
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("AbilitiesCrossSuite")
    elseif s.ready(world) then
        s.act(world)
        at, mark = at + 1, t
    elseif t - mark > 30 then
        T("X0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("AbilitiesCrossSuite")
    end
end):in_set("zz/ac_drive")
