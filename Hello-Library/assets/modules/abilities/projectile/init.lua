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

local Quat = require("bevy::math::Quat")

app:add_systems(First, {
    Query[{ added = { "abilities/projectile" } }],
    Commands,
}, function(launches, commands)
    for _, e in ipairs(launches:iter()) do
        local a = e:get("abilities/projectile")
        local look = Quat.mul_quat(Quat.from_rotation_y(a.yaw or 0),
            Quat.from_rotation_x(a.pitch or 0))
        local along = Quat.mul_vec3(look, { x = 0, y = 0, z = -1 })
        local at = a.at or { x = 0, y = 0, z = 0 }
        local speed = a.speed or 20
        commands:entity(e:id()):patch({
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
end):in_set("abilities/projectile/launch")

-- `abilities/projectile` was taken off an entity that stays: the `projectile` it added goes.
-- A despawned launch is in the `removed` rows too, which `try_remove` passes by.
app:add_systems(First, {
    Query[{ removed = { "abilities/projectile" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("projectile")
    end
end):in_set("abilities/projectile/removed")
