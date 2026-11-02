-- The client half: every client draws every projectile, a glowing ball of its radius and color.

local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Sphere = require("bevy::math::primitives::Sphere")

app:add_systems(First, {
    Query[{ added = { "projectile" } }],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(projectiles, meshes, materials, commands)
    for _, e in ipairs(projectiles:iter()) do
        local p = e:get("projectile")
        local c = p.color
        commands:entity(e:id()):insert({
            Mesh3d = meshes:add(Sphere.new(p.radius)),
            ["MeshMaterial3d<StandardMaterial>"] = materials:add({
                base_color = { Srgba = { red = c.r, green = c.g, blue = c.b, alpha = 1 } },
                emissive = { red = c.r, green = c.g, blue = c.b, alpha = 1 },
            }),
        })
    end
end):in_set("projectile/draw")

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
