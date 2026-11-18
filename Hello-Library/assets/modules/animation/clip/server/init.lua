-- The server half of `animation/clip`: it publishes where each animated scene node stands. Each
-- side spawns its own copy of a scene, so the node's `Name`, unique in a map, is what the two share:
-- the server spawns one synced record per animated scene node, and each client copies it onto its
-- own copy of the node.
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

--- Is the carrier a scene node, one the clients spawn copies of: named, and not replicated.
local function scene_node(e)
    local sync = e:get("core/net/sync")
    return e:has("Name") and not (type(sync) == "table" and sync["animation/clip"] ~= nil)
end

--- Where a node stands: the one place publishing reads it from. Its query names
--- `animation/clip/seek`.
local function position(e)
    local seek = e:get("animation/clip/seek")
    return seek and seek.to or 0
end

-- An animated scene node arriving: its record, from where the node stands.
app:add_systems(First, {
    Query[{ added = { "animation/clip" }, optional = { "Name", "core/net/sync", "animation/clip/seek" } }],
    Query[{ with = { "animation/clip/node" } }],
    Commands,
}, function(arrived, records, commands)
    local held = {}
    for _, r in ipairs(records:iter()) do held[r:get("animation/clip/node").name] = r end
    for _, e in ipairs(arrived:iter()) do
        if scene_node(e) then
            local name = e:get("Name").name
            local value = { name = name, speed = e:get("animation/clip").speed, time = position(e) }
            if held[name] then
                commands:entity(held[name]:id()):insert({ ["animation/clip/node"] = value })
            else
                commands:spawn({
                    ["animation/clip/node"] = value,
                    ["core/net/sync"] = { ["animation/clip/node"] = { authority = "server" } },
                    ["core/script/owner"] = false,
                })
            end
            moving = moving or value.speed ~= 0
        end
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

-- Publishing: a node's record is written when its speed changes, and on each half-second beat
-- while it moves. It polls only while a node moves, or one's clip changed.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "animation/clip" }, optional = { "Name", "core/net/sync", "animation/clip/seek" } }],
    Query[{ with = { "animation/clip/node" } }],
    Commands,
}, function(time, nodes, records, commands)
    beat = beat + time:delta_secs()
    local on_beat = beat >= PUBLISH
    if on_beat then beat = 0 end
    local by_name = {}
    for _, r in ipairs(records:iter()) do by_name[r:get("animation/clip/node").name] = r end
    moving = false
    for _, e in ipairs(nodes:iter()) do
        local record = scene_node(e) and by_name[e:get("Name").name]
        if record then
            local speed = e:get("animation/clip").speed
            local r = record:get("animation/clip/node")
            if r.speed ~= speed or (on_beat and speed ~= 0) then
                commands:entity(record:id()):insert({ ["animation/clip/node"] = { name = r.name, speed = speed, time = position(e) } })
            end
            moving = moving or speed ~= 0
        end
    end
end):in_set("animation/clip/publish"):run_if({
    Query[{ changed = { "animation/clip" } }],
}, function(changed)
    return moving or not changed:is_empty()
end)
