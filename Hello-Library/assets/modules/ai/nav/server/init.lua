-- Navigation for the agents that carry it: the graph of what is walkable, built from the
-- regions and links any level source publishes. Missing fields get defaults when it is added.
--
-- ai/nav = {
--     capabilities = { <capability> = true, ... },
-- }
--
-- ai/nav/region = { min_x, max_x, min_z, max_z, y, cost }, on any entity
-- ai/nav/link = { from = <region entity>, to = <region entity>, x, y, z, cost, kind, capability, behavior, one_way }, on any entity
--
-- The resource ai/nav/graph = {
--     regions = { { entity, min_x, max_x, min_z, max_z, y, cost, center = <a Vec2, its y the world's z> }, ... },
--     edges = { [<region index>] = { { to, cost, x, y, z, kind, capability, behavior }, ... } },
-- }

local Graph = require("modules/ai/nav/server/graph.lua")

app:add_systems(First, {
    Query[{ added = { "ai/nav" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local n = e:get("ai/nav")
        commands:entity(e:id()):patch({
            ["ai/nav"] = { capabilities = n.capabilities or {} },
        })
    end
end):in_set("ai/nav/init")

-- This system's first run sees every region as changed, so regions older than this mod count.
app:add_systems(First, {
    Query[{
        ["or"] = {
            changed = { "ai/nav/region", "ai/nav/link" },
            removed = { "ai/nav/region", "ai/nav/link" },
        },
    }],
    Query[{ with = { "ai/nav/region" } }],
    Query[{ with = { "ai/nav/link" } }],
    Commands,
}, function(touched, regions, links, commands)
    if not touched:is_empty() then
        local list, linked = {}, {}
        for _, e in ipairs(regions:iter()) do
            local r = e:get("ai/nav/region")
            if r.min_x and r.max_x and r.min_z and r.max_z then
                list[#list + 1] = {
                    entity = e:id(),
                    min_x = r.min_x,
                    max_x = r.max_x,
                    min_z = r.min_z,
                    max_z = r.max_z,
                    y = r.y or 0,
                    cost = r.cost or 1,
                    center = { x = (r.min_x + r.max_x) * 0.5, y = (r.min_z + r.max_z) * 0.5 },
                }
            end
        end
        for _, e in ipairs(links:iter()) do
            linked[#linked + 1] = e:get("ai/nav/link")
        end
        commands:insert_resource("ai/nav/graph", { regions = list, edges = Graph.build_edges(list, linked) })
    end
end):in_set("ai/nav/index")
