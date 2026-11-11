-- A scene's glTF custom properties become components. Put it on an entity that carries a
-- SceneRoot: each key of a node's extras (`GltfExtras`) or of the scene's own (`GltfSceneExtras`)
-- is inserted on that node as a component, with the value as its config, so a key that names a
-- mod loads that mod. Taking it off takes those components off the scene's nodes.
--
-- gltf/mod_registry = {}
--
-- A value that is a table is the config; a string holding a JSON object is decoded; any other
-- value is not a component and is skipped. A re-export respawns the scene's nodes, so a property
-- deleted in Blender never reaches the new ones.

local json = require("modules/core/dkjson.lua")

-- The components a node's extras name. The explicit nil metatables keep dkjson's tables plain.
local function components(node)
    local comps = {}
    local node_extras = node:get("GltfExtras")
    local scene_extras = node:get("GltfSceneExtras")
    for _, extras in ipairs({ node_extras or {}, scene_extras or {} }) do
        local decoded = json.decode(extras.value or "", 1, nil, nil, nil)
        if type(decoded) == "table" then
            for key, value in pairs(decoded) do
                if type(value) == "string" then
                    value = json.decode(value, 1, nil, nil, nil)
                end
                if type(key) == "string" and key ~= "" and type(value) == "table" and comps[key] == nil then
                    comps[key] = value
                end
            end
        end
    end
    return comps
end

-- Bevy's scene spawner lands a scene's nodes after Update, so their extras are new here.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "GltfExtras", "GltfSceneExtras" },
            changed = { "GltfExtras", "GltfSceneExtras" },
        },
    }],
    Query[{ added = { "gltf/mod_registry" } }],
    Query[{ any_of = { "GltfExtras", "GltfSceneExtras" } }],
    Query[{ with = { "gltf/mod_registry" } }],
    Commands,
}, function(edited, added, nodes, carriers, commands)
    local list = {}
    for _, node in ipairs(edited:iter()) do
        list[#list + 1] = node:id()
    end
    for _, carrier in ipairs(added:iter()) do
        for _, id in ipairs(nodes:iter_descendants(carrier:id())) do
            list[#list + 1] = id
        end
    end
    for _, node in ipairs(nodes:iter_many(list)) do
        if carriers:iter_many(carriers:iter_ancestors(node:id()))[1] ~= nil then
            local comps = components(node)
            -- The names come from the file: that is this mod's job, so a map can load any mod.
            if next(comps) ~= nil then
                commands:entity(node:id()):insert(comps)
            end
        end
    end
end):in_set("gltf/mod_registry/apply")

-- The carrier stays and its scene with it: the components the extras gave go.
app:add_systems(First, {
    Query[{ removed = { "gltf/mod_registry" } }],
    Query[{ any_of = { "GltfExtras", "GltfSceneExtras" } }],
    Commands,
}, function(removed, nodes, commands)
    for _, carrier in ipairs(removed:iter()) do
        for _, node in ipairs(nodes:iter_many(nodes:iter_descendants(carrier:id()))) do
            for key in pairs(components(node)) do
                commands:entity(node:id()):try_remove(key)
            end
        end
    end
end):in_set("gltf/mod_registry/removed")

return {}
