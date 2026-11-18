-- The server half of `animation/clip`: it publishes where each animated node stands, as the
-- server's own AnimationPlayer plays it (the base runs on both sides). Each side spawns its own copy
-- of a scene, so a scene node's `Name`, unique in a map, is what the two share: the server spawns
-- one synced record per animated scene node, and each client copies it onto its own copy of the
-- node. An entity the server replicates carries its own `animation/clip/seek`, synced as the mod
-- that spawns it declares, which this half writes.
--
-- animation/clip/node = {
--     name = <the node's Name>,
--     speed = <its animation/clip.speed>,
--     time = <where it stands, in seconds of clip time, or "end">,
-- }: one per animated scene node on the server, synced from the server, written when the speed
-- changes and every half second while the node moves.

local Time = require("bevy::time::Time")

-- How often a moving node's place is published, in seconds.
local PUBLISH = 0.5

-- Seconds since the last publishing beat, one beat for every node; and whether a node moved at the
-- last publish, as publishing polls while one does.
local beat, moving = 0, false

--- Is the carrier replicated: spawned with its `animation/clip` in a `core/net/sync` table.
local function replicated(e)
    local sync = e:get("core/net/sync")
    return type(sync) == "table" and sync["animation/clip"] ~= nil
end

--- Where a node stands: the one place publishing reads it from. Its player's furthest clip with a
--- weight, once the player plays one; else its `animation/clip/seek`. The node's query names
--- `animation/clip/graph` and `animation/clip/seek`; `players` names `AnimationPlayer`.
local function position(e, players)
    local graph = e:get("animation/clip/graph")
    local player = graph and players
        and (players:iter_many({ e:id() })[1] or players:iter_many(players:iter_descendants(e:id()))[1])
    if player then
        local wanted = e:get("animation/clip").clips or {}
        local at = nil
        for clip, index in pairs(graph.nodes) do
            local active = (wanted[clip] or 0) > 0 and player.AnimationPlayer:animation(index) or nil
            if active then at = math.max(at or 0, active.seek_time) end
        end
        if at then return at end
    end
    local seek = e:get("animation/clip/seek")
    return seek and seek.to or 0
end

-- An animated scene node arriving: its record, from where the node stands.
app:add_systems(First, {
    Query[{
        added = { "animation/clip" },
        optional = { "Name", "core/net/sync", "animation/clip/seek", "animation/clip/graph" },
    }],
    Query[{ with = { "animation/clip/node" } }],
    Commands,
}, function(arrived, records, commands)
    local held = {}
    for _, r in ipairs(records:iter()) do held[r:get("animation/clip/node").name] = r end
    for _, e in ipairs(arrived:iter()) do
        if e:has("Name") and not replicated(e) then
            local name = e:get("Name").name
            local value = { name = name, speed = e:get("animation/clip").speed, time = position(e, nil) }
            if held[name] then
                commands:entity(held[name]:id()):insert({ ["animation/clip/node"] = value })
            else
                commands:spawn({
                    ["animation/clip/node"] = value,
                    ["core/net/sync"] = { ["animation/clip/node"] = { authority = "server" } },
                    ["core/script/owner"] = false,
                })
            end
        end
        moving = moving or e:get("animation/clip").speed ~= 0
    end
end):in_set("animation/clip/node")

-- An animated node gone: a record no node's name holds any more goes. A gone row reads no `Name`.
app:add_systems(First, {
    Query[{ ["or"] = { removed = { "animation/clip" } } }],
    Query[{ with = { "animation/clip", "Name" } }],
    Query[{ with = { "animation/clip/node" } }],
    Commands,
}, function(gone, nodes, records, commands)
    if gone:is_empty() then return end
    local standing = {}
    for _, e in ipairs(nodes:iter()) do standing[e:get("Name").name] = true end
    for _, r in ipairs(records:iter()) do
        if not standing[r:get("animation/clip/node").name] then commands:entity(r:id()):despawn() end
    end
end):in_set("animation/clip/node")

-- Publishing, after the base has played this frame: a scene node's record, or a replicated
-- entity's `animation/clip/seek`, is written when its clip changes (its speed), and on each
-- half-second beat while it moves. It polls only while a node moves, or one's clip changed. A
-- replicated entity's seek written here is where its own player stood this frame, so the base's
-- seek on its edge, a frame later, sets it back by that frame at most.
app:add_systems(PostUpdate, {
    Res[Time],
    Query[{
        with = { "animation/clip" },
        optional = { "Name", "core/net/sync", "animation/clip/seek", "animation/clip/graph" },
    }],
    Query[{ changed = { "animation/clip" } }],
    Query[{ with = { "animation/clip/node" } }],
    Query[{ with = { "AnimationPlayer" } }],
    Commands,
}, function(time, nodes, changed, records, players, commands)
    beat = beat + time:delta_secs()
    local on_beat = beat >= PUBLISH
    if on_beat then beat = 0 end
    local fresh = {}
    for _, e in ipairs(changed:iter()) do fresh[e:id()] = true end
    local by_name = {}
    for _, r in ipairs(records:iter()) do by_name[r:get("animation/clip/node").name] = r end
    moving = false
    for _, e in ipairs(nodes:iter()) do
        local speed = e:get("animation/clip").speed
        if replicated(e) then
            if fresh[e:id()] or (on_beat and speed ~= 0) then
                commands:entity(e:id()):insert({ ["animation/clip/seek"] = { to = position(e, players) } })
            end
            moving = moving or speed ~= 0
        else
            local record = e:has("Name") and by_name[e:get("Name").name]
            if record then
                local r = record:get("animation/clip/node")
                if r.speed ~= speed or (on_beat and speed ~= 0) then
                    commands:entity(record:id()):insert({
                        ["animation/clip/node"] = { name = r.name, speed = speed, time = position(e, players) },
                    })
                end
                moving = moving or speed ~= 0
            end
        end
    end
end):in_set("animation/clip/publish"):after("animation/clip/play"):run_if({
    Query[{ changed = { "animation/clip" } }],
}, function(changed)
    return moving or not changed:is_empty()
end)
