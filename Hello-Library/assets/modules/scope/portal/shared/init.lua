-- A portal: a way into another world, named by its scope key. A hosted portal a player dropped
-- stands in its target too, leading back (the server half); any other is one-ended, the way back
-- being the other world's own portal. On both sides a dropped portal is a fixed ball of radius 1.2
-- that says who walks into it (`collision_trigger`); one still being placed is none of that.
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

-- The body comes when the portal is dropped (`placement` removed), or at its spawn when it is never
-- placed (a scene's door): one being placed follows its placer, and must hold no one. A fresh trigger
-- reads whoever already stands inside as walking in, so a portal dropped where a player stands takes
-- that player in. `insert_if_new`: a reload sees every portal as added again. A cancelled placement
-- despawns the portal, which has no row in `dropped`.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "scope/portal" },
            removed = { "placement" },
        },
    }],
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
    }],
    Commands,
}, function(touched, dropped, commands)
    local ids = {}
    for _, e in ipairs(touched:iter()) do
        ids[#ids + 1] = e:id()
    end
    for _, e in ipairs(dropped:iter_many(ids)) do
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
