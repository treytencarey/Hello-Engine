-- A static trimesh collider from the carrier's own geometry: every mesh primitive at or below the
-- carrier gets a child shape built from its mesh. In Blender, give an object the custom property
-- `collider/mesh` and `gltf/mod_registry` puts this mod on its node.
--
-- collider/mesh = {}
--
-- collider/mesh/shape: marks the collider child under a primitive.
--
-- The shape has no RigidBody: a body-less collider is static and Rapier re-places it whenever its
-- GlobalTransform changes. A Fixed body would have Rapier write its pose back through the
-- parent's inverse, which drifts under a scaled, rotated node.

local Collider = require("bevy_rapier3d::geometry::Collider")
local LuaFrameBudget = require("bevy_lua_ecs::lua_frame_budget::LuaFrameBudget")
local On = require("bevy::ecs::prelude::On")
local SceneInstanceReady = require("bevy::scene::SceneInstanceReady")

-- A big map's carriers take more than a frame's slice. One left for later is written through
-- Commands, as a system does not see its own `get_mut` write, and that wakes it next frame.
app:add_systems(Update, {
    Res[LuaFrameBudget],
    Query[{
        ["or"] = {
            added = { "collider/mesh", "collider" },
            changed = { "collider/mesh", "collider" },
        },
        with = { "collider/mesh", Mut["collider"] },
        optional = { "SceneRoot", "Children" },
    }],
    Query[{
        with = { "Mesh3d" },
        optional = { "Children" },
    }],
    Query[{ with = { "collider/mesh/shape" } }],
    Commands,
}, function(budget, carriers, prims, shapes, commands)
    local spent = false
    for _, e in ipairs(carriers:iter_mut()) do
        if spent then
            commands:entity(e:id()):insert({ collider = { built = false } })
        elseif e:has("SceneRoot") and not e:has("Children") then
            -- Its scene is still loading: the observer below wakes it once Bevy has spawned it.
        else
            local list = prims:iter_descendants(e:id())
            table.insert(list, 1, e:id())
            for _, prim in ipairs(prims:iter_many(list)) do
                for _, old in ipairs(shapes:iter_many(prim:get("Children") or {})) do
                    commands:entity(old:id()):despawn()
                end
                local mesh = prim:get("Mesh3d")
                local shape = Collider.from_bevy_mesh(mesh, "TriMesh")
                if shape ~= nil then
                    commands:spawn({
                        Transform = {},
                        Collider3d = shape,
                        ["collider/mesh/shape"] = {},
                        ChildOf = prim:id(),
                    })
                else
                    print(string.format("[collider/mesh] no trimesh for primitive %s: mesh not loaded or refused", prim:id()))
                end
            end
            e:get_mut("collider").built = true
            spent = budget:over_budget()
        end
    end
end):in_set("collider/mesh/build"):before("collider/status")

-- A carrier that holds a SceneRoot builds once its scene has spawned, and again after a
-- re-export respawns it.
app:add_observer(On[SceneInstanceReady], {
    Query[{ with = { "collider/mesh", "collider" } }],
    Commands,
}, function(event, carriers, commands)
    if carriers:contains(event.entity) then
        commands:entity(event.entity):insert({ collider = { built = false } })
    end
end)

return { base = "collider" }
