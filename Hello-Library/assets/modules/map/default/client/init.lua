-- The client half: the ground's box and color, and the sun, a child light shining down at
-- an angle. A change redraws the box and relights the same sun.

register_system("First", function(world)
    for _, e in ipairs(world:query({ changed = { "map/default" } })) do
        -- after MapGround, which has filled any missing field by now
        local m = e:get("map/default")
        e:patch({
            Mesh3d = create_asset("bevy_mesh::mesh::Mesh", {
                primitive = { Cuboid = { half_size = { x = m.size.x / 2, y = m.size.y / 2, z = m.size.z / 2 } } },
            }),
            ["MeshMaterial3d<StandardMaterial>"] = create_asset("bevy_pbr::pbr_material::StandardMaterial", {
                base_color = { r = m.color.r, g = m.color.g, b = m.color.b, a = 1 },
                perceptual_roughness = 0.9,
            }),
        })
        local sun = world:query({ entities = { e:id() }, with = { "map/default/sun" }, limit = 1 })[1]
        if sun ~= nil then
            sun:patch({ DirectionalLight = { illuminance = m.sun } })
        else
            spawn({
                ["map/default/sun"] = {},
                DirectionalLight = { illuminance = m.sun, shadows_enabled = true },
                Transform = {
                    rotation = world:call_static_method("Quat", "mul_quat",
                        world:call_static_method("Quat", "from_rotation_y", 0.8),
                        world:call_static_method("Quat", "from_rotation_x", -0.8)),
                },
            }):with_parent(e:id())
        end
    end
end, { label = "MapDraw", after = { "MapGround" } })

-- `map/default` was taken off an entity that stays: take off what this half added. The
-- sun, marked `map/default/sun`, goes by `mod_registry`.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "map/default" } })) do
        e:patch({
            Mesh3d = null,
            ["MeshMaterial3d<StandardMaterial>"] = null,
        })
    end
end, { label = "MapUndraw" })
