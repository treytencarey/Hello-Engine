-- An explosion: a glowing ball at `at` that grows to its radius and is gone after its
-- duration. Each side spawns its own from what it saw (`projectile/explode` on every side),
-- so it is never synced: each side places it, runs its timer and despawns it when it ends.
-- Missing fields get defaults when it is added.
--
-- explosion = {
--     at = { x = <metres>, y = <metres>, z = <metres> },
--     radius = <metres>,
--     duration = <seconds>,
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
-- }
--
-- explosion/burning = {}: present on each side while it lasts (a `cooldown` timer).

local app = ...

app:add_systems(First, {
    Query[{ added = { "explosion" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local x = e:get("explosion")
        commands:entity(e:id()):patch({
            explosion = {
                at = x.at or { x = 0, y = 0, z = 0 },
                radius = x.radius or 1.5,
                duration = x.duration or 0.4,
                color = x.color or { r = 1, g = 0.5, b = 0.1 },
            },
        })
    end
end):in_set("explosion/init")

app:add_systems(First, {
    Query[{ added = { "explosion" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local x = e:get("explosion")
        commands:entity(e:id()):patch({
            Transform = { translation = x.at },
            cooldown = { ["explosion/burning"] = { remaining = x.duration } },
        })
    end
end):in_set("explosion/place"):after("explosion/init")

-- Its timer ended: it is gone. One already despawned has no row in `live`.
app:add_systems(First, {
    Query[{
        removed = { "explosion/burning" },
        with = { "explosion" },
    }],
    Query[{ with = { "explosion" } }],
    Commands,
}, function(ended, live, commands)
    local gone = {}
    for _, e in ipairs(ended:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(live:iter_many(gone)) do
        commands:entity(e:id()):despawn()
    end
end):in_set("explosion/ended")

-- `explosion` was taken off an entity that stays: stop its timer. A despawned entity has no
-- row in `timed`.
app:add_systems(First, {
    Query[{ removed = { "explosion" } }],
    Query[{ with = { "cooldown" } }],
    Commands,
}, function(removed, timed, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(timed:iter_many(gone)) do
        commands:entity(e:id()):patch({ cooldown = { ["explosion/burning"] = null } })
    end
end):in_set("explosion/removed")

-- Local on each side: never synced.
return {
    ["core/net/sync"] = false,
}
