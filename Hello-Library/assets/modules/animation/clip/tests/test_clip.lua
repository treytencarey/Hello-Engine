-- --host
-- `animation/clip` on a client, headless: the scene's AnimationPlayer and its graph exist, and its
-- clips advance, as on any side; what is checked is mostly what the player is told to play. The
-- model is the animation fixture: an animated node under an `Armature`, its clips one second long.
--
--   CL1 missing fields get defaults: speed 1, holding its end
--   CL2 the node's graph has a node per clip, and the scene's player gets it and plays the clip at
--       its weight and speed, looping when asked
--   CL3 two clips play at once, each at its weight
--   CL4 a new weight and speed reach the running clips, and the graph is kept
--   CL5 a weight of 0 stops its clip, and the graph is kept
--   CL6 a clip taken out builds the graph again without it, and the player plays only the rest
--   CL7 a clip that starts backward starts from its start, which holds it there, finished
--   CL8 asked to repeat otherwise, a running clip starts again where it stands, in the new mode
--   CL9 a clip that is not an asset path plays nothing
--   CL10 a clip newly in `clips` starts at `animation/clip/seek`
--   CL11 `animation/clip/seek` changing moves the playing clips, within their length
--   CL12 a write to `animation/clip` alone moves nothing
--   CL13 `"end"` starts a clip at its end, a backward one too, which then plays back from there
--   CL14 a clip whose length is not known yet (its file still loading) goes to its end once it is
--   CL15 a clip named by an animation of the node's scene's glTF plays it
--   CL16 a clip named by an animation of a scene whose file does not exist asks for that file once:
--        nothing tries it again
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local AssetServer = require("bevy::asset::AssetServer")
local UntypedAssetLoadFailedEvent = require("bevy::asset::UntypedAssetLoadFailedEvent")

local suite = helpers.create_suite("AnimationClipSuite")
local T = suite.assert_test

local MODEL = "modules/animation/tests/fixtures/Model"
local WALK = MODEL .. "-Walk.glb#Animation0"
local IDLE = MODEL .. "-Idle.glb#Animation0"
local JUMP = MODEL .. "-Jump.glb#Animation0"
-- a file that does not exist
local MISSING = "modules/animation/clip/tests/fixtures/zz_missing.gltf"
-- a file nothing else here loads, so its length is not known when it starts
local LATE = MODEL .. "-Walk8.gltf#Animation3"

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/clip"] = {},
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        Transform = {},
        ["animation/clip"] = { clips = { [WALK] = 1 } },
    })
    -- a scene whose glTF names its one animation `zz_open`
    commands:spawn({
        ["zz/named"] = {},
        SceneRoot = asset_server:load("modules/animation/clip/tests/fixtures/named.gltf#Scene0"),
        Transform = { translation = { x = 5, y = 0, z = 0 } },
        ["animation/clip"] = { clips = { zz_open = 1 }, speed = 0 },
    })
    commands:spawn({
        ["zz/missing"] = {},
        SceneRoot = asset_server:load(MISSING .. "#Scene0"),
        Transform = { translation = { x = -5, y = 0, z = 0 } },
        ["animation/clip"] = { clips = { zz_gone = 1 } },
    })
end)

-- Every time the missing file is asked for and fails: the scene's own ask, and the clip's.
local missing_failures = 0
app:add_systems(First, { bevy.MessageReader[UntypedAssetLoadFailedEvent] }, function(failed)
    for _, failure in ipairs(failed:read()) do
        -- named with its asset source, maybe twice
        local path = tostring(failure.path):gsub("#.*$", ""):gsub("^.*://", "")
        if path == MISSING then missing_failures = missing_failures + 1 end
    end
end):in_set("zz/animation_clip_missing")

local function node(world)
    return world:query({ with = { "zz/clip" }, optional = { "animation/clip", "animation/clip/graph" } })[1]
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local phase, clock = "loading", 0
local nodes_before
local seek_walk

-- Where time would move a clip, the suite moves it.
app:add_systems(PostUpdate, {
    Query[{ with = { "zz/clip", "animation/clip/graph" } }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
}, function(nodes, players)
    if seek_walk == nil then return end
    for _, n in ipairs(nodes:iter()) do
        local p = players:iter_many_mut(players:iter_descendants(n:id()))[1]
        local index = n:get("animation/clip/graph").nodes[WALK]
        if p and index then p.AnimationPlayer:play(index, { seek_to = seek_walk }) end
    end
    seek_walk = nil
end):in_set("zz/animation_clip_seek"):after("animation/clip/seek")

app:add_systems(Update, {
    World,
    Query[{ with = { "AnimationPlayer" }, optional = { "AnimationGraphHandle" } }],
    Commands,
}, function(world, players, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local n = node(world)
    local p = n and players:iter_many(world:descendants(n:id()))[1]
    local graph = n and n:get("animation/clip/graph")
    local function playing(clip)
        local index = graph and graph.nodes[clip]
        return index and p and p.AnimationPlayer:animation(index) or nil
    end
    -- How many graph nodes the player runs. Its `active_animations` reads back with one key for
    -- every entry, so each node is asked.
    local function active_count()
        local running = 0
        for index = 0, 8 do
            if p.AnimationPlayer:animation(index) ~= nil then running = running + 1 end
        end
        return running
    end
    local function set(value, to)
        commands:entity(n:id()):insert({ ["animation/clip"] = value })
        if to ~= nil then commands:entity(n:id()):insert({ ["animation/clip/seek"] = { to = to } }) end
    end

    if phase == "loading" then
        if not (p and p:has("AnimationGraphHandle") and playing(WALK)) and clock < 10 then return end
        local c = n:get("animation/clip")
        T("CL1_missing_fields_get_defaults", c.speed == 1 and c["repeat"] == false, tostring(c["repeat"]))
        local a = playing(WALK)
        T("CL2_a_node_per_clip_and_the_player_plays_it_at_its_weight_and_speed", graph ~= nil and count(graph.nodes) == 1
            and a ~= nil and a.weight == 1 and a.speed == 1 and a["repeat"] == "Never",
            a and string.format("weight %s speed %s %s", a.weight, a.speed, a["repeat"]) or "not playing")
        set({ clips = { [WALK] = 0.25, [IDLE] = 0.75 }, speed = 1, ["repeat"] = true })
        step("two")

    elseif phase == "two" and clock > 0.3 then
        local w, i = playing(WALK), playing(IDLE)
        T("CL2_looping_when_asked", w ~= nil and w["repeat"] == "Forever", tostring(w and w["repeat"]))
        T("CL3_two_clips_play_at_their_weights", w ~= nil and i ~= nil and w.weight == 0.25 and i.weight == 0.75
            and active_count() == 2, string.format("%s %s", tostring(w and w.weight), tostring(i and i.weight)))
        nodes_before = graph.nodes
        set({ clips = { [WALK] = 0.5, [IDLE] = 0.5 }, speed = 0, ["repeat"] = true })
        step("reweighted")

    elseif phase == "reweighted" and clock > 0.3 then
        local w, i = playing(WALK), playing(IDLE)
        T("CL4_a_new_weight_and_speed_reach_the_running_clips", w ~= nil and i ~= nil and w.weight == 0.5 and w.speed == 0
            and i.weight == 0.5 and i.speed == 0, string.format("%s %s", tostring(w and w.weight), tostring(w and w.speed)))
        T("CL4_and_the_graph_is_kept", graph.nodes[WALK] == nodes_before[WALK] and graph.nodes[IDLE] == nodes_before[IDLE]
            and count(graph.nodes) == 2, "")
        set({ clips = { [WALK] = 0, [IDLE] = 1 }, speed = 1, ["repeat"] = true })
        step("silenced")

    elseif phase == "silenced" and clock > 0.3 then
        T("CL5_a_weight_of_0_stops_its_clip_and_the_graph_is_kept", playing(WALK) == nil and playing(IDLE) ~= nil
            and count(graph.nodes) == 2 and active_count() == 1, tostring(active_count()))
        set({ clips = { [IDLE] = 1 }, speed = 1, ["repeat"] = true })
        step("taken_out")

    elseif phase == "taken_out" and clock > 0.3 then
        T("CL6_a_clip_taken_out_builds_the_graph_without_it", count(graph.nodes) == 1 and graph.nodes[WALK] == nil
            and playing(IDLE) ~= nil and active_count() == 1, string.format("nodes %d, active %d", count(graph.nodes), active_count()))
        -- the same clips, the idle one looping: asked to hold its end now, it starts again where it
        -- stood, in the new mode
        set({ clips = { [IDLE] = 1 }, speed = 1, ["repeat"] = false })
        step("holding")

    elseif phase == "holding" and clock > 0.3 then
        local i = playing(IDLE)
        T("CL8_asked_to_repeat_otherwise_it_starts_again_in_the_new_mode", i ~= nil and i["repeat"] == "Never"
            and count(graph.nodes) == 1, tostring(i and i["repeat"]))
        set({ clips = { [IDLE] = 1, [JUMP] = 1 }, speed = -1, ["repeat"] = false })
        step("backward")

    elseif phase == "backward" and clock > 0.3 then
        local j = playing(JUMP)
        T("CL7_a_clip_starting_backward_starts_from_its_start", j ~= nil and j.speed == -1 and j.seek_time <= 0
            and j.seek_time > -0.1 and j.completions >= 1,
            j and string.format("speed %s at %s, %s completions", j.speed, j.seek_time, j.completions) or "not playing")
        set({ clips = { [IDLE] = 1, ["portal_open"] = 1 }, speed = 1, ["repeat"] = false })
        step("named")

    elseif phase == "named" and clock > 0.3 then
        T("CL9_a_clip_that_is_not_an_asset_path_plays_nothing", graph.nodes["portal_open"] == nil and count(graph.nodes) == 1
            and active_count() == 1, string.format("nodes %d", count(graph.nodes)))
        set({ clips = { [IDLE] = 1, [WALK] = 1 }, speed = 0 }, 0.4)
        step("seek_new")

    elseif phase == "seek_new" and clock > 0.3 then
        local w = playing(WALK)
        T("CL10_a_clip_newly_in_clips_starts_at_the_seek", w ~= nil and math.abs(w.seek_time - 0.4) < 1e-3,
            w and tostring(w.seek_time) or "not playing")
        set({ clips = { [IDLE] = 1, [WALK] = 1 }, speed = 0 }, 0.7)
        step("seek_moved")

    elseif phase == "seek_moved" and clock > 0.3 then
        local w, i = playing(WALK), playing(IDLE)
        T("CL11_a_changed_seek_moves_the_playing_clips", w ~= nil and i ~= nil and math.abs(w.seek_time - 0.7) < 1e-3
            and math.abs(i.seek_time - 0.7) < 1e-3, string.format("%s %s", tostring(w and w.seek_time), tostring(i and i.seek_time)))
        set({ clips = { [IDLE] = 1, [WALK] = 1 }, speed = 0 }, 5)
        step("seek_clamped")

    elseif phase == "seek_clamped" and clock > 0.3 then
        local w = playing(WALK)
        T("CL11_within_their_length", w ~= nil and math.abs(w.seek_time - 1) < 1e-3, w and tostring(w.seek_time) or "not playing")
        seek_walk = 0.2
        step("seek_kept")

    elseif phase == "seek_kept" and clock > 0.3 then
        set({ clips = { [IDLE] = 1, [WALK] = 0.5 }, speed = 0 })
        step("seek_kept_written")

    elseif phase == "seek_kept_written" and clock > 0.3 then
        local w = playing(WALK)
        T("CL12_a_write_to_animation_clip_alone_moves_nothing", w ~= nil and w.weight == 0.5 and math.abs(w.seek_time - 0.2) < 1e-3,
            w and string.format("weight %s at %s", w.weight, w.seek_time) or "not playing")
        set({ clips = { [IDLE] = 1, [WALK] = 1, [JUMP] = 1 }, speed = -1 }, "end")
        step("seek_end")

    elseif phase == "seek_end" and clock > 0.3 then
        local j, w = playing(JUMP), playing(WALK)
        -- each started at its end and has played back for at most the 0.3 s waited
        T("CL13_end_starts_a_clip_at_its_end_a_backward_one_too", j ~= nil and w ~= nil and j.speed == -1
            and j.seek_time > 0.6 and j.seek_time < 1 and w.seek_time > 0.6 and w.seek_time < 1,
            string.format("%s %s", tostring(j and j.seek_time), tostring(w and w.seek_time)))
        set({ clips = { [IDLE] = 1, [LATE] = 1 }, speed = 0 })
        step("seek_late")

    elseif phase == "seek_late" then
        local l = playing(LATE)
        if not (l ~= nil and l.seek_time > 0) and clock < 5 then return end
        T("CL14_a_clip_whose_length_comes_later_goes_to_its_end_once_known", l ~= nil and math.abs(l.seek_time - 1) < 1e-3,
            l and tostring(l.seek_time) or "not playing")
        local named = world:query({ with = { "zz/named" }, optional = { "animation/clip/graph" } })[1]
        local g = named and named:get("animation/clip/graph")
        local np = named and players:iter_many(world:descendants(named:id()))[1]
        local a = g and np and g.nodes.zz_open and np.AnimationPlayer:animation(g.nodes.zz_open) or nil
        T("CL15_a_clip_named_by_its_scene_s_gltf_plays_it", a ~= nil and a.weight == 1 and a.speed == 0,
            g and ("node " .. tostring(g.nodes.zz_open) .. ", " .. (a and "playing" or "not playing")) or "no graph")
        -- the suite has run for several seconds by now: a clip retrying each frame asks hundreds of times
        T("CL16_a_scene_file_that_does_not_exist_is_asked_for_once", missing_failures >= 1 and missing_failures <= 2,
            tostring(missing_failures) .. " failed loads")
        phase = "done"
        suite.finish("ANIMATION_CLIP")
    end

    if phase ~= "done" and clock > 10 then
        T("CL0_reached_" .. phase, false, "stuck")
        phase = "done"
        suite.finish("ANIMATION_CLIP")
    end
end):in_set("zz/animation_clip_suite")
