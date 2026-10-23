-- The client half: each character's model and the clip it plays, built per entity.
--
-- A character's model is a child (`animation/model`) holding its scene, and its clips are
-- nodes of its own graph (`animation/graph`). Both hold asset handles, which Bevy refills in
-- place when a file changes or arrives, so a file change rebuilds nothing
-- here. A change to `animation` replaces only what it names anew: a new scene replaces the
-- model, new clips rebuild the graph. The scene spawns its own AnimationPlayer, which is
-- given its character's graph and marked `animation/player`. The clip to play comes from
-- the character's motion on this client, or from `animation/action` while that is there.
--
-- animation/model = { scene = <the scene's path> }: the child holding the model's scene.
-- animation/graph = {
--     handle = <the AnimationGraph>,
--     nodes = { <state> = <node index> },
--     clips = { <state> = <the clip's path> },
-- }
-- animation/player = { state, graph }: on the AnimationPlayer the model's scene spawned, what it
--     last started (empty until it starts one).
-- animation/motion = { at = { x, y, z } }: where the character was last frame.
-- animation/playing = { state = <name>, speed = <playback speed> }: what it should play.

local app = ...
local AssetServer = require("bevy::asset::AssetServer")
local Time = require("bevy::time::Time")

-- Its model, once its fields are filled in: spawned on add, replaced when the scene changes.
app:add_systems(First, {
    Query[{
        changed = { "animation" },
        optional = { "Children" },
    }],
    Query[{ with = { "animation/model" } }],
    Res[AssetServer],
    Commands,
}, function(changed, models, asset_server, commands)
    for _, e in ipairs(changed:iter()) do
        local a = e:get("animation")
        if a.model and a.scene and a.offset then
            local scene = a.model .. a.scene
            local children = e:get("Children") or {}
            local model = models:iter_many(children)[1]
            if model == nil or model:get("animation/model").scene ~= scene then
                if model then commands:entity(model:id()):despawn() end
                commands:spawn({
                    ["animation/model"] = { scene = scene },
                    SceneRoot = asset_server:load(scene),
                    Transform = { translation = a.offset },
                }):insert({ ChildOf = e:id() })
            end
        end
    end
end):in_set("animation/model")

-- Its graph, a node per clip: built on add, rebuilt when a clip changes. Every clip, the
-- first included, is added under the root from node 2, so each plays from its start.
-- An AnimationGraph with clips cannot be built through `Assets<AnimationGraph>` from Lua yet
-- (its graph is opaque to reflection, and `add_clip` is reached only as an asset method), so
-- this system takes the World and builds it as before.
app:add_systems(First, { World }, function(world)
    for _, e in ipairs(world:query({ changed = { "animation" }, optional = { "animation/graph" } })) do
        local a = e:get("animation")
        if a.model and a.clips then
            local built = (e:get("animation/graph") or {}).clips or {}
            local same = true
            for state, suffix in pairs(a.clips) do
                same = same and built[state] == a.model .. suffix
            end
            for state in pairs(built) do
                same = same and a.clips[state] ~= nil
            end
            if not same or not e:has("animation/graph") then
                local graph, nodes, clips, next_node = nil, {}, {}, 2
                for state, suffix in pairs(a.clips) do
                    local clip = load_asset(a.model .. suffix)
                    graph = graph or create_asset("AnimationGraph", { clip = clip })
                    world:call_asset_method(graph, "AnimationGraph", "add_clip", clip, 1.0, 0)
                    nodes[state], clips[state] = next_node, a.model .. suffix
                    next_node = next_node + 1
                end
                -- `set`, not `patch`: a patch merges into the old `nodes` and `clips`, so a clip
                -- taken out would stay listed
                e:set({ ["animation/graph"] = { handle = graph, nodes = nodes, clips = clips } })
                local player = world:query({
                    with = { "animation/player" },
                    iter_many = world:descendants(e:id()),
                    limit = 1,
                })[1]
                if player then world:get_entity(player:id()):set({ AnimationGraphHandle = graph }) end
            end
        end
    end
end):in_set("animation/graph")

-- The scene's AnimationPlayer, linked to its character's graph: the nearest ancestor that
-- carries one.
app:add_systems(First, {
    Query[{ added = { "AnimationPlayer" } }],
    Query[{ with = { "animation", "animation/graph" } }],
    Commands,
}, function(players, carriers, commands)
    for _, p in ipairs(players:iter()) do
        local carrier = carriers:iter_many(carriers:iter_ancestors(p:id()))[1]
        if carrier then
            commands:entity(p:id()):insert({
                AnimationTransitions = {},
                ["animation/player"] = {},
                AnimationGraphHandle = carrier:get("animation/graph").handle,
            })
        end
    end
end):in_set("animation/link"):after("animation/graph")

-- What it is doing: from its body's velocity when it has one (physics moves a body in fixed
-- steps, so most frames show no movement), else from how it moved since last frame. Motion
-- is followed every frame.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "animation", "animation/graph", "Transform" },
        optional = { "animation/motion", "animation/playing", "animation/action", "Velocity3d" },
    }],
    Commands,
}, function(time, characters, commands)
    local dt = time:delta_secs()
    if dt <= 0 then return end
    for _, e in ipairs(characters:iter()) do
        local a = e:get("animation")
        local at = e:get("Transform").translation
        local vx, vy, vz
        local body = e:get("Velocity3d")
        if body and body.linvel then
            vx, vy, vz = body.linvel.x or 0, body.linvel.y or 0, body.linvel.z or 0
        else
            local last = (e:get("animation/motion") or {}).at or at
            vx, vy, vz = (at.x - last.x) / dt, (at.y - last.y) / dt, (at.z - last.z) / dt
        end
        local state, speed = "idle", 1
        local action = e:get("animation/action")
        if action and action.state then
            state, speed = action.state, action.speed or 1
        elseif vy < -1 then
            state = "fall"
        elseif vy > 1 then
            state = "jump"
        else
            local horizontal = math.sqrt(vx * vx + vz * vz)
            if horizontal > 0.1 then
                state = "walk"
                speed = math.max(0.3, math.min(2, horizontal / a.walk_speed))
            end
        end
        local playing = e:get("animation/playing") or {}
        commands:entity(e:id()):patch({ ["animation/motion"] = { at = { x = at.x, y = at.y, z = at.z } } })
        if playing.state ~= state or playing.speed ~= speed then
            commands:entity(e:id()):patch({ ["animation/playing"] = { state = state, speed = speed } })
        end
    end
end):in_set("animation/state")

-- The clip its player plays, when what it should play changes (its state, its speed or its
-- graph) or a new player appears. What a player last started is kept on it
-- (`animation/player`): a new state or graph crossfades into its clip from the start, and the
-- same state at a new speed only changes the running clip's speed (a restart on every speed
-- change kept a clip from ever reaching its end). A new player has started nothing.
app:add_systems(Update, {
    Query[{
        ["or"] = { changed = { "animation/playing", "animation/graph" } },
        with = { "animation" },
    }],
    Query[{ added = { "animation/player" } }],
    Query[{ with = { "animation" } }],
    Query[{ with = { "animation", "animation/playing", "animation/graph" } }],
    Query[{ with = { Mut["animation/player"], Mut["AnimationTransitions"], Mut["AnimationPlayer"] } }],
}, function(changed, new_players, owners, characters, players)
    local carriers = {}
    for _, e in ipairs(changed:iter()) do
        carriers[#carriers + 1] = e:id()
    end
    for _, p in ipairs(new_players:iter()) do
        local carrier = owners:iter_many(owners:iter_ancestors(p:id()))[1]
        if carrier then carriers[#carriers + 1] = carrier:id() end
    end
    for _, e in ipairs(characters:iter_many(carriers)) do
        local playing = e:get("animation/playing")
        local graph = e:get("animation/graph")
        local node = graph.nodes[playing.state] or graph.nodes.idle
        local player = players:iter_many_mut(players:iter_descendants(e:id()))[1]
        if player and node then
            local started = player:get("animation/player")
            local options = { speed = playing.speed or 1, ["repeat"] = true }
            if started.state == playing.state and started.graph == graph.handle then
                player.AnimationPlayer:play(node, options)
            else
                player.AnimationTransitions:play(node, 0.2, options)
                player:set({ ["animation/player"] = { state = playing.state, graph = graph.handle } })
            end
        end
    end
end):in_set("animation/play"):after("animation/state")
