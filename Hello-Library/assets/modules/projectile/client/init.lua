-- The client half: every client draws every projectile, a glowing ball of its radius and color.

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "projectile" } })) do
        local p = e:get("projectile")
        e:patch({
            Mesh3d = create_asset("bevy_mesh::mesh::Mesh", {
                primitive = { Sphere = { radius = p.radius } },
            }),
            ["MeshMaterial3d<StandardMaterial>"] = create_asset("bevy_pbr::pbr_material::StandardMaterial", {
                base_color = { r = p.color.r, g = p.color.g, b = p.color.b, a = 1 },
                emissive = { r = p.color.r, g = p.color.g, b = p.color.b, a = 1 },
            }),
        })
    end
end, { label = "ProjectileDraw", after = { "ProjectileInit" } })

-- `projectile` was taken off an entity that stays: take off what this mod added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "projectile" } })) do
        e:patch({
            Mesh3d = null,
            ["MeshMaterial3d<StandardMaterial>"] = null,
        })
    end
end, { label = "ProjectileUndraw" })
