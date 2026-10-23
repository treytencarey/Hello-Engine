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

local app = ...

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

-- `map/default` was taken off an entity that stays: take off the body this mod added.
-- `removed` also fires on despawn, so the removal must not fail on an entity that is gone.
app:add_systems(First, {
    Query[{ removed = { "map/default" } }],
    Commands,
}, function(maps, commands)
    for _, e in ipairs(maps:iter()) do
        commands:entity(e:id()):try_remove("RigidBody3d", "Collider3d")
    end
end):in_set("map/default/removed")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
