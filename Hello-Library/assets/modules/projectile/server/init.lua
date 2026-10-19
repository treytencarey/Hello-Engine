-- The server half: the end. When the lifetime timer (`projectile/flying`, run on both sides)
-- ends, the server despawns the projectile, and the despawn reaches every client.

register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "projectile/flying" },
        with = { "projectile" },
    })) do
        despawn(e:id())
    end
end, { label = "ProjectileLanded" })
