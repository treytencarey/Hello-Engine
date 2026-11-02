-- Walkable volumes authored in a scene: every node below the entity whose name holds `include`
-- gets an `ai/nav/volume`, which `ai/nav/volumes` bakes. It loads no scene; it reads what the
-- map spawned. Missing fields get defaults when it is added.
--
-- ai/nav/volumes/scene = {
--     include = <text a node's name must hold>,
-- }
--
-- A node's size is its world scale times a 2 m cube, so its half extents are its scale: author
-- nav volumes without applying transforms before export. A rotated node's box is the
-- axis-aligned box around it.
--
-- A node's volume says `scene = true`, so only those are taken off when this mod goes: a
-- sub-component of this mod on a node would have `mod_registry` despawn the map's node with it.

local Mat3 = require("bevy::math::Mat3")

app:add_systems(First, {
    Query[{ added = { "ai/nav/volumes/scene" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local s = e:get("ai/nav/volumes/scene")
        commands:entity(e:id()):patch({
            ["ai/nav/volumes/scene"] = { include = s.include or "_nav" },
        })
    end
end):in_set("ai/nav/volumes/scene/init")

-- A scene's nodes land over an unknown number of frames, and each is an added `Name`. A node
-- that came first is found when this mod's component arrives or changes. First reads the world
-- scale the last frame's propagation left, which a scene's new nodes already have.
app:add_systems(First, {
    Query[{ added = { "Name" } }],
    Query[{ changed = { "ai/nav/volumes/scene" } }],
    Query[{
        with = { "Name", "GlobalTransform" },
        without = { "ai/nav/volume" },
    }],
    Query[{ with = { "ai/nav/volumes/scene" } }],
    Commands,
}, function(named, sources, nodes, owners, commands)
    local list = {}
    for _, e in ipairs(named:iter()) do
        list[#list + 1] = e:id()
    end
    for _, e in ipairs(sources:iter()) do
        list[#list + 1] = e:id()
        for _, id in ipairs(nodes:iter_descendants(e:id())) do
            list[#list + 1] = id
        end
    end
    for _, node in ipairs(nodes:iter_many(list)) do
        local up = owners:iter_ancestors(node:id())
        table.insert(up, 1, node:id())
        local owner = owners:iter_many(up)[1]
        local include = owner and owner:get("ai/nav/volumes/scene").include
        local name = node:get("Name").name
        if include and string.find(name, include, 1, true) then
            local t = node.GlobalTransform:compute_transform()
            local half = Mat3.mul_vec3(Mat3.abs(Mat3.from_quat(t.rotation)), t.scale)
            commands:entity(node:id()):insert({
                ["ai/nav/volume"] = { hx = half.x, hy = half.y, hz = half.z, scene = true },
            })
        end
    end
end):in_set("ai/nav/volumes/scene/tag"):after("ai/nav/volumes/scene/init")

-- `ai/nav/volumes/scene` was taken off an entity that stays: its volumes go, and the nodes stay.
app:add_systems(First, {
    Query[{ removed = { "ai/nav/volumes/scene" } }],
    Query[{ with = { "ai/nav/volume" } }],
    Commands,
}, function(removed, tagged, commands)
    for _, e in ipairs(removed:iter()) do
        local list = tagged:iter_descendants(e:id())
        list[#list + 1] = e:id()
        for _, node in ipairs(tagged:iter_many(list)) do
            local volume = node:get("ai/nav/volume")
            if volume.scene then
                commands:entity(node:id()):try_remove("ai/nav/volume")
            end
        end
    end
end):in_set("ai/nav/volumes/scene/removed")

return { base = "ai/nav/volumes" }
