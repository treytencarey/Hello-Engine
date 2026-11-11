-- A flat ground: the map entity becomes a fixed box players stand on, its top at y =
-- size.y / 2. The server and every client build the body from the synced `map/default`, so
-- only that component is synced; the client half draws it and lights it. Missing fields get
-- defaults when it is added; a change rebuilds the box.
--
-- map/default = {
--     size = { x = <metres>, y = <metres>, z = <metres> },
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
--     sun = <lux of the sunlight>,
-- }

-- A new or changed map: missing fields are filled in (which is itself a change, so the box
-- is built on the next run), or the entity becomes a fixed box of its size. `changed` also
-- fires when it is added.
app:add_systems(First, {
    Query[{ changed = { Mut["map/default"] } }],
    Commands,
}, function(maps, commands)
    for _, e in ipairs(maps:iter_mut()) do
        local m = e:get("map/default")
        if m.size == nil or m.color == nil or m.sun == nil then
            e:patch({
                ["map/default"] = {
                    size = m.size or { x = 100, y = 0.2, z = 100 },
                    color = m.color or { r = 0.3, g = 0.5, b = 0.3 },
                    sun = m.sun or 10000,
                },
            })
        else
            commands:entity(e:id()):patch({
                RigidBody3d = "Fixed",
                Collider3d = { cuboid = { hx = m.size.x / 2, hy = m.size.y / 2, hz = m.size.z / 2 } },
            })
        end
    end
end):in_set("map/default/ground")

-- The map's spawn point, on the centre of the box's top: `player/spawner` puts players only on a
-- point the map carries. A change of size moves it.
app:add_systems(First, {
    Query[{
        changed = { "map/default" },
        optional = { "Children" },
    }],
    Query[{ with = { "player/spawner/point", Mut["Transform"] } }],
    Commands,
}, function(maps, points, commands)
    for _, e in ipairs(maps:iter()) do
        local m = e:get("map/default")
        if m.size ~= nil then
            -- Bevy propagates a transform only through a chain where every link has one.
            commands:entity(e:id()):insert_if_new({ Transform = {} })
            local top = { x = 0, y = m.size.y / 2, z = 0 }
            local point = points:iter_many_mut(e:get("Children") or {})[1]
            if point ~= nil then
                point:get_mut("Transform").translation = top
            else
                commands:spawn({
                    Name = "map/default",
                    Transform = { translation = top },
                    ["player/spawner/point"] = {},
                    ChildOf = e:id(),
                })
            end
        end
    end
end):in_set("map/default/ground")

-- `map/default` was taken off an entity that stays: take off the body this mod added, and its
-- spawn point. `removed` also fires on despawn, so the removal must not fail on an entity that is
-- gone.
app:add_systems(First, {
    Query[{
        removed = { "map/default" },
        optional = { "Children" },
    }],
    Query[{ with = { "player/spawner/point" } }],
    Commands,
}, function(maps, points, commands)
    for _, e in ipairs(maps:iter()) do
        commands:entity(e:id()):try_remove("RigidBody3d", "Collider3d")
        for _, point in ipairs(points:iter_many(e:get("Children") or {})) do
            commands:entity(point:id()):try_despawn()
        end
    end
end):in_set("map/default/removed")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
