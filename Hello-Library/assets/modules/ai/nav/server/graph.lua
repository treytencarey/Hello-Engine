-- The navigation graph and its search, in plain functions: no systems, no components. Regions
-- are XZ boxes in a list, and a node of the graph is an index into it. Search runs over
-- regions, never over world cells, so a map with 400 rooms searches 400 nodes however large
-- they are.
--
-- region = { min_x, max_x, min_z, max_z, y, cost, center = { x, y } }
-- edge = { to = <index>, cost, x, y, z, kind, capability, behavior }
--
-- A region's `center` is a `Vec2` on the ground: its `y` is the world's z.

local Vec2 = require("bevy::math::Vec2")

local M = {}

-- The edges of each region: those whose boxes touch, then the links between two positions. Also
-- answers the positions no region is near: a link with one makes no edge.
function M.build_edges(regions, links)
    local edges, missing = {}, {}
    for i = 1, #regions do
        edges[i] = {}
    end

    for i = 1, #regions do
        local a = regions[i]
        for j = i + 1, #regions do
            local b = regions[j]
            -- Closer than 0.35 m counts as touching, along a shared border of at least 0.5 m: a
            -- corner alone is no way through.
            local min_x, max_x = math.max(a.min_x, b.min_x), math.min(a.max_x, b.max_x)
            local min_z, max_z = math.max(a.min_z, b.min_z), math.min(a.max_z, b.max_z)
            local span_x, span_z = max_x - min_x, max_z - min_z
            if span_x >= -0.35 and span_z >= -0.35 and math.max(span_x, span_z) >= 0.5 then
                local cost = Vec2.distance(a.center, b.center) * (a.cost + b.cost) * 0.5
                local x, y, z = (min_x + max_x) * 0.5, math.max(a.y, b.y), (min_z + max_z) * 0.5
                edges[i][#edges[i] + 1] = { to = j, cost = cost, x = x, y = y, z = z, kind = "walk" }
                edges[j][#edges[j] + 1] = { to = i, cost = cost, x = x, y = y, z = z, kind = "walk" }
            end
        end
    end

    for _, link in ipairs(links) do
        local from = link.from and M.locate(regions, link.from.x, link.from.z)
        local to = link.to and M.locate(regions, link.to.x, link.to.z)
        if link.from and not from then
            missing[#missing + 1] = link.from
        end
        if link.to and not to then
            missing[#missing + 1] = link.to
        end
        if from and to then
            local a, b = regions[from], regions[to]
            local edge = {
                to = to,
                cost = link.cost or Vec2.distance(a.center, b.center),
                x = link.x or (link.from.x + link.to.x) * 0.5,
                y = link.y or math.max(a.y, b.y),
                z = link.z or (link.from.z + link.to.z) * 0.5,
                kind = link.kind or "link",
                capability = link.capability,
                behavior = link.behavior,
            }
            edges[from][#edges[from] + 1] = edge
            if not link.one_way then
                edges[to][#edges[to] + 1] = {
                    to = from,
                    cost = edge.cost,
                    x = edge.x,
                    y = edge.y,
                    z = edge.z,
                    kind = edge.kind,
                    capability = edge.capability,
                    behavior = edge.behavior,
                }
            end
        end
    end

    return edges, missing
end

-- The region holding a point, the one with the nearest centre where they overlap; else the
-- nearest within 8 m.
function M.locate(regions, x, z)
    local point = { x = x, y = z }
    local best, best_d2

    for i, r in ipairs(regions) do
        if x >= r.min_x and x <= r.max_x and z >= r.min_z and z <= r.max_z then
            local d2 = Vec2.distance_squared(r.center, point)
            if not best_d2 or d2 < best_d2 then
                best, best_d2 = i, d2
            end
        end
    end
    if best then
        return best
    end

    for i, r in ipairs(regions) do
        local nearest = Vec2.clamp(point, { x = r.min_x, y = r.min_z }, { x = r.max_x, y = r.max_z })
        local d2 = Vec2.distance_squared(nearest, point)
        if d2 <= 64 and (not best_d2 or d2 < best_d2) then
            best, best_d2 = i, d2
        end
    end
    return best
end

-- A search is plain data, so it can stop at a budget and carry on in a later frame.
function M.new_job(start, goal, goal_pos, capabilities)
    return {
        start = start,
        goal = goal,
        goal_pos = goal_pos,
        capabilities = capabilities or {},
        open = { start },
        g = { [start] = 0 },
        f = { [start] = 0 },
        came = {},
        came_edge = {},
        closed = {},
        done = false,
    }
end

-- At most `budget` regions further. Answers whether the search is finished, `job.result` then
-- being "found" or "unreachable", and how many regions it looked at.
function M.step(job, regions, edges, budget)
    local steps = 0
    while not job.done and steps < budget do
        -- The open node with the lowest f. A linear scan: region graphs are small enough that a
        -- heap costs more in table churn than it saves.
        local best_i, best_f
        for i = 1, #job.open do
            local f = job.f[job.open[i]]
            if not best_f or f < best_f then
                best_i, best_f = i, f
            end
        end
        local current = best_i and job.open[best_i]
        if best_i then
            job.open[best_i] = job.open[#job.open]
            job.open[#job.open] = nil
        end

        if not current then
            job.done, job.result = true, "unreachable"
        elseif current == job.goal then
            job.done, job.result = true, "found"
        elseif not job.closed[current] then
            job.closed[current] = true
            steps = steps + 1
            for _, edge in ipairs(edges[current]) do
                local allowed = not edge.capability or job.capabilities[edge.capability]
                if allowed and not job.closed[edge.to] then
                    local tentative = job.g[current] + edge.cost
                    if not job.g[edge.to] or tentative < job.g[edge.to] then
                        job.g[edge.to] = tentative
                        job.f[edge.to] = tentative + Vec2.distance(regions[edge.to].center, regions[job.goal].center)
                        job.came[edge.to] = current
                        job.came_edge[edge.to] = edge
                        job.open[#job.open + 1] = edge.to
                    end
                end
            end
        end
    end
    return job.done, steps
end

-- A found route as waypoints, the crossings between its regions and then the goal, and the
-- regions in order. Regions are convex, so the straight line between two crossings is walkable.
function M.extract_path(job)
    if job.result ~= "found" then
        return nil, nil
    end

    local sequence, crossings = {}, {}
    local current = job.goal
    while current do
        table.insert(sequence, 1, current)
        if job.came_edge[current] then
            table.insert(crossings, 1, job.came_edge[current])
        end
        current = job.came[current]
    end

    local waypoints = {}
    for _, edge in ipairs(crossings) do
        waypoints[#waypoints + 1] = { x = edge.x, y = edge.y, z = edge.z, kind = edge.kind, behavior = edge.behavior }
    end
    waypoints[#waypoints + 1] = { x = job.goal_pos.x, y = job.goal_pos.y, z = job.goal_pos.z, kind = "goal" }
    return waypoints, sequence
end

return M
