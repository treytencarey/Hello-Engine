-- Publishes the walkable ground, so a client can draw it: its own component carries what the
-- `ai/nav/volume`, `ai/nav/region` and `ai/nav/link` entities say, as a client has none of them. A
-- volume with no region under it, or a region that does not match its volume, shows. Regions that
-- touch join with nothing to draw, so only links are drawn between them. It writes only when one of
-- those changes, so a level that stands still costs one message.
--
-- ai/debug/world = {
--     volumes = { { min_x, max_x, min_y, max_y, min_z, max_z }, ... },
--     regions = { { min_x, max_x, min_z, max_z, y }, ... },
--     links = { { from = { x, y, z }, to = { x, y, z }, x, y, z }, ... },
-- }

-- In Last, as a new volume has no place of its own until PostUpdate has worked it out.
app:add_systems(Last, {
    Query[{ with = { Mut["ai/debug/world"] } }],
    Query[{ with = { "ai/nav/volume", "GlobalTransform" } }],
    Query[{ with = { "ai/nav/region" } }],
    Query[{ with = { "ai/nav/link" } }],
}, function(carriers, volumes, regions, links)
    local value = { volumes = {}, regions = {}, links = {} }
    for _, node in ipairs(volumes:iter()) do
        local v = node:get("ai/nav/volume")
        local at = node.GlobalTransform:compute_transform().translation
        if v.hx ~= nil and v.hz ~= nil then
            local hy = v.hy or 0
            value.volumes[#value.volumes + 1] = {
                min_x = at.x - v.hx,
                max_x = at.x + v.hx,
                min_y = at.y - hy,
                max_y = at.y + hy,
                min_z = at.z - v.hz,
                max_z = at.z + v.hz,
            }
        end
    end
    for _, e in ipairs(regions:iter()) do
        local r = e:get("ai/nav/region")
        value.regions[#value.regions + 1] = { min_x = r.min_x, max_x = r.max_x, min_z = r.min_z, max_z = r.max_z, y = r.y }
    end
    for _, e in ipairs(links:iter()) do
        local l = e:get("ai/nav/link")
        value.links[#value.links + 1] = { from = l.from, to = l.to, x = l.x, y = l.y, z = l.z }
    end
    for _, e in ipairs(carriers:iter_mut()) do
        e:set({ ["ai/debug/world"] = value })
    end
end)
    :run_if({
        Query[{
            ["or"] = {
                added = { "ai/debug/world" },
                changed = { "ai/nav/volume", "ai/nav/region", "ai/nav/link" },
                removed = { "ai/nav/volume", "ai/nav/region", "ai/nav/link" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)
    :in_set("ai/debug/world/publish")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
