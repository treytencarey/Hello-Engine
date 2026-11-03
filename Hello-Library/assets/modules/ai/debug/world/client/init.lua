-- Draws what the server published in `ai/debug/world`, in two layers that answer different questions.
-- Filled slabs are the walkable ground, to read from across the map, and they are real geometry, as
-- gizmos are only lines. Lines are the exact boundaries and links, to read a specific bad path.
--
-- ai/debug/world/slab = { entity = <its carrier> }: on a slab
-- ai/debug/world/slabs: a carrier's slabs, kept by the engine

local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Cuboid = require("bevy::math::primitives::Cuboid")
local Gizmos = require("bevy::gizmos::gizmos::Gizmos")

local function color(red, green, blue, alpha)
    return { Srgba = { red = red, green = green, blue = blue, alpha = alpha } }
end

local VOLUME = color(0.2, 0.95, 0.35, 0.85)
local REGION = color(0.25, 0.55, 0.9, 0.55)
local LINK = color(0.95, 0.85, 0.25, 0.85)
local CROSSING = color(1, 0.95, 0.55, 1)

local LIFT = 0.08

-- Slabs sit under the lines, and above the floor so they do not flicker with it. They answer no
-- pointer, or one covering the floor would swallow every click on the map. The old mesh and material
-- go with the last slab holding them.
app:add_systems(First, {
    Query[{
        changed = { "ai/debug/world" },
        optional = { "ai/debug/world/slabs" },
    }],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(carriers, meshes, materials, commands)
    for _, e in ipairs(carriers:iter()) do
        for _, slab in ipairs(e:get("ai/debug/world/slabs") or {}) do
            commands:entity(slab):try_despawn()
        end
        local w = e:get("ai/debug/world")
        local regions = w.regions or {}
        if #regions > 0 then
            local mesh = meshes:add(Cuboid.new(1, 1, 1))
            local material = materials:add({
                base_color = { Srgba = { red = 0.2, green = 0.95, blue = 0.35, alpha = 0.22 } },
                unlit = true,
                alpha_mode = "Blend",
            })
            for _, r in ipairs(regions) do
                commands:spawn({
                    ["ai/debug/world/slab"] = { entity = e:id() },
                    Mesh3d = mesh,
                    ["MeshMaterial3d<StandardMaterial>"] = material,
                    Transform = {
                        translation = { x = (r.min_x + r.max_x) * 0.5, y = (r.y or 0) + 0.04, z = (r.min_z + r.max_z) * 0.5 },
                        scale = { x = r.max_x - r.min_x, y = 0.02, z = r.max_z - r.min_z },
                    },
                    Pickable = { should_block_lower = false, is_hoverable = false },
                    ["core/net/sync"] = false,
                })
            end
        end
    end
end):in_set("ai/debug/world/fill")

local function outline(gizmos, min_x, max_x, y, min_z, max_z, tint)
    local xs = { min_x, max_x, max_x, min_x }
    local zs = { min_z, min_z, max_z, max_z }
    for i = 1, 4 do
        local j = i % 4 + 1
        gizmos:line({ x = xs[i], y = y, z = zs[i] }, { x = xs[j], y = y, z = zs[j] }, tint)
    end
end

app:add_systems(Update, {
    Gizmos,
    Query[{ with = { "ai/debug/world" } }],
}, function(gizmos, carriers)
    for _, e in ipairs(carriers:iter()) do
        local w = e:get("ai/debug/world")
        for _, v in ipairs(w.volumes or {}) do
            local low, high = v.min_y + LIFT, v.max_y + LIFT
            outline(gizmos, v.min_x, v.max_x, low, v.min_z, v.max_z, VOLUME)
            if high > low then
                outline(gizmos, v.min_x, v.max_x, high, v.min_z, v.max_z, VOLUME)
                for _, corner in ipairs({
                    { v.min_x, v.min_z },
                    { v.max_x, v.min_z },
                    { v.max_x, v.max_z },
                    { v.min_x, v.max_z },
                }) do
                    gizmos:line({ x = corner[1], y = low, z = corner[2] }, { x = corner[1], y = high, z = corner[2] }, VOLUME)
                end
            end
        end
        for _, r in ipairs(w.regions or {}) do
            outline(gizmos, r.min_x, r.max_x, (r.y or 0) + LIFT, r.min_z, r.max_z, REGION)
        end
        for _, l in ipairs(w.links or {}) do
            local from = { x = l.from.x, y = l.from.y + LIFT * 2, z = l.from.z }
            local to = { x = l.to.x, y = l.to.y + LIFT * 2, z = l.to.z }
            local crossing = { x = l.x or (from.x + to.x) * 0.5, y = (l.y or from.y) + LIFT * 2, z = l.z or (from.z + to.z) * 0.5 }
            gizmos:line(from, crossing, LINK)
            gizmos:line(crossing, to, LINK)
            gizmos:line({ x = crossing.x, y = crossing.y - 0.4, z = crossing.z }, { x = crossing.x, y = crossing.y + 0.4, z = crossing.z }, CROSSING)
        end
    end
end):in_set("ai/debug/world/draw")

-- `ai/debug/world` was taken off an entity that stays: its slabs go.
app:add_systems(First, {
    Query[{
        removed = { "ai/debug/world" },
        with = { "ai/debug/world/slabs" },
    }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        for _, slab in ipairs(e:get("ai/debug/world/slabs")) do
            commands:entity(slab):try_despawn()
        end
    end
end):in_set("ai/debug/world/removed")

return {
    relationships = {
        ["ai/debug/world/slab"] = { target = "ai/debug/world/slabs", linked_spawn = true },
    },
}
