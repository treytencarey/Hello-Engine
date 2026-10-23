-- The client half: every client draws every projectile, a glowing ball of its radius and color.

local app = ...

app:add_systems(First, {
    Query[{ added = { "projectile" } }],
    Commands,
}, function(projectiles, commands)
    for _, e in ipairs(projectiles:iter()) do
        local p = e:get("projectile")
        commands:entity(e:id()):insert({
            Mesh3d = create_asset("bevy_mesh::mesh::Mesh", {
                primitive = { Sphere = { radius = p.radius } },
            }),
            ["MeshMaterial3d<StandardMaterial>"] = create_asset("bevy_pbr::pbr_material::StandardMaterial", {
                base_color = { r = p.color.r, g = p.color.g, b = p.color.b, a = 1 },
                emissive = { r = p.color.r, g = p.color.g, b = p.color.b, a = 1 },
            }),
        })
    end
end):in_set("projectile/draw"):after("projectile/init")

-- `projectile` was taken off an entity that stays: take off what this mod added. A despawned
-- projectile is in the `removed` rows too, which `try_remove` passes by.
app:add_systems(First, {
    Query[{ removed = { "projectile" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("Mesh3d", "MeshMaterial3d<StandardMaterial>")
    end
end):in_set("projectile/undraw")
