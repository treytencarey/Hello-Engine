-- The server half: the end. When the lifetime timer (`projectile/flying`, run on both sides)
-- ends, the server despawns the projectile, and the despawn reaches every client.

local app = ...

-- A projectile despawned already (it hit something) is in the `removed` rows too, which
-- `try_despawn` passes by.
app:add_systems(First, {
    Query[{
        removed = { "projectile/flying" },
        with = { "projectile" },
    }],
    Commands,
}, function(landed, commands)
    for _, e in ipairs(landed:iter()) do
        commands:entity(e:id()):try_despawn()
    end
end):in_set("projectile/landed")
