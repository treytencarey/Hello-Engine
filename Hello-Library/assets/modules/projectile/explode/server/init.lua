-- The server half: the end. A ball whose copy here hit something (`projectile/explode/hit`,
-- from the shared half) is despawned, and the despawn reaches every client.

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        added = { "projectile/explode/hit" },
        with = { "projectile/explode" },
    })) do
        despawn(e:id())
    end
end, { label = "ProjectileExplodeEnd", after = { "ProjectileExplode" } })
