-- Clips playing on a node: the base every skeletal animation plays through. A node carrying
-- `animation/clip` plays its clips on the AnimationPlayer at that node or under it (Bevy's glTF
-- loader puts the player on the animation's root node), each at its weight, all at one speed. It
-- runs on both sides: a server plays the real clip too, so what an animation moves (a door's
-- collider) moves there.
--
-- A clip is an asset path, `<file>#Animation<N>`, or the name of an animation in the glTF the
-- node's scene came from (the nearest `SceneRoot` at or above it). A clip that newly has a weight
-- starts at the node's `animation/clip/seek`, or else from its start, which a negative speed
-- holds; one that keeps a weight plays on, taking the new weight and speed; one whose weight goes
-- to 0, or that is taken out, stops. `animation/clip/seek` arriving or changing moves every playing
-- clip to it.
--
-- animation/clip/source = {
--     file = <the file of the node's scene, for a clip named by one of its animations>,
--     clips = { [<clip>] = <its handle, for a clip named by its asset path> },
-- }: on the node, on each side, never synced. What its clips are read from, asked for once; the
-- handles keep them loaded.
--
-- animation/clip/graph = {
--     handle = <the node's AnimationGraph>,
--     nodes = { [<clip>] = <the graph node playing it> },
-- }: on the node, on each side, never synced. Built for the set of clips the node names, and built again
-- when that set changes, so a node that fades between clips lists all of them, at 0 when silent.

local bevy = require("bevy::prelude")
local AssetServer = require("bevy::asset::AssetServer")
local Assets = require("bevy::asset::Assets")
local AssetEvent = require("bevy::asset::AssetEvent")
local UntypedAssetLoadFailedEvent = require("bevy::asset::UntypedAssetLoadFailedEvent")
local AnimationGraph = require("bevy::animation::graph::AnimationGraph")
local AnimationClip = require("bevy::animation::AnimationClip")
local Gltf = require("bevy::gltf::prelude::Gltf")
local Clip = require("modules/animation/clip/shared/clip.lua")

local function is_path(clip)
    return clip:find("#", 1, true) ~= nil
end

local function without_label(path)
    return (tostring(path):gsub("#.*$", ""))
end

-- A path as a load reports it: its asset source taken off (a failure can name it twice).
local function sourceless(path)
    local text, taken = tostring(path), 1
    while taken > 0 do text, taken = text:gsub("^[%w_%-]+://", "") end
    return text
end

--- The file a node's scene came from: the nearest `SceneRoot` at or above it, its path without its
--- label. `scenes` is a query naming `SceneRoot`.
local function scene_file(scenes, node)
    local root = scenes:iter_many({ node })[1] or scenes:iter_many(scenes:iter_ancestors(node))[1]
    return root and without_label(root:get("SceneRoot"):path()) or nil
end

--- The handle a node's clip names, or nil, from its `animation/clip/source`: an asset path's own,
--- or an animation of its scene's file. A second answer says the name waits for that file to load.
local function clip_handle(clip, source, gltfs)
    if is_path(clip) then return (source.clips or {})[clip], false end
    if source.file == nil then return nil, false end
    local gltf = gltfs:get(source.file)
    if gltf == nil then return nil, true end
    return gltf.named_animations and gltf.named_animations[clip] or nil, false
end

local unresolved_said = {}

--- The node's clips that resolve, in a stable order, and their handles; and whether a name waits
--- for its file to load.
local function resolved(clips, source, gltfs)
    local names, handles, waits = {}, {}, false
    for clip in pairs(clips or {}) do
        local handle, waiting = clip_handle(clip, source, gltfs)
        waits = waits or waiting
        if handle then
            names[#names + 1] = clip
            handles[clip] = handle
        elseif not waiting and not unresolved_said[clip] then
            unresolved_said[clip] = true
            print(string.format("[ANIMATION/CLIP] '%s' is neither an asset path (<file>#Animation<N>) nor an animation of its node's glTF: it plays nothing", clip))
        end
    end
    table.sort(names)
    return names, handles, waits
end

--- The AnimationPlayer a node plays on: its own, or the first under it, from a query naming it `Mut`.
local function player_of(players, node)
    return players:iter_many_mut({ node })[1] or players:iter_many_mut(players:iter_descendants(node))[1]
end

-- What a node's clips are read from, on its clips arriving or changing: each file asked for once,
-- and kept while a clip names it.
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = { added = { "animation/clip" }, changed = { "animation/clip" } },
        optional = { "animation/clip/source" },
    }],
    Query[{ with = { "SceneRoot" } }],
    Res[AssetServer],
    Commands,
}, function(changed, scenes, asset_server, commands)
    for _, e in ipairs(changed:iter()) do
        local had = e:get("animation/clip/source")
        local before = had and had.clips or {}
        local file, clips, differs = had and had.file, {}, had == nil
        local named = false
        for clip in pairs(e:get("animation/clip").clips or {}) do
            if is_path(clip) then
                clips[clip] = before[clip] or asset_server:load(clip)
                differs = differs or before[clip] == nil
            else
                named = true
            end
        end
        for clip in pairs(before) do
            differs = differs or clips[clip] == nil
        end
        if named and file == nil then
            local path = scene_file(scenes, e:id())
            if path ~= nil then file, differs = asset_server:load(path), true end
        elseif not named and file ~= nil then
            file, differs = nil, true
        end
        if differs then
            commands:entity(e:id()):insert({ ["animation/clip/source"] = { file = file, clips = clips } })
        end
    end
end):in_set("animation/clip/source"):before("animation/clip/graph")

-- A file that does not load: said once, and its clips play nothing.
app:add_systems(First, {
    bevy.MessageReader[UntypedAssetLoadFailedEvent],
    Query[{ with = { "animation/clip/source" } }],
}, function(failed, sources)
    for _, failure in ipairs(failed:read()) do
        local path = without_label(sourceless(failure.path))
        for _, e in ipairs(sources:iter()) do
            local source = e:get("animation/clip/source")
            local named = source.file ~= nil and without_label(sourceless(source.file:path())) == path
            -- a clip's handle is a path value until its file loads: its path is its key
            for clip in pairs(source.clips or {}) do
                named = named or without_label(sourceless(clip)) == path
            end
            if named and not unresolved_said[path] then
                unresolved_said[path] = true
                print(string.format("[ANIMATION/CLIP] '%s' did not load: the clips it holds play nothing", path))
            end
        end
    end
end):in_set("animation/clip/failed")

--- The handles of the assets that finished loading this run, from an AssetEvent reader and the
--- assets it names (ResMut, for get_strong_handle): a handle compares with ==, an id does not.
local function loaded(reader, assets)
    local handles = {}
    for _, ev in ipairs(reader:read()) do
        local done = type(ev) == "table" and ev.LoadedWithDependencies or nil
        local handle = done and assets:get_strong_handle(done.id)
        if handle ~= nil then handles[#handles + 1] = handle end
    end
    return handles
end

local function among(handles, handle)
    for _, h in ipairs(handles) do
        if h == handle then return true end
    end
    return false
end

-- The graph, a node per clip: built when the node arrives, and again when the set of clips it
-- names changes, or when a scene's file it waits for loads. A player already linked gets the new
-- graph, and what it played under the old one stops, as its graph nodes no longer mean the same
-- clips.
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = { changed = { "animation/clip", "animation/clip/source" } },
        with = { "animation/clip", "animation/clip/source" },
    }],
    Query[{ with = { "animation/clip", "animation/clip/source" }, optional = { "animation/clip/graph" } }],
    bevy.MessageReader[AssetEvent[Gltf]],
    Query[{ with = { Mut["AnimationPlayer"] } }],
    ResMut[Assets[Gltf]],
    ResMut[Assets[AnimationGraph]],
    Commands,
}, function(changed, carriers, files, players, gltfs, graphs, commands)
    local touched = {}
    for _, e in ipairs(changed:iter()) do touched[#touched + 1] = e:id() end
    local arrived = loaded(files, gltfs)
    if #arrived > 0 then
        for _, e in ipairs(carriers:iter()) do
            if among(arrived, e:get("animation/clip/source").file) then touched[#touched + 1] = e:id() end
        end
    end
    local done = {}
    for _, e in ipairs(carriers:iter_many(touched)) do
        if done[e:id()] then goto next_node end
        done[e:id()] = true
        local names, handles = resolved(e:get("animation/clip").clips, e:get("animation/clip/source"), gltfs)
        local built = (e:get("animation/clip/graph") or {}).nodes
        local same = built ~= nil
        for _, clip in ipairs(names) do
            same = same and built[clip] ~= nil
        end
        local count = 0
        for _ in pairs(built or {}) do count = count + 1 end
        same = same and count == #names
        if not same then
            local graph, nodes = AnimationGraph.new(), {}
            for _, clip in ipairs(names) do
                nodes[clip] = graph:add_clip(handles[clip], 1.0, graph.root)
            end
            local handle = graphs:add(graph)
            -- `insert`, not `patch`: a patch merges into the old `nodes`, so a clip taken out
            -- would stay listed
            commands:entity(e:id()):insert({ ["animation/clip/graph"] = { handle = handle, nodes = nodes } })
            local player = player_of(players, e:id())
            if player then
                player.AnimationPlayer:stop_all()
                commands:entity(player:id()):insert({ AnimationGraphHandle = handle })
            end
        end
        ::next_node::
    end
end):in_set("animation/clip/graph")

-- A player the node's scene spawned, given the graph of the nearest node at or above it.
app:add_systems(PostUpdate, {
    Query[{ added = { "AnimationPlayer" } }],
    Query[{ with = { "animation/clip", "animation/clip/graph" } }],
    Commands,
}, function(players, nodes, commands)
    for _, p in ipairs(players:iter()) do
        local node = nodes:iter_many({ p:id() })[1] or nodes:iter_many(nodes:iter_ancestors(p:id()))[1]
        if node then
            commands:entity(p:id()):insert({ AnimationGraphHandle = node:get("animation/clip/graph").handle })
        end
    end
end):in_set("animation/clip/link"):after("animation/clip/graph")


--- The node's clips on its player. A clip starting (newly weighted, first reaching the player, or
--- a finished one started again) starts at the node's seek; with `seeking`, every playing clip
--- moves to it. A clip whose length is not known yet (its file not loaded) starts where it would.
local function apply(e, player, clips, with, seeking)
    local wanted = e:get("animation/clip")
    local seek = e:get("animation/clip/seek")
    local to = seek and seek.to
    local speed = wanted.speed
    local loops = wanted["repeat"] == true
    for clip, index in pairs(e:get("animation/clip/graph").nodes) do
        local weight = (wanted.clips or {})[clip] or 0
        local active = player.AnimationPlayer:animation(index)
        local handle = clip_handle(clip, e:get("animation/clip/source") or {}, with.gltfs)
        local asset = handle and clips:get(handle) or nil
        local duration = asset and asset.duration or nil
        local at = to ~= nil and Clip.place(to, duration) or nil
        if weight <= 0 then
            if active then player.AnimationPlayer:stop(index) end
        elseif active == nil then
            player.AnimationPlayer:play(index, { weight = weight, speed = speed, ["repeat"] = loops or nil, seek_to = at })
        else
            local finished = active["repeat"] == "Never" and active.completions >= 1
            local turned = (speed < 0) ~= (active.speed < 0)
            if (finished and turned) or (active["repeat"] == "Forever") ~= loops then
                local from = at or math.max(0, math.min(active.seek_time, duration or active.seek_time))
                player.AnimationPlayer:stop(index)
                player.AnimationPlayer:play(index, { weight = weight, speed = speed, ["repeat"] = loops or nil, seek_to = from })
            else
                player.AnimationPlayer:play(index, { weight = weight, speed = speed, seek_to = seeking and at or nil })
            end
        end
    end
end

-- The clips on the player: when the node's clips, weights, speed or graph change, or its player
-- gets its graph, and with a seek when `animation/clip/seek` arrives or changes. Bevy stops
-- advancing a clip that does not repeat once it reaches an end, so a finished one asked to go the
-- other way, or one asked to repeat otherwise, starts again, at the seek or else where it stands.
-- A seek that waits for a clip's length is sought again when the length arrives (below).
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = { changed = { "animation/clip", "animation/clip/graph" } },
        with = { "animation/clip", "animation/clip/graph" },
    }],
    Query[{
        ["or"] = { added = { "animation/clip/seek" }, changed = { "animation/clip/seek" } },
        with = { "animation/clip", "animation/clip/graph" },
    }],
    Query[{ added = { "AnimationGraphHandle" }, with = { "AnimationPlayer" } }],
    Query[{
        with = { "animation/clip", "animation/clip/graph" },
        optional = { "animation/clip/seek", "animation/clip/source" },
    }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
    Res[Assets[AnimationClip]],
    Res[Assets[Gltf]],
}, function(changed, sought, linked, all, players, clips, gltfs)
    local with = { gltfs = gltfs }
    local touched, seeking = {}, {}
    for _, e in ipairs(changed:iter()) do touched[#touched + 1] = e:id() end
    for _, e in ipairs(sought:iter()) do
        touched[#touched + 1] = e:id()
        seeking[e:id()] = true
    end
    for _, p in ipairs(linked:iter()) do
        local node = all:iter_many({ p:id() })[1] or all:iter_many(all:iter_ancestors(p:id()))[1]
        if node then touched[#touched + 1] = node:id() end
    end
    local done = {}
    for _, e in ipairs(all:iter_many(touched)) do
        local player = not done[e:id()] and player_of(players, e:id())
        done[e:id()] = true
        if player then apply(e, player, clips, with, seeking[e:id()] == true) end
    end
end):in_set("animation/clip/play"):after("animation/clip/link")

-- A file the node's clips wait for has loaded. A clip named by its asset path was asked for as a
-- path value: the loaded handle, which equals it, takes its place in the source. A node with a seek
-- whose weighted clip, or whose scene's file, just loaded is sought again, its length known now.
app:add_systems(PostUpdate, {
    bevy.MessageReader[AssetEvent[AnimationClip]],
    bevy.MessageReader[AssetEvent[Gltf]],
    Query[{
        with = { "animation/clip", "animation/clip/source" },
        optional = { "animation/clip/seek", "animation/clip/graph" },
    }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
    ResMut[Assets[AnimationClip]],
    ResMut[Assets[Gltf]],
    Commands,
}, function(clip_files, scene_files, nodes, players, clips, gltfs, commands)
    local arrived_clips, arrived_files = loaded(clip_files, clips), loaded(scene_files, gltfs)
    if #arrived_clips + #arrived_files == 0 then return end
    for _, e in ipairs(nodes:iter()) do
        local source = e:get("animation/clip/source")
        local weights = e:get("animation/clip").clips or {}
        local waited = among(arrived_files, source.file)
        local upgraded, kept = false, {}
        for clip, handle in pairs(source.clips or {}) do
            kept[clip] = handle
            for _, h in ipairs(arrived_clips) do
                if h == handle then
                    kept[clip], upgraded = h, true
                    waited = waited or (weights[clip] or 0) > 0
                end
            end
        end
        if upgraded then
            commands:entity(e:id()):insert({ ["animation/clip/source"] = { file = source.file, clips = kept } })
        end
        local player = waited and e:has("animation/clip/seek") and e:has("animation/clip/graph") and player_of(players, e:id())
        if player then apply(e, player, clips, { gltfs = gltfs }, true) end
    end
end):in_set("animation/clip/loaded"):after("animation/clip/play")

return {
    defaults = {
        ["animation/clip"] = {
            clips = {},
            speed = 1,
            ["repeat"] = false,
        },
    },
}
