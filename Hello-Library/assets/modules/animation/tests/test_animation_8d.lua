-- --host
-- A character's walk as a set of eight directions, and its run, on a client, headless: the weights
-- it writes on its model. The directions are the eight clips of `tests/fixtures/Model-Walk8.gltf`.
-- Each character faces +Z (its rotation is left alone), so the angle is where it moves.
--
--   D1 walking straight ahead plays the forward clip alone
--   D2 walking halfway between two directions plays both, each at half
--   D3 walking back and to the left plays that direction alone
--   D4 faster than 4 m/s, a character with a `run` clip runs, at its speed over `run_speed`
--   D5 just under 4 m/s it still walks (a speed read from a Transform moved by frames wavers, so not
--      at 4 itself)
--   D6 a character with no `run` clip walks at any speed
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("Animation8dSuite")
local T = suite.assert_test

local MODEL = "modules/animation/tests/fixtures/Model"
local IDLE = "-Idle.glb#Animation0"
local RUN = "-Jump.glb#Animation0"
local DIRECTIONS = {}
for i, angle in ipairs({ 0, 45, 90, 135, 180, -135, -90, -45 }) do
    DIRECTIONS[i] = { angle = angle, clip = "-Walk8.gltf#Animation" .. (i - 1) }
end
local function dir(angle)
    for _, d in ipairs(DIRECTIONS) do
        if d.angle == angle then return MODEL .. d.clip end
    end
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["zz/world"] = {}, ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/char"] = { name = "runner" },
        animation = { model = MODEL, clips = { idle = IDLE, walk = DIRECTIONS, run = RUN } },
        Transform = { translation = { x = 0, y = 1, z = 0 } },
    })
    commands:spawn({
        ["zz/char"] = { name = "walker" },
        animation = { model = MODEL, clips = { idle = IDLE, walk = DIRECTIONS } },
        Transform = { translation = { x = 10, y = 1, z = 0 } },
    })
end)

local velocity = nil

app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "zz/char", Mut["Transform"] } }],
}, function(time, chars)
    if velocity == nil then return end
    local dt = time:delta_secs()
    for _, e in ipairs(chars:iter_mut()) do
        local t = e:get_mut("Transform")
        t.translation.x = t.translation.x + velocity.x * dt
        t.translation.z = t.translation.z + velocity.z * dt
    end
end):in_set("zz/animation_8d_mover"):before("animation/state")

local function named(world, name)
    for _, e in ipairs(world:query({ with = { "zz/char" }, optional = { "animation/playing" } })) do
        if e:get("zz/char").name == name then return e end
    end
end

local function weights(world, e)
    local m = world:query({ with = { "animation/model" }, optional = { "animation/clip" }, iter_many = world:descendants(e:id()) })[1]
    return m and (m:get("animation/clip") or {}).clips or {}
end

local function near(a, b) return a ~= nil and math.abs(a - b) < 0.02 end

-- A walk toward `deg` clockwise from ahead (+Z), seen from above: a body facing +Z has its right at -X.
local function toward(deg, speed)
    local r = math.rad(deg)
    return { x = -math.sin(r) * speed, z = math.cos(r) * speed }
end

local phase, clock = "loading", 0
local STEPS = {
    { name = "ahead", velocity = toward(0, 3) },
    { name = "between", velocity = toward(22.5, 3) },
    { name = "back_left", velocity = toward(-135, 3) },
    { name = "fast", velocity = toward(0, 5) },
    { name = "four", velocity = toward(0, 3.8) },
}
local index = 0

app:add_systems(Update, { World, Res[Time] }, function(world, time)
    clock = clock + time:delta_secs()
    local runner, walker = named(world, "runner"), named(world, "walker")
    local w = runner and weights(world, runner) or {}

    if phase == "loading" then
        if not (w[MODEL .. IDLE] == 1) and clock < 10 then return end
        phase, clock, index = "moving", 0, 1
        velocity = STEPS[1].velocity
        return
    end
    if phase ~= "moving" or clock < 0.8 then return end
    local step = STEPS[index]
    local playing = runner:get("animation/playing") or {}

    if step.name == "ahead" then
        T("D1_straight_ahead_plays_the_forward_clip_alone", near(w[dir(0)], 1) and near(w[dir(45)], 0) and near(w[dir(-45)], 0)
            and near(w[MODEL .. IDLE], 0), string.format("F %s R45 %s L45 %s", tostring(w[dir(0)]), tostring(w[dir(45)]), tostring(w[dir(-45)])))
    elseif step.name == "between" then
        T("D2_between_two_directions_plays_both_at_half", near(w[dir(0)], 0.5) and near(w[dir(45)], 0.5) and near(w[dir(-45)], 0),
            string.format("F %s R45 %s", tostring(w[dir(0)]), tostring(w[dir(45)])))
    elseif step.name == "back_left" then
        T("D3_back_and_to_the_left_plays_that_direction", near(w[dir(-135)], 1) and near(w[dir(180)], 0) and near(w[dir(0)], 0),
            string.format("L135 %s B %s", tostring(w[dir(-135)]), tostring(w[dir(180)])))
    elseif step.name == "fast" then
        local ww = weights(world, walker)
        T("D4_faster_than_4_it_runs_at_its_speed_over_run_speed", playing.state == "run" and near(playing.speed, 5 / 6)
            and near(w[MODEL .. RUN], 1) and near(w[dir(0)], 0),
            string.format("%s at %s, run %s", tostring(playing.state), tostring(playing.speed), tostring(w[MODEL .. RUN])))
        T("D6_with_no_run_clip_it_walks_at_any_speed", (walker:get("animation/playing") or {}).state == "walk"
            and near(ww[dir(0)], 1), tostring((walker:get("animation/playing") or {}).state))
    elseif step.name == "four" then
        T("D5_just_under_4_it_still_walks", playing.state == "walk" and near(w[dir(0)], 1),
            string.format("%s, F %s", tostring(playing.state), tostring(w[dir(0)])))
    end

    index = index + 1
    if STEPS[index] then
        velocity, clock = STEPS[index].velocity, 0
    else
        velocity, phase = nil, "done"
        suite.finish("ANIMATION_8D")
    end
end):in_set("zz/animation_8d_suite"):after("animation/state")

app:add_systems(Update, { Res[Time] }, function(time)
    if phase ~= "done" and clock > 12 then
        T("D0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("ANIMATION_8D")
    end
end)
