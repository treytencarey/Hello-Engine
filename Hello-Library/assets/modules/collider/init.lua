-- The base of the collider mods (`collider/mesh`, `collider/bb`): the registry adds it beside
-- one, and that mod sets `built` once the carrier's shapes are built. It keeps the books for
-- each scene: on the nearest SceneRoot above its carriers, `collider/status` says whether any
-- of them is still building. It is added with the scene's first carrier, written only when the
-- state changes, and removed with the last.
--
-- collider = {
--     built = <true once every primitive of the carrier has its shape>,
-- }
--
-- collider/status = {
--     state = <"building" while any carrier under the root is not built, else "done">,
-- }

-- A despawned carrier's root can't be read, so a removal looks at every root with a status.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "collider" },
            changed = { "collider" },
        },
    }],
    Query[{ removed = { "collider" } }],
    Query[{
        with = { "SceneRoot" },
        optional = { Mut["collider/status"] },
    }],
    Query[{ with = { "SceneRoot", "collider/status" } }],
    Query[{ with = { "collider" } }],
    Commands,
}, function(touched, removed, roots, tracked, carriers, commands)
    local list = {}
    for _, e in ipairs(touched:iter()) do
        local up = roots:iter_ancestors(e:id())
        table.insert(up, 1, e:id())
        local root = roots:iter_many(up)[1]
        if root ~= nil then
            list[#list + 1] = root:id()
        end
    end
    if not removed:is_empty() then
        for _, root in ipairs(tracked:iter()) do
            list[#list + 1] = root:id()
        end
    end
    for _, root in ipairs(roots:iter_many_mut(list)) do
        local under = carriers:iter_descendants(root:id())
        table.insert(under, 1, root:id())
        local found = carriers:iter_many(under)
        local state = #found > 0 and "done" or nil
        for _, carrier in ipairs(found) do
            local c = carrier:get("collider")
            if c.built ~= true then
                state = "building"
                break
            end
        end
        if state == nil then
            commands:entity(root:id()):try_remove("collider/status")
        elseif root:has("collider/status") then
            root:get_mut("collider/status"):set_if_neq({ state = state })
        else
            commands:entity(root:id()):insert({ ["collider/status"] = { state = state } })
        end
    end
end):in_set("collider/status")

return {
    defaults = {
        collider = { built = false },
    },
}
