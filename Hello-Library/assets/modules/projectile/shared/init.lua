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

-- Launch: place it and give it a body that arrives with its collider.
app:add_systems(First, {
    Query[{ added = { "projectile" } }],
    Commands,
}, function(projectiles, commands)
    for _, e in ipairs(projectiles:iter()) do
        local p = e:get("projectile")
        commands:entity(e:id()):patch({
            Transform = { translation = p.from },
            RigidBody3d = "Dynamic",
            Collider3d = { ball = { radius = p.radius } },
            GravityScale3d = { value = p.gravity },
            Velocity3d = { linvel = p.velocity },
        })
    end
end):in_set("projectile/launch")

-- The lifetime runs on every side as a `cooldown` timer, `projectile/flying`: a client has
-- the time left at once (UI, and later a predicted copy), and the server ends it.
app:add_systems(First, {
    Query[{ added = { "projectile" } }],
    Commands,
}, function(projectiles, commands)
    for _, e in ipairs(projectiles:iter()) do
        local p = e:get("projectile")
        commands:entity(e:id()):patch({ cooldown = { ["projectile/flying"] = { remaining = p.lifetime } } })
    end
end):in_set("projectile/flying")

-- `projectile` was taken off an entity that stays: take off the body this mod added and stop
-- its timer. The Transform stays; the entity keeps its place. A despawned projectile is in the
-- `removed` rows too, and has nothing to take off.
app:add_systems(First, {
    Query[{
        removed = { "projectile" },
        optional = { "cooldown" },
    }],
    Query[{ with = { "RigidBody3d" } }],
    Commands,
}, function(removed, bodies, commands)
    for _, e in ipairs(removed:iter()) do
        if bodies:contains(e:id()) then
            local entity = commands:entity(e:id())
            entity:try_remove("RigidBody3d", "Collider3d", "GravityScale3d", "Velocity3d")
            -- Only while `cooldown` stays: a patch landing after it went would bring it back.
            if e:has("cooldown") then
                entity:patch({ cooldown = { ["projectile/flying"] = null } })
            end
        end
    end
end):in_set("projectile/removed")

return {
    defaults = {
        projectile = {
            from = { x = 0, y = 0, z = 0 },
            velocity = { x = 0, y = 0, z = 0 },
            radius = 0.2,
            gravity = 0.3,
            lifetime = 3,
            color = { r = 1, g = 0.3, b = 0.1 },
        },
    },
    ["core/net/sync"] = {
        authority = "server",
    },
    relationships = {
        ["projectile/caster"] = { target = "projectile/casts" },
    },
}
