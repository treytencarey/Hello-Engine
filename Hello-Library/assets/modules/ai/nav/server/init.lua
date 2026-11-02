-- Navigation for the agents that carry it: the graph of what is walkable, built from the regions
-- and links any level source publishes, and a path for what an agent is asked to go to. Missing
-- fields get defaults when it is added.
--
-- ai/nav = {
--     capabilities = { <capability> = true, ... },
-- }
--
-- ai/nav/request = {
--     <asker> = { to = { x, y, z } },
-- }: added empty with `ai/nav`, and each asker writes and removes only its own key
--
-- ai/nav/path = {
--     solved_id = <changes with each new path>,
--     status = "ready" | "unreachable",
--     path = { { x, y, z, kind, behavior }, ... },
--     regions = { <region index>, ... },
-- }
--
-- ai/nav/serving = {
--     key = <the entry it is serving>,
--     to = <where that entry goes>,
--     entries = <the entries as it last saw them>,
--     answered = <the entry `ai/nav/path` answers>,
-- }
--
-- ai/nav/search = {
--     job = <a search in progress, none before it starts>,
-- }: while an answer is owed
--
-- ai/nav/region = { min_x, max_x, min_z, max_z, y, min_y, max_y, cost }, on any entity
-- ai/nav/link = { from = { x, y, z }, to = { x, y, z }, x, y, z, cost, kind, capability, behavior, one_way }, on any entity
--
-- The resource ai/nav/graph = {
--     regions = { { min_x, max_x, min_z, max_z, y, min_y, max_y, cost, center = <a Vec2, its y the world's z> }, ... },
--     edges = { [<region index>] = { { to, cost, x, y, z, kind, capability, behavior }, ... } },
--     warned = { [<"x,y,z">] = true }: link ends already warned about,
-- }

local Graph = require("modules/ai/nav/server/graph.lua")
local Time = require("bevy::time::Time")
local LuaFrameBudget = require("bevy_lua_ecs::lua_frame_budget::LuaFrameBudget")
local any_match_filter = require("bevy::ecs::schedule::common_conditions::any_match_filter")
local any_component_removed = require("bevy::ecs::schedule::common_conditions::any_component_removed")

app:add_systems(First, {
    Query[{ added = { "ai/nav" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        -- A patch, so a reload keeps the entries there.
        commands:entity(e:id()):patch({ ["ai/nav/request"] = {} })
        commands:init_resource("ai/nav/graph", { regions = {}, edges = {}, warned = {} })
    end
end):in_set("ai/nav/init")

local changed = any_match_filter[{
    ["or"] = {
        changed = { "ai/nav/region", "ai/nav/link" },
    },
}]
local changed_or_region_gone = changed["or"](changed, any_component_removed["ai/nav/region"])

-- The condition's first run sees every region as changed, so regions older than this mod count.
-- Links name positions, so a region respawned where it was keeps its links. A changed graph owes
-- every served entry a new answer.
app:add_systems(First, {
    Query[{ with = { "ai/nav/region" } }],
    Query[{ with = { "ai/nav/link" } }],
    Query[{ with = { "ai/nav/serving" } }],
    Res["ai/nav/graph"],
    Commands,
}, function(regions, links, served, graph, commands)
    local list, linked = {}, {}
    for _, e in ipairs(regions:iter()) do
        local r = e:get("ai/nav/region")
        if r.min_x and r.max_x and r.min_z and r.max_z then
            list[#list + 1] = {
                min_x = r.min_x,
                max_x = r.max_x,
                min_z = r.min_z,
                max_z = r.max_z,
                y = r.y or 0,
                min_y = r.min_y or r.y or 0,
                max_y = r.max_y or r.y or 0,
                cost = r.cost or 1,
                center = { x = (r.min_x + r.max_x) * 0.5, y = (r.min_z + r.max_z) * 0.5 },
            }
        end
    end
    for _, e in ipairs(links:iter()) do
        linked[#linked + 1] = e:get("ai/nav/link")
    end

    local edges, missing = Graph.build_edges(list, linked)
    local warned = graph:get().warned
    for _, at in ipairs(missing) do
        local where = string.format("%g,%g,%g", at.x, at.y or 0, at.z)
        if not warned[where] then
            warned[where] = true
            print("[ai/nav] a link's end has no region near it: " .. where)
        end
    end
    commands:insert_resource("ai/nav/graph", { regions = list, edges = edges, warned = warned })

    for _, e in ipairs(served:iter()) do
        commands:entity(e:id()):try_insert({ ["ai/nav/search"] = {} })
    end
end):in_set("ai/nav/index"):after("ai/nav/init")
    :run_if(changed_or_region_gone["or"](changed_or_region_gone, any_component_removed["ai/nav/link"]))

local function same_place(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

-- Which entry to serve. An entry that is new, or goes somewhere new, comes first: at a handover
-- the old one can still be there for a frame. Then the one it is serving, then any.
app:add_systems(PreUpdate, {
    Query[{
        changed = { "ai/nav/request" },
        with = { "ai/nav" },
        optional = { "ai/nav/serving" },
    }],
    Commands,
}, function(asked, commands)
    for _, e in ipairs(asked:iter()) do
        local request = e:get("ai/nav/request")
        local serving = e:get("ai/nav/serving") or { entries = {} }
        local entity = commands:entity(e:id())

        local wanted, keys = {}, {}
        for key, entry in pairs(request) do
            if entry.to then
                wanted[key] = entry
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)

        local pick
        for _, key in ipairs(keys) do
            local before = serving.entries[key]
            if pick == nil and (before == nil or not same_place(before.to, wanted[key].to)) then
                pick = key
            end
        end
        if pick == nil then
            pick = wanted[serving.key] and serving.key or keys[1]
        end

        if pick == nil then
            entity:try_remove("ai/nav/path", "ai/nav/serving", "ai/nav/search")
        else
            local to = wanted[pick].to
            if pick ~= serving.key or not same_place(serving.to, to) then
                entity:insert({ ["ai/nav/search"] = {} })
            end
            local answered = serving.answered
            if answered and not wanted[answered] then
                answered = nil
                entity:try_remove("ai/nav/path")
            end
            entity:insert({ ["ai/nav/serving"] = { key = pick, to = to, entries = wanted, answered = answered } })
        end
    end
end):in_set("ai/nav/serve")

-- A whole write: a patch would merge a short path over a long one.
local function answer(commands, e, time, status, path, regions)
    commands:entity(e:id()):insert({
        ["ai/nav/path"] = { solved_id = time:elapsed_secs_f64(), status = status, path = path, regions = regions },
    })
    commands:entity(e:id()):patch({ ["ai/nav/serving"] = { answered = e:get("ai/nav/serving").key } })
    commands:entity(e:id()):remove("ai/nav/search")
end

-- It polls while a search is owed, one at a time, until the system's slice of the frame is spent.
-- An off-graph start, or the goal's own region, walks straight at the goal, as does a world with no
-- regions at all.
app:add_systems(PreUpdate, {
    Res[Time],
    Res[LuaFrameBudget],
    Res["ai/nav/graph"],
    Query[{
        with = { "ai/nav", "ai/nav/serving", Mut["ai/nav/search"], "Transform" },
    }],
    Commands,
}, function(time, budget, graph, searching, commands)
    local spent = false
    for _, e in ipairs(searching:iter_mut()) do
        if not spent then
            local g = graph:get()
            local to = e:get("ai/nav/serving").to
            local job = e:get("ai/nav/search").job
            local straight = { { x = to.x, y = to.y, z = to.z, kind = "goal" } }

            if job == nil and #g.regions == 0 then
                answer(commands, e, time, "ready", straight, {})
            elseif job == nil then
                local at = e:get("Transform").translation
                local start, goal = Graph.locate(g.regions, at.x, at.y, at.z), Graph.locate(g.regions, to.x, to.y, to.z)
                if goal == nil then
                    answer(commands, e, time, "unreachable", {}, {})
                elseif start == nil or start == goal then
                    answer(commands, e, time, "ready", straight, {})
                else
                    job = Graph.new_job(start, goal, to, e:get("ai/nav").capabilities)
                end
            end

            if job ~= nil then
                local done
                repeat
                    done = Graph.step(job, g.regions, g.edges)
                    spent = budget:over_budget()
                until done or spent
                if done then
                    local path, regions = Graph.extract_path(job)
                    answer(commands, e, time, path and "ready" or "unreachable", path or {}, regions or {})
                else
                    e:set({ ["ai/nav/search"] = { job = job } })
                end
            else
                spent = budget:over_budget()
            end
        end
    end
end):in_set("ai/nav/solve"):after("ai/nav/serve")

return {
    defaults = {
        ["ai/nav"] = { capabilities = {} },
    },
}
