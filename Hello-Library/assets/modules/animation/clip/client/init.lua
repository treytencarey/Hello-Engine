-- Clips playing on a node: the base every skeletal animation plays through. A node carrying
-- `animation/clip` plays its clips on the AnimationPlayer at that node or under it (Bevy's glTF
-- loader puts the player on the animation's root node), each at its weight, all at one speed.
--
-- A clip is an asset path, `<file>#Animation<N>`, or the name of an animation in the glTF the
-- node's scene came from (the nearest `SceneRoot` at or above it). A clip that newly has a weight
-- starts at the node's `animation/clip/seek`, or else from its start, which a negative speed
-- holds; one that keeps a weight plays on, taking the new weight and speed; one whose weight goes
-- to 0, or that is taken out, stops. `animation/clip/seek` arriving or changing moves every playing clip to it.
--
-- animation/clip/graph = {
--     handle = <the node's AnimationGraph>,
--     nodes = { [<clip>] = <the graph node playing it> },
-- }: on the node, this client only. Built for the set of clips the node names, and built again
-- when that set changes, so a node that fades between clips lists all of them, at 0 when silent.

local AssetServer = require("bevy::asset::AssetServer")
local Assets = require("bevy::asset::Assets")
local AnimationGraph = require("bevy::animation::graph::AnimationGraph")
local AnimationClip = require("bevy::animation::AnimationClip")
local Gltf = require("bevy::gltf::prelude::Gltf")
local Clip = require("modules/animation/clip/shared/clip.lua")

--- The handle a node's clip names, or nil: an asset path loads; any other name is an animation of
--- the glTF the node's scene came from, its `SceneRoot`'s path without its label. A second answer
--- says the name waits for that glTF to load. `with` holds `scenes` (a query naming
--- `SceneRoot`), `gltfs` and `asset_server`.
local function clip_handle(clip, node, with)
    if clip:find("#", 1, true) then return with.asset_server:load(clip), false end
    local root = with.scenes:iter_many({ node })[1] or with.scenes:iter_many(with.scenes:iter_ancestors(node))[1]
    if root == nil then return nil, false end
    local path = tostring(root:get("SceneRoot"):path()):gsub("#.*$", "")
    local gltf = with.gltfs:get(with.asset_server:load(path))
    if gltf == nil then return nil, true end
    return gltf.named_animations and gltf.named_animations[clip] or nil, false
end

local unresolved_said = {}

--- The node's clips that resolve, in a stable order, and their handles; and whether a name waits
--- for its glTF to load.
local function resolved(clips, node, with)
    local names, handles, waits = {}, {}, false
    for clip in pairs(clips or {}) do
        local handle, waiting = clip_handle(clip, node, with)
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

-- The graph, a node per clip: built when the node arrives, and again when the set of clips it
-- names changes. A player already linked gets the new graph, and what it played under the old
-- one stops, as its graph nodes no longer mean the same clips.
app:add_systems(PostUpdate, {
    Query[{ changed = { "animation/clip" }, optional = { "animation/clip/graph" } }],
    Query[{ with = { Mut["AnimationPlayer"] } }],
    Query[{ with = { "SceneRoot" } }],
    Res[Assets[Gltf]],
    Res[AssetServer],
    ResMut[Assets[AnimationGraph]],
    Commands,
}, function(changed, players, scenes, gltfs, asset_server, graphs, commands)
    local with = { scenes = scenes, gltfs = gltfs, asset_server = asset_server }
    for _, e in ipairs(changed:iter()) do
        local names, handles, waits = resolved(e:get("animation/clip").clips, e:id(), with)
        -- a name whose glTF has not loaded: written again, so its own edge tries it next frame
        if waits then commands:entity(e:id()):insert({ ["animation/clip"] = e:get("animation/clip") }) end
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
--- moves to it. Answers false when the seek waits for a clip's length (its file not loaded yet).
local function apply(e, player, clips, with, seeking)
    local wanted = e:get("animation/clip")
    local seek = e:get("animation/clip/seek")
    local to = seek and seek.to
    local speed = wanted.speed
    local loops = wanted["repeat"] == true
    local placed = true
    for clip, index in pairs(e:get("animation/clip/graph").nodes) do
        local weight = (wanted.clips or {})[clip] or 0
        local active = player.AnimationPlayer:animation(index)
        local handle = clip_handle(clip, e:id(), with)
        local asset = handle and clips:get(handle) or nil
        local duration = asset and asset.duration or nil
        local at = to ~= nil and Clip.place(to, duration) or nil
        if weight > 0 and to ~= nil and at == nil then placed = false end
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
    return placed
end

-- The clips on the player: when the node's clips, weights, speed or graph change, or its player
-- gets its graph, and with a seek when `animation/clip/seek` arrives or changes. Bevy stops
-- advancing a clip that does not repeat once it reaches an end, so a finished one asked to go the
-- other way, or one asked to repeat otherwise, starts again, at the seek or else where it stands.
-- A seek that waits for a clip's length writes its seek again, so its own edge tries it next frame.
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
    Query[{ with = { "animation/clip", "animation/clip/graph" }, optional = { "animation/clip/seek" } }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
    Query[{ with = { "SceneRoot" } }],
    Res[Assets[AnimationClip]],
    Res[Assets[Gltf]],
    Res[AssetServer],
    Commands,
}, function(changed, sought, linked, all, players, scenes, clips, gltfs, asset_server, commands)
    local with = { scenes = scenes, gltfs = gltfs, asset_server = asset_server }
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
        if player and not apply(e, player, clips, with, seeking[e:id()] == true) then
            commands:entity(e:id()):insert({ ["animation/clip/seek"] = { to = e:get("animation/clip/seek").to } })
        end
    end
end):in_set("animation/clip/play"):after("animation/clip/link")

-- A scene node the server drives: its record (`animation/clip/node`, from the server) arriving or
-- changing, or the node arriving after it, puts the server's speed on this side's copy of the node
-- and its time in the node's seek. The client runs no clock.
app:add_systems(First, {
    Query[{
        ["or"] = { added = { "animation/clip/node" }, changed = { "animation/clip/node" } },
    }],
    Query[{ added = { "animation/clip" }, with = { "Name" } }],
    Query[{ with = { "animation/clip/node" } }],
    Query[{ with = { Mut["animation/clip"], "Name" } }],
    Commands,
}, function(changed, arrived, records, nodes, commands)
    local moved = {}
    for _, r in ipairs(changed:iter()) do moved[r:get("animation/clip/node").name] = true end
    local fresh = {}
    for _, e in ipairs(arrived:iter()) do fresh[e:id()] = true end
    if next(moved) == nil and next(fresh) == nil then return end
    local by_name = {}
    for _, r in ipairs(records:iter()) do
        local record = r:get("animation/clip/node")
        by_name[record.name] = record
    end
    for _, e in ipairs(nodes:iter_mut()) do
        local name = e:get("Name").name
        local record = by_name[name]
        if record and (moved[name] or fresh[e:id()]) then
            if e:get("animation/clip").speed ~= record.speed then e:get_mut("animation/clip").speed = record.speed end
            commands:entity(e:id()):insert({ ["animation/clip/seek"] = { to = record.time } })
        end
    end
end):in_set("animation/clip/node")
