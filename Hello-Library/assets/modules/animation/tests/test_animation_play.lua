-- --host
-- `animation` playing through `animation/clip` on a client, headless: what the character writes
-- on its model, and what the model's player is told. No clip advances here. The model is the
-- animation fixture.
--
--   AP1 the model carries every clip the character has, idle at 1 and the rest at 0, looping
--   AP2 walking fades walk in as idle fades out, and settles at walk alone
--   AP3 the clips play at the walk's speed, and the model's player plays walk at its weight
--   AP4 a character at its targets writes its model no more
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AnimationPlaySuite")
local T = suite.assert_test

local MODEL = "modules/animation/tests/fixtures/Model"
local IDLE = MODEL .. "-Idle.glb#Animation0"
local WALK = MODEL .. "-Walk.glb#Animation0"
local JUMP = MODEL .. "-Jump.glb#Animation0"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/char"] = {}, animation = { model = MODEL },
        Transform = { translation = { x = 0, y = 1, z = 0 } },
    })
end)

local function character(world)
    return world:query({ with = { "zz/char" }, optional = { "animation/playing" } })[1]
end

local function model_of(world, e)
    return world:query({
        with = { "animation/model" },
        optional = { "animation/clip", "animation/clip/graph" },
        iter_many = world:descendants(e:id()),
    })[1]
end

local phase, clock = "loading", 0
local moving = false
local seen = { blended = 0, writes = 0 }

app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "zz/char", Mut["Transform"] } }],
}, function(time, chars)
    if not moving then return end
    for _, e in ipairs(chars:iter_mut()) do
        local t = e:get_mut("Transform")
        t.translation.x = t.translation.x + 3 * time:delta_secs()
    end
end):in_set("zz/animation_play_mover"):before("animation/state")

app:add_systems(Update, {
    World,
    Res[Time],
    Query[{ with = { "AnimationPlayer" } }],
}, function(world, time, players)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local e = character(world)
    local model = e and model_of(world, e)
    local c = model and model:get("animation/clip")
    local clips = c and c.clips or {}

    if phase == "loading" then
        if not (model and model:has("animation/clip/graph") and clips[IDLE] == 1) and clock < 10 then return end
        T("AP1_the_model_carries_every_clip_idle_at_1", clips[IDLE] == 1 and clips[WALK] == 0 and clips[JUMP] == 0
            and c["repeat"] == true and c.speed == 1,
            string.format("idle %s walk %s jump %s", tostring(clips[IDLE]), tostring(clips[WALK]), tostring(clips[JUMP])))
        moving = true
        step("walking")

    elseif phase == "walking" then
        if clips[WALK] > 0 and clips[WALK] < 1 and clips[IDLE] > 0 and clips[IDLE] < 1 then seen.blended = seen.blended + 1 end
        if clock < 1.0 then return end
        T("AP2_walking_fades_walk_in_as_idle_fades_out", seen.blended >= 2 and clips[WALK] == 1 and clips[IDLE] == 0,
            string.format("%d frames blended, walk %s idle %s", seen.blended, tostring(clips[WALK]), tostring(clips[IDLE])))
        local graph = model:get("animation/clip/graph")
        local p = players:iter_many(world:descendants(model:id()))[1]
        local a = p and graph and p.AnimationPlayer:animation(graph.nodes[WALK])
        T("AP3_the_clips_play_at_the_walks_speed_and_the_player_plays_walk", math.abs(c.speed - 0.5) < 0.05
            and a ~= nil and a.weight == 1 and math.abs(a.speed - 0.5) < 0.05,
            string.format("speed %s, player %s", tostring(c.speed), a and (a.weight .. "@" .. a.speed) or "not playing"))
        moving = false
        step("settling")

    elseif phase == "settling" and clock > 0.6 then
        step("still")

    elseif phase == "still" then
        for _ in ipairs(world:query({ changed = { "animation/clip" }, with = { "animation/model" } })) do
            seen.writes = seen.writes + 1
        end
        if clock < 0.5 then return end
        T("AP4_a_character_at_its_targets_writes_its_model_no_more", seen.writes == 0 and clips[IDLE] == 1,
            string.format("%d writes, idle %s", seen.writes, tostring(clips[IDLE])))
        phase = "done"
        suite.finish("ANIMATION_PLAY")
    end

    if phase ~= "done" and clock > 12 then
        T("AP0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("ANIMATION_PLAY")
    end
end):in_set("zz/animation_play_suite"):after("animation/state")
