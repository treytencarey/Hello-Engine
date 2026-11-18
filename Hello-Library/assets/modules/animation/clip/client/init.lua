-- Clips playing on a node: the base every skeletal animation plays through. A node carrying
-- `animation/clip` plays its clips on the AnimationPlayer at that node or under it (Bevy's glTF
-- loader puts the player on the animation's root node), each at its weight, all at one speed.
-- Missing fields get defaults when it is added.
--
-- animation/clip = {
--     clips = { [<clip>] = <weight>, ... },
--     speed = <1 plays forward, -1 backward, 0 pauses; any other value scales>,
--     repeat = <true loops; false holds the end it reaches>,
-- }
--
-- A clip is an asset path, `<file>#Animation<N>`. A clip that newly has a weight starts from its
-- start, which a negative speed holds; one that keeps a weight plays on, taking the new weight and
-- speed; one whose weight goes to 0, or that is taken out, stops.
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

--- The asset a clip names, or nil. An animation named in the node's own glTF resolves here once
--- a glTF's animations can be read; until then a name plays nothing.
local function resolve(clip)
    if clip:find("#", 1, true) then return clip end
    return nil
end

local unresolved_said = {}

--- The node's clips that resolve, in a stable order.
local function resolved(clips)
    local names = {}
    for clip in pairs(clips or {}) do
        if resolve(clip) then
            names[#names + 1] = clip
        elseif not unresolved_said[clip] then
            unresolved_said[clip] = true
            print(string.format("[ANIMATION/CLIP] '%s' is not an asset path (<file>#Animation<N>): it plays nothing", clip))
        end
    end
    table.sort(names)
    return names
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
    Res[AssetServer],
    ResMut[Assets[AnimationGraph]],
    Commands,
}, function(changed, players, asset_server, graphs, commands)
    for _, e in ipairs(changed:iter()) do
        local names = resolved(e:get("animation/clip").clips)
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
                nodes[clip] = graph:add_clip(asset_server:load(resolve(clip)), 1.0, graph.root)
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

-- The clips on the player, when the node's clips, weights, speed or graph change, or its player
-- gets its graph. Bevy stops advancing a clip that does not repeat once it reaches an end, so a
-- finished one asked to go the other way, or one asked to repeat otherwise, starts again from
-- where it stands.
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = { changed = { "animation/clip", "animation/clip/graph" } },
        with = { "animation/clip", "animation/clip/graph" },
    }],
    Query[{ added = { "AnimationGraphHandle" }, with = { "AnimationPlayer" } }],
    Query[{ with = { "animation/clip", "animation/clip/graph" } }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
    Res[Assets[AnimationClip]],
    Res[AssetServer],
}, function(changed, linked, all, players, clips, asset_server)
    local touched = {}
    for _, e in ipairs(changed:iter()) do touched[#touched + 1] = e:id() end
    for _, p in ipairs(linked:iter()) do
        local node = all:iter_many({ p:id() })[1] or all:iter_many(all:iter_ancestors(p:id()))[1]
        if node then touched[#touched + 1] = node:id() end
    end
    for _, e in ipairs(all:iter_many(touched)) do
        local wanted = e:get("animation/clip")
        local nodes = e:get("animation/clip/graph").nodes
        local player = player_of(players, e:id())
        if player then
            local speed = wanted.speed
            local loops = wanted["repeat"] == true
            for clip, index in pairs(nodes) do
                local weight = (wanted.clips or {})[clip] or 0
                local active = player.AnimationPlayer:animation(index)
                local asset = clips:get(asset_server:load(resolve(clip)))
                local duration = asset and asset.duration or 0
                if weight <= 0 then
                    if active then player.AnimationPlayer:stop(index) end
                elseif active == nil then
                    player.AnimationPlayer:play(index, { weight = weight, speed = speed, ["repeat"] = loops or nil })
                else
                    local finished = active["repeat"] == "Never" and active.completions >= 1
                    local turned = (speed < 0) ~= (active.speed < 0)
                    if (finished and turned) or (active["repeat"] == "Forever") ~= loops then
                        local at = math.max(0, math.min(active.seek_time, duration))
                        player.AnimationPlayer:stop(index)
                        player.AnimationPlayer:play(index, {
                            weight = weight, speed = speed, ["repeat"] = loops or nil, seek_to = at,
                        })
                    else
                        player.AnimationPlayer:play(index, { weight = weight, speed = speed })
                    end
                end
            end
        end
    end
end):in_set("animation/clip/play"):after("animation/clip/link")

return {
    defaults = {
        ["animation/clip"] = {
            clips = {},
            speed = 1,
            ["repeat"] = false,
        },
    },
}
