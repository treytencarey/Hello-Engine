-- A projectile: a ball launched from a point at a velocity, flying under scaled gravity, and
-- despawned by the server when its lifetime ends. The server and every client simulate it,
-- its lifetime timer included, from the same launch state, so only `projectile` is synced.
-- Missing fields get defaults when it is added.
--
-- projectile = {
--     from = { x = <metres>, y = <metres>, z = <metres> },
--     velocity = { x = <m/s>, y = <m/s>, z = <m/s> },
--     radius = <metres>,
--     gravity = <gravity scale>,
--     lifetime = <seconds>,
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
-- }
--
-- Who fired it, a relationship (below): `projectile/caster` on the projectile names its
-- caster, and the engine keeps `projectile/casts` on the caster, listing what it has in
-- flight. The server holds both: the caster is never synced.
--
-- projectile/caster = { entity = <the caster> }
-- projectile/casts = { <projectile>, ... }   (kept by the engine; read only)

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "projectile" } })) do
        local p = e:get("projectile")
        e:patch({
            projectile = {
                from = p.from or { x = 0, y = 0, z = 0 },
                velocity = p.velocity or { x = 0, y = 0, z = 0 },
                radius = p.radius or 0.2,
                gravity = p.gravity or 0.3,
                lifetime = p.lifetime or 3,
                color = p.color or { r = 1, g = 0.3, b = 0.1 },
            },
        })
    end
end, { label = "ProjectileInit" })

-- Launch: place it and give it a body that arrives with its collider.
register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "projectile" } })) do
        local p = e:get("projectile")
        e:patch({
            Transform = { translation = p.from },
            RigidBody3d = "Dynamic",
            Collider3d = { ball = { radius = p.radius } },
            GravityScale3d = { value = p.gravity },
            Velocity3d = { linvel = p.velocity },
        })
    end
end, { label = "ProjectileLaunch", after = { "ProjectileInit" } })

-- The lifetime runs on every side as a `cooldown` timer, `projectile/flying`: a client has
-- the time left at once (UI, and later a predicted copy), and the server ends it.
register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "projectile" } })) do
        local p = e:get("projectile")
        e:patch({ cooldown = { ["projectile/flying"] = { remaining = p.lifetime } } })
    end
end, { label = "ProjectileFlying", after = { "ProjectileInit" } })

-- `projectile` was taken off an entity that stays: take off the body this mod added and stop
-- its timer. The Transform stays; the entity keeps its place.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "projectile" } })) do
        e:patch({
            RigidBody3d = null,
            Collider3d = null,
            GravityScale3d = null,
            Velocity3d = null,
            cooldown = { ["projectile/flying"] = null },
        })
    end
end, { label = "ProjectileRemoved" })

return {
    ["core/net/sync"] = {
        authority = "server",
    },
    relationships = {
        ["projectile/caster"] = { target = "projectile/casts" },
    },
}
