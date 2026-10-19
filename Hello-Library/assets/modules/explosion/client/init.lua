-- The client half: a glowing sphere of the explosion's color, growing from nothing to its
-- radius while it lasts.

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "explosion" } })) do
        local x = e:get("explosion")
        local c = x.color
        e:patch({
            Mesh3d = create_asset("bevy_mesh::mesh::Mesh", { primitive = { Sphere = { radius = 1 } } }),
            ["MeshMaterial3d<StandardMaterial>"] = create_asset("bevy_pbr::pbr_material::StandardMaterial", {
                base_color = { r = c.r, g = c.g, b = c.b, a = 1 },
                emissive = { r = c.r * 4, g = c.g * 4, b = c.b * 4, a = 1 },
            }),
            Transform = { scale = { x = 0.01, y = 0.01, z = 0.01 } },
        })
    end
end, { label = "ExplosionDraw", after = { "ExplosionPlace" } })

-- Timed work polls, but only explosions still burning.
register_system("Update", function(world)
    for _, e in ipairs(world:query({ with = { "explosion", "cooldown/left" } })) do
        local x = e:get("explosion")
        local left = (e:get("cooldown/left") or {})["explosion/burning"]
        if left and x.duration and x.duration > 0 then
            local size = math.max(0.01, x.radius * (1 - left / x.duration))
            e:patch({ Transform = { scale = { x = size, y = size, z = size } } })
        end
    end
end, { label = "ExplosionGrow" })

-- `explosion` was taken off an entity that stays: take off what this half added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "explosion" } })) do
        if world:get_entity(e:id()) then
            e:patch({ Mesh3d = null, ["MeshMaterial3d<StandardMaterial>"] = null })
        end
    end
end, { label = "ExplosionUndraw" })
