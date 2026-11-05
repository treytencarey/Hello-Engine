-- One walkable box from numbers, for a map with no authored node to mark: a child entity with
-- an `ai/nav/volume`, which `ai/nav/volumes` bakes. Missing fields get defaults when it is added.
-- A change moves the same child.
--
-- ai/nav/volumes/box = {
--     hx = <half extent, required>,
--     hz = <half extent, required>,
--     hy = <half height: the floor is at y - hy>,
--     x = <centre, relative to the entity>,
--     y = <centre, relative to the entity>,
--     z = <centre, relative to the entity>,
-- }
--
-- ai/nav/volumes/box/volume: marks its child

app:add_systems(First, {
    Query[{
        changed = { "ai/nav/volumes/box" },
        optional = { "Children" },
    }],
    Query[{ with = { "ai/nav/volumes/box/volume", Mut["ai/nav/volume"], Mut["Transform"] } }],
    Query[{ with = { "ai/nav/volumes/box/volume" }, without = { "ai/nav/volume" } }],
    Commands,
}, function(boxes, children, swept, commands)
    for _, e in ipairs(boxes:iter()) do
        local b = e:get("ai/nav/volumes/box")
        if b.hx and b.hz then
            local child = children:iter_many_mut(e:get("Children") or {})[1]
            local bare = swept:iter_many(e:get("Children") or {})[1]
            if child ~= nil then
                child:patch({
                    ["ai/nav/volume"] = { hx = b.hx, hy = b.hy, hz = b.hz },
                    Transform = { translation = { x = b.x, y = b.y, z = b.z } },
                })
            elseif bare ~= nil then
                -- `ai/nav` left, and took the child's volume with it
                commands:entity(bare:id()):insert({ ["ai/nav/volume"] = { hx = b.hx, hy = b.hy, hz = b.hz } })
            else
                commands:spawn({
                    ["ai/nav/volumes/box/volume"] = {},
                    ["ai/nav/volume"] = { hx = b.hx, hy = b.hy, hz = b.hz },
                    Transform = { translation = { x = b.x, y = b.y, z = b.z } },
                    ChildOf = e:id(),
                })
            end
        end
    end
end):in_set("ai/nav/volumes/box/spawn")

-- `ai/nav` takes `ai/nav/volume` off everything when its last carrier leaves, so it's added again
-- when the mod arrives. `ai/nav/volumes` then bakes it.
app:add_systems(First, {
    Query[{ added = { "ai/nav" } }],
    Query[{ with = { "ai/nav/volumes/box" }, optional = { "Children" } }],
    Query[{ with = { "ai/nav/volumes/box/volume" }, without = { "ai/nav/volume" } }],
    Commands,
}, function(arrived, boxes, swept, commands)
    if arrived:is_empty() then return end
    for _, e in ipairs(boxes:iter()) do
        local b = e:get("ai/nav/volumes/box")
        for _, child in ipairs(swept:iter_many(e:get("Children") or {})) do
            commands:entity(child:id()):insert({ ["ai/nav/volume"] = { hx = b.hx, hy = b.hy, hz = b.hz } })
        end
    end
end):in_set("ai/nav/volumes/box/return")

return {
    base = "ai/nav/volumes",
    defaults = {
        ["ai/nav/volumes/box"] = { hy = 0, x = 0, y = 0, z = 0 },
    },
}
