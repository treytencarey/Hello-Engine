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

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "explosion" } })) do
        local x = e:get("explosion")
        e:patch({
            explosion = {
                at = x.at or { x = 0, y = 0, z = 0 },
                radius = x.radius or 1.5,
                duration = x.duration or 0.4,
                color = x.color or { r = 1, g = 0.5, b = 0.1 },
            },
        })
    end
end, { label = "ExplosionInit" })

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "explosion" } })) do
        local x = e:get("explosion")
        e:patch({
            Transform = { translation = x.at },
            cooldown = { ["explosion/burning"] = { remaining = x.duration } },
        })
    end
end, { label = "ExplosionPlace", after = { "ExplosionInit" } })

-- Its timer ended: it is gone.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "explosion/burning" },
        with = { "explosion" },
    })) do
        despawn(e:id())
    end
end, { label = "ExplosionEnded" })

-- `explosion` was taken off an entity that stays: stop its timer.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "explosion" } })) do
        if world:get_entity(e:id()) then e:patch({ cooldown = { ["explosion/burning"] = null } }) end
    end
end, { label = "ExplosionRemoved" })

-- Local on each side: never synced.
return {
    ["core/net/sync"] = false,
}
