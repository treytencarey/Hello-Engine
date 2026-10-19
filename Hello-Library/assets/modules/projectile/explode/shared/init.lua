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

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "projectile/explode" } })) do
        e:patch({ collision_trigger = {} })
    end
end, { label = "ProjectileExplodeSensor" })

local function hits_other_than(entered, caster)
    for _, id in ipairs(entered or {}) do
        if not (caster and id == caster.entity) then return true end
    end
    return false
end

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        changed = { "collision_trigger" },
        with = { "projectile/explode" },
        without = { "projectile/explode/hit" },
        optional = { "projectile/caster" },
    })) do
        if hits_other_than(e:get("collision_trigger").entered, e:get("projectile/caster")) then
            local x = e:get("projectile/explode")
            local at = world:call_component_method(e:id(), "GlobalTransform", "compute_transform").translation
            spawn({
                explosion = { at = { x = at.x, y = at.y, z = at.z },
                              radius = x.radius, duration = x.duration, color = x.color },
                -- Not reaped with this mod: the ball that spawned it is its last carrier.
                ScriptOwned = false,
            })
            -- A client's copy is the server's to end: hidden here, despawned by the server.
            e:patch({ ["projectile/explode/hit"] = {}, Visibility = "Hidden" })
        end
    end
end, { label = "ProjectileExplode" })

-- `projectile/explode` was taken off an entity that stays: it is no longer a sensor, and a
-- ball it hid shows again.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "projectile/explode" } })) do
        local live = world:get_entity(e:id())
        if live then
            local undo = { collision_trigger = null }
            if live:get("projectile/explode/hit") ~= nil then
                undo["projectile/explode/hit"] = null
                undo.Visibility = "Inherited"
            end
            live:patch(undo)
        end
    end
end, { label = "ProjectileExplodeRemoved" })

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
