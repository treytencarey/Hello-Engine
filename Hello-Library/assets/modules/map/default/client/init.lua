-- The client half: the ground's box and color, and the sun, a child light shining down at
-- an angle. A change redraws the box and relights the same sun.

local app = ...
local Quat = require("bevy::math::Quat")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Cuboid = require("bevy::math::primitives::Cuboid")

app:add_systems(First, {
    Query[{
        changed = { "map/default" },
        optional = { "Children" },
    }],
    Query[{
        with = { "map/default/sun", Mut["DirectionalLight"] },
    }],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(maps, suns, meshes, materials, commands)
    for _, e in ipairs(maps:iter()) do
        -- after map/default/ground, which has filled any missing field by now
        local m = e:get("map/default")
        commands:entity(e:id()):patch({
            Mesh3d = meshes:add(Cuboid.new(m.size.x, m.size.y, m.size.z)),
            ["MeshMaterial3d<StandardMaterial>"] = materials:add({
                base_color = { Srgba = { red = m.color.r, green = m.color.g, blue = m.color.b, alpha = 1 } },
                perceptual_roughness = 0.9,
            }),
        })
        local sun = suns:iter_many_mut(e:get("Children") or {})[1]
        if sun ~= nil then
            sun:patch({ DirectionalLight = { illuminance = m.sun } })
        else
            local light = commands:spawn({
                ["map/default/sun"] = {},
                DirectionalLight = { illuminance = m.sun, shadows_enabled = true },
                Transform = {
                    rotation = Quat.mul_quat(Quat.from_rotation_y(0.8),
                        Quat.from_rotation_x(-0.8)),
                },
            }):id()
            commands:entity(e:id()):add_child(light)
        end
    end
end):in_set("map/default/draw"):after("map/default/ground")

-- `map/default` was taken off an entity that stays: take off what this half added. The
-- sun, marked `map/default/sun`, goes by `mod_registry`. `removed` also fires on despawn, so
-- the removal must not fail on an entity that is gone.
app:add_systems(First, {
    Query[{ removed = { "map/default" } }],
    Commands,
}, function(maps, commands)
    for _, e in ipairs(maps:iter()) do
        commands:entity(e:id()):try_remove("Mesh3d", "MeshMaterial3d<StandardMaterial>")
    end
end):in_set("map/default/undraw")
