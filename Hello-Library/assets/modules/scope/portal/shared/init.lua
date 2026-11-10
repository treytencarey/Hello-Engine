-- A portal: a way into another world, named by its scope key. One-ended: the way back is the
-- other world's own portal. On both sides it is a fixed ball of radius 1.2 that says who walks
-- into it (`collision_trigger`), from its spawn on, while it is still being placed too.
--
-- scope/portal = {
--     target = <the scope key of the world it leads to>,
-- }
--
-- scope/portal/hosted = {}: on a placed portal whose target runs in this process with its peer
-- link up, written by the server.
--
-- scope/portal/locked = {
--     reason = <why the target cannot be shown>,
-- }
--
-- scope/portal/cooling = {}: on a player handed in from another world, for 3 s, while it may not
-- cross again. It is a `cooldown` timer that crosses with the player from the portal it took.

-- The trigger is there while the portal is placed too, so whoever stands where it is placed is
-- already inside when placing ends, and has not walked in; only a portal no longer being placed
-- takes a walk-in. `insert_if_new`: a reload sees every portal as added again, and a fresh
-- `collision_trigger` would read whoever stands inside as walking in.
app:add_systems(First, {
    Query[{ added = { "scope/portal" } }],
    Commands,
}, function(portals, commands)
    for _, e in ipairs(portals:iter()) do
        commands:entity(e:id()):insert_if_new({
            RigidBody3d = "Fixed",
            Collider3d = { ball = { radius = 1.2 } },
            collision_trigger = {},
        })
    end
end):in_set("scope/portal/shared")

-- `scope/portal` was taken off an entity that stays. A despawned entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "scope/portal" } }],
    Query[{ any_of = { "RigidBody3d", "Collider3d", "collision_trigger" } }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):try_remove("RigidBody3d", "Collider3d", "collision_trigger")
    end
end):in_set("scope/portal/shared")
