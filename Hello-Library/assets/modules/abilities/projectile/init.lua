-- A projectile fired by an ability: launched from `at`, 1 m along the look given by `yaw` and
-- `pitch` (the caster's camera), at `speed`. It becomes a `projectile` on the same entity,
-- which flies and ends on its own. An ability spawns it (`abilities/grenade`,
-- `abilities/fireball`); this component never crosses the network, and the `projectile` it
-- adds does. It is a root, not the caster's child: a child body is dragged along by a moving
-- parent (measured). An ability links it to its caster with `projectile/caster`.
--
-- abilities/projectile = {
--     at = { x = <metres>, y = <metres>, z = <metres> },
--     yaw = <radians>,
--     pitch = <radians>,
--     speed = <m/s>,
--     radius = <metres>,
--     gravity = <gravity scale>,
--     lifetime = <seconds>,
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
-- }

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "abilities/projectile" } })) do
        local a = e:get("abilities/projectile")
        local look = world:call_static_method("Quat", "mul_quat",
            world:call_static_method("Quat", "from_rotation_y", a.yaw or 0),
            world:call_static_method("Quat", "from_rotation_x", a.pitch or 0))
        local along = world:call_static_method("Quat", "mul_vec3", look, { x = 0, y = 0, z = -1 })
        local at = a.at or { x = 0, y = 0, z = 0 }
        local speed = a.speed or 20
        e:patch({
            projectile = {
                from = { x = at.x + along.x, y = at.y + along.y, z = at.z + along.z },
                velocity = { x = along.x * speed, y = along.y * speed, z = along.z * speed },
                radius = a.radius,
                gravity = a.gravity,
                lifetime = a.lifetime,
                color = a.color,
            },
        })
    end
end, { label = "AbilitiesProjectileLaunch" })

-- `abilities/projectile` was taken off an entity that stays: the `projectile` it added goes.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "abilities/projectile" } })) do
        if world:get_entity(e:id()) then e:patch({ projectile = null }) end
    end
end, { label = "AbilitiesProjectileRemoved" })
