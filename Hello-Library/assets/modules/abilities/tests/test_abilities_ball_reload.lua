-- --host
-- A ball in flight through a reload of the ability that threw it: each ability's own file is written
-- again while it keeps throwing. The watcher polls every 5 s, longer than a grenade flies, so it throws
-- until the reload comes, and then the ball that flew through it is watched to its end.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("AbilitiesBallReloadSuite")

-- High over nothing, each with its own stretch of sky, so neither hits anything.
local KINDS = {
    {
        name = "fireball",
        ability = "abilities/fireball",
        press = "input/game/abilities/fireball",
        file = "abilities/fireball/init.lua",
        x = 0,
        lifetime = 5,
    },
    {
        name = "grenade",
        ability = "abilities/grenade",
        press = "input/game/abilities/grenade",
        file = "abilities/grenade/init.lua",
        x = 500,
        lifetime = 3,
    },
}

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    for _, kind in ipairs(KINDS) do
        commands:spawn({
            ["zz/player"] = { name = kind.name },
            [kind.ability] = {},
            Transform = { translation = { x = kind.x, y = 1000, z = 0 } },
            camera = { yaw = 0, pitch = 0 },
            ["core/net/owner"] = { client_id = 7 },
            ["core/net/sync"] = { Transform = { authority = "client" } },
        })
    end
end)

local reloads = {}
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        local path = tostring(event.path)
        for _, kind in ipairs(KINDS) do
            if path:find(kind.file, 1, true) then
                reloads[kind.name] = (reloads[kind.name] or 0) + 1
            end
        end
    end
end):in_set("zz/ball_reload_watch")

-- Every ball, by whose stretch of sky it is in: the ones there last frame, when each was thrown, and
-- how many have ever been thrown.
local balls = {}
for _, kind in ipairs(KINDS) do
    balls[kind.name] = { thrown = 0, thrown_at = {}, last = {} }
end

local function sky_of(x)
    for _, kind in ipairs(KINDS) do
        if math.abs(x - kind.x) < 200 then
            return kind.name
        end
    end
end

local function at_of(world, id)
    local e = world:get_entity(id)
    return e and e.GlobalTransform and e.GlobalTransform:compute_transform().translation
end

local function player(world, kind)
    for _, e in ipairs(world:query({ with = { "zz/player" }, optional = { kind.press } })) do
        if e:get("zz/player").name == kind.name then
            return e
        end
    end
end

local kind_index, phase, clock, since_throw = 1, "settle", 0, 10
local ball, ball_at, thrown_before, reloads_before = nil, nil, 0, 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    local dt = time:delta_secs()
    clock = clock + dt
    local now = time:elapsed_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    -- What flew through the frame before is read before this frame's list replaces it.
    local previous = {}
    for name, b in pairs(balls) do
        previous[name] = b.last
        b.last = {}
    end
    for _, e in ipairs(world:query({ added = { "abilities/projectile" } })) do
        local name = sky_of(e:get("abilities/projectile").at.x)
        balls[name].thrown = balls[name].thrown + 1
        balls[name].thrown_at[tostring(e:id())] = now
    end
    for _, e in ipairs(world:query({ with = { "abilities/projectile" } })) do
        local name = sky_of(e:get("abilities/projectile").at.x)
        local list = balls[name].last
        list[#list + 1] = e:id()
    end

    local kind = KINDS[kind_index]
    local b = balls[kind.name]

    if phase == "settle" and clock > 0.5 then
        reloads_before = reloads[kind.name] or 0
        local path = "assets/modules/" .. kind.file
        write_file_bytes(path, read_file_bytes(path))
        step("throwing")

    elseif phase == "throwing" then
        -- A press lasts a frame, so none is held when the reload comes.
        local p = player(world, kind)
        if p:has(kind.press) then
            commands:entity(p:id()):remove(kind.press)
        end
        since_throw = since_throw + dt
        if since_throw > 1.2 then
            since_throw = 0
            commands:entity(p:id()):patch({ [kind.press] = { value = 1 } })
        end
        if (reloads[kind.name] or 0) > reloads_before then
            local list = previous[kind.name]
            ball = list[#list]
            suite.assert_test("B0_" .. kind.name .. "_a_ball_was_flying_when_it_reloaded", ball ~= nil, "")
            ball_at = ball and at_of(world, ball)
            thrown_before = b.thrown
            step("reloaded")
        elseif clock > 12 then
            suite.assert_test("B0_" .. kind.name .. "_it_reloaded", false, "no reload in 12 s")
            phase = "done"
            suite.finish("AbilitiesBallReloadSuite")
        end

    elseif phase == "reloaded" and clock > 0.5 then
        local at = ball and at_of(world, ball)
        suite.assert_test("B1_" .. kind.name .. "_the_ball_flies_on_through_its_abilitys_reload", at ~= nil, "")
        suite.assert_test("B2_" .. kind.name .. "_and_keeps_moving",
            at ~= nil and ball_at ~= nil and math.abs(at.z - ball_at.z) + math.abs(at.y - ball_at.y) > 1, "")
        step("flying")

    elseif phase == "flying" and ball ~= nil and world:get_entity(ball) == nil then
        local flew = now - (b.thrown_at[tostring(ball)] or now)
        suite.assert_test("B3_" .. kind.name .. "_it_ends_itself_when_its_lifetime_does",
            math.abs(flew - kind.lifetime) < 0.5, "flew " .. flew)
        suite.assert_test("B4_" .. kind.name .. "_and_no_second_ball_appeared", b.thrown == thrown_before, b.thrown .. " after " .. thrown_before)
        kind_index = kind_index + 1
        since_throw = 10
        if KINDS[kind_index] == nil then
            phase = "done"
            suite.finish("AbilitiesBallReloadSuite")
        else
            step("settle")
        end

    elseif phase == "flying" and clock > kind.lifetime + 2 then
        suite.assert_test("B3_" .. kind.name .. "_it_ends_itself_when_its_lifetime_does", false, "still flying")
        phase = "done"
        suite.finish("AbilitiesBallReloadSuite")
    end
end):in_set("zz/ball_reload_suite")
