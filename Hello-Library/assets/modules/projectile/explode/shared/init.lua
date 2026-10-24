-- A projectile that explodes on contact. It passes through what it meets instead of bouncing
-- (a sensor, through `collision_trigger`). Every side reacts at once to the first thing its
-- copy enters other than its caster (`projectile/caster`, when it has one): it hides the ball
-- and shows its own `explosion` where it was, never synced. The server alone ends the ball
-- (its server half). Missing fields are the explosion's own defaults.
--
-- projectile/explode = {
--     radius = <the explosion's radius>,
--     duration = <the explosion's seconds>,
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
-- }
--
-- projectile/explode/hit = {}: on each side, once its copy has hit (never synced).
--
-- Writes are `try_` commands: they land after the system, and a client's copy may be despawned
-- by then (the server ended it).

local app = ...

app:add_systems(First, {
    Query[{ added = { "projectile/explode" } }],
    Commands,
}, function(balls, commands)
    for _, e in ipairs(balls:iter()) do
        commands:entity(e:id()):try_insert_if_new({ collision_trigger = {} })
    end
end):in_set("projectile/explode/sensor")

app:add_systems(Update, {
    Query[{
        changed = { "collision_trigger" },
        with = { "projectile/explode", "GlobalTransform" },
        without = { "projectile/explode/hit" },
        optional = { "projectile/caster" },
    }],
    Commands,
}, function(balls, commands)
    for _, e in ipairs(balls:iter()) do
        local entered = e:get("collision_trigger").entered or {}
        local caster = e:get("projectile/caster")
        for _, id in ipairs(entered) do
            if not (caster and id == caster.entity) then
                local x = e:get("projectile/explode")
                local at = e.GlobalTransform:compute_transform().translation
                commands:spawn({
                    explosion = { at = { x = at.x, y = at.y, z = at.z },
                                  radius = x.radius, duration = x.duration, color = x.color },
                    -- Not reaped with this mod: the ball that spawned it is its last carrier.
                    ["core/script/owner"] = false,
                })
                -- A client's copy is the server's to end: hidden here, despawned by the server.
                commands:entity(e:id()):try_insert({ ["projectile/explode/hit"] = {}, Visibility = "Hidden" })
                break
            end
        end
    end
end):in_set("projectile/explode")

-- `projectile/explode` was taken off an entity that stays: it is no longer a sensor, and a
-- ball it hid shows again.
app:add_systems(First, {
    Query[{
        removed = { "projectile/explode" },
        optional = { "projectile/explode/hit" },
    }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        local entity = commands:entity(e:id())
        entity:try_remove("collision_trigger")
        if e:has("projectile/explode/hit") then
            entity:try_remove("projectile/explode/hit")
            entity:try_insert({ Visibility = "Inherited" })
        end
    end
end):in_set("projectile/explode/removed")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
