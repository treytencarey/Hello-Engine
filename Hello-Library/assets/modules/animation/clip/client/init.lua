-- The client half of `animation/clip`: a scene node the server drives plays here from the server's
-- record of it. The base itself, which builds the graph and plays the clips, is the shared half and
-- runs on both sides.

-- A scene node the server drives: its record (`animation/clip/node`, from the server) arriving or
-- changing, or the node arriving after it, puts the server's speed on this side's copy of the node
-- and its time in the node's seek.
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
