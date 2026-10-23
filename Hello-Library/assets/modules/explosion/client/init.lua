-- The client half: a glowing sphere of the explosion's color, growing from nothing to its
-- radius while it lasts.

local app = ...
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Sphere = require("bevy::math::primitives::Sphere")

-- The mesh is Bevy's sphere of radius 1 (`Assets<Mesh>` takes a `Sphere`), scaled to the
-- explosion's size.
app:add_systems(First, {
    Query[{ added = { "explosion" } }],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(added, meshes, materials, commands)
    for _, e in ipairs(added:iter()) do
        local c = e:get("explosion").color
        commands:entity(e:id()):patch({
            Mesh3d = meshes:add(Sphere.new(1)),
            ["MeshMaterial3d<StandardMaterial>"] = materials:add({
                base_color = { Srgba = { red = c.r, green = c.g, blue = c.b, alpha = 1 } },
                emissive = { red = c.r * 4, green = c.g * 4, blue = c.b * 4, alpha = 1 },
            }),
            Transform = { scale = { x = 0.01, y = 0.01, z = 0.01 } },
        })
    end
end):in_set("explosion/draw"):after("explosion/place")

-- Timed work polls, but only explosions still burning.
app:add_systems(Update, {
    Query[{ with = { "explosion", "cooldown/left" } }],
    Commands,
}, function(burning, commands)
    for _, e in ipairs(burning:iter()) do
        local x = e:get("explosion")
        local left = (e:get("cooldown/left") or {})["explosion/burning"]
        if left and x.duration and x.duration > 0 then
            local size = math.max(0.01, x.radius * (1 - left / x.duration))
            commands:entity(e:id()):patch({ Transform = { scale = { x = size, y = size, z = size } } })
        end
    end
end):in_set("explosion/grow")

-- `explosion` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `drawn`.
app:add_systems(First, {
    Query[{ removed = { "explosion" } }],
    Query[{ any_of = { "Mesh3d", "MeshMaterial3d<StandardMaterial>" } }],
    Commands,
}, function(removed, drawn, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(drawn:iter_many(gone)) do
        commands:entity(e:id()):remove("Mesh3d", "MeshMaterial3d<StandardMaterial>")
    end
end):in_set("explosion/undraw")
