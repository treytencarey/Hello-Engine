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
register_system("First", function(world)
    for _, e in ipairs(world:query({ changed = { "map/default" } })) do
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
            e:patch({
                RigidBody3d = "Fixed",
                Collider3d = { cuboid = { hx = m.size.x / 2, hy = m.size.y / 2, hz = m.size.z / 2 } },
            })
        end
    end
end, { label = "MapGround" })

-- `map/default` was taken off an entity that stays: take off the body this mod added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "map/default" } })) do
        e:patch({
            RigidBody3d = null,
            Collider3d = null,
        })
    end
end, { label = "MapRemoved" })

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
