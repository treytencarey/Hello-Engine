-- The server half: the end. A ball whose copy here hit something (`projectile/explode/hit`,
-- from the shared half) is despawned, and the despawn reaches every client.

local app = ...

app:add_systems(Update, {
    Query[{
        added = { "projectile/explode/hit" },
        with = { "projectile/explode" },
    }],
    Commands,
}, function(hit, commands)
    for _, e in ipairs(hit:iter()) do
        commands:entity(e:id()):try_despawn()
    end
end):in_set("projectile/explode/end"):after("projectile/explode")
