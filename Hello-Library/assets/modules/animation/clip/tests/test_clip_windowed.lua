-- --host (windowed: a headless run advances no clip)
-- `animation/clip` playing over time, as a door's clip does: the fixture's walk clip, one second
-- long, on the fixture model.
--
--   CW1 forward, not repeating: it reaches its end and holds it
--   CW2 turned backward once it has finished there: it plays back from the end, not from the start
--   CW3 paused halfway back: it stays where it stands
--   CW4 backward again: it reaches its start and holds it
--   CW5 repeating: it plays past its length and goes round
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("AnimationClipWindowedSuite")
local T = suite.assert_test

local MODEL = "modules/animation/tests/fixtures/Model"
local WALK = MODEL .. "-Walk.glb#Animation0"

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/clip"] = {},
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        Transform = {},
        ["animation/clip"] = { clips = { [WALK] = 1 }, speed = 0 },
    })
end)

local phase, clock = "loading", 0
local paused_at

app:add_systems(Update, {
    World,
    Query[{ with = { "AnimationPlayer" } }],
    Commands,
}, function(world, players, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local n = world:query({ with = { "zz/clip" }, optional = { "animation/clip/graph" } })[1]
    local p = n and players:iter_many(world:descendants(n:id()))[1]
    local graph = n and n:get("animation/clip/graph")
    local a = graph and p and graph.nodes[WALK] and p.AnimationPlayer:animation(graph.nodes[WALK]) or nil
    local function set(speed, loops)
        commands:entity(n:id()):insert({ ["animation/clip"] = { clips = { [WALK] = 1 }, speed = speed, ["repeat"] = loops } })
    end
    local function said() return a and string.format("at %.3f, %d completions", a.seek_time, a.completions) or "not playing" end

    if phase == "loading" then
        if a == nil and clock < 10 then return end
        set(1, false)
        step("forward")

    elseif phase == "forward" and clock > 1.5 then
        T("CW1_forward_it_reaches_its_end_and_holds_it", a ~= nil and a.completions >= 1 and a.seek_time >= 1, said())
        set(-1, false)
        step("back")

    elseif phase == "back" and clock > 0.5 then
        T("CW2_turned_back_after_finishing_it_plays_back_from_the_end", a ~= nil and a.seek_time > 0.3 and a.seek_time < 0.7,
            said())
        set(0, false)
        paused_at = a and a.seek_time
        step("paused")

    elseif phase == "paused" and clock > 0.5 then
        T("CW3_paused_it_stays", a ~= nil and paused_at ~= nil and math.abs(a.seek_time - paused_at) < 0.05, said())
        set(-1, false)
        step("to_start")

    elseif phase == "to_start" and clock > 1.5 then
        T("CW4_backward_it_reaches_its_start_and_holds_it", a ~= nil and a.completions >= 1 and a.seek_time <= 0.01, said())
        set(1, true)
        step("looping")

    elseif phase == "looping" and clock > 2.5 then
        T("CW5_repeating_it_goes_round", a ~= nil and a["repeat"] == "Forever" and a.elapsed > 1.5 and a.seek_time < 1, said())
        phase = "done"
        suite.finish("ANIMATION_CLIP_WINDOWED")
    end

    if phase ~= "done" and clock > 12 then
        T("CW0_reached_" .. phase, false, said())
        phase = "done"
        suite.finish("ANIMATION_CLIP_WINDOWED")
    end
end):in_set("zz/animation_clip_windowed")
