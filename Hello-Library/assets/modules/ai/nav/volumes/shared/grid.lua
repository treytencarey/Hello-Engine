-- Carves a sampled volume into walkable rectangles, in plain functions: the caller supplies the
-- floor heights. A 100x100 volume at 1 m is 10 000 cells but usually a handful of rectangles,
-- which keeps the navigation graph small.
--
-- grid = { min_x, min_z, cell, w, h, count, floor = { [<index>] = <y> or false }, walkable = { [<index>] = true } }

local M = {}

function M.index(g, ix, iz)
    return (iz - 1) * g.w + ix
end

function M.new(min_x, min_z, max_x, max_z, cell)
    local w = math.max(1, math.ceil((max_x - min_x) / cell))
    local h = math.max(1, math.ceil((max_z - min_z) / cell))
    return { min_x = min_x, min_z = min_z, cell = cell, w = w, h = h, count = w * h, floor = {}, walkable = {} }
end

function M.cell_center(g, ix, iz)
    return g.min_x + (ix - 0.5) * g.cell, g.min_z + (iz - 0.5) * g.cell
end

function M.coords(g, i)
    local iz = math.floor((i - 1) / g.w) + 1
    return i - (iz - 1) * g.w, iz
end

-- A cell is walkable when it found a floor and every orthogonal neighbour that found one is
-- within `max_step` of it. So the flat ground around an obstacle stays, the slope up it does
-- not, and a cliff's edge is the boundary. A steep ramp and a wall look the same: both exceed
-- the step.
function M.mark_walkable(g, max_step)
    for i = 1, g.count do
        local y = g.floor[i]
        if y then
            local ix, iz = M.coords(g, i)
            local level = true
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local nx, nz = ix + d[1], iz + d[2]
                if nx >= 1 and nx <= g.w and nz >= 1 and nz <= g.h then
                    local ny = g.floor[M.index(g, nx, nz)]
                    if ny and math.abs(ny - y) > max_step then
                        level = false
                    end
                end
            end
            if level then
                g.walkable[i] = true
            end
        end
    end
end

-- Greedy: from the first free cell, extend right while walkable, then down while the whole row
-- below matches. Not optimal, but linear, and open ground collapses to one or two boxes. A
-- rectangle's y is its average floor, so a gentle slope sits sensibly.
function M.merge_rects(g)
    local used, rects = {}, {}

    local function free(ix, iz)
        local i = M.index(g, ix, iz)
        return g.walkable[i] and not used[i]
    end

    for iz = 1, g.h do
        for ix = 1, g.w do
            if free(ix, iz) then
                local x2 = ix
                while x2 < g.w and free(x2 + 1, iz) do
                    x2 = x2 + 1
                end

                local z2 = iz
                local extending = true
                while extending and z2 < g.h do
                    for x = ix, x2 do
                        if not free(x, z2 + 1) then
                            extending = false
                        end
                    end
                    if extending then
                        z2 = z2 + 1
                    end
                end

                local sum, n = 0, 0
                for z = iz, z2 do
                    for x = ix, x2 do
                        local i = M.index(g, x, z)
                        used[i] = true
                        sum, n = sum + g.floor[i], n + 1
                    end
                end

                rects[#rects + 1] = {
                    min_x = g.min_x + (ix - 1) * g.cell,
                    max_x = g.min_x + x2 * g.cell,
                    min_z = g.min_z + (iz - 1) * g.cell,
                    max_z = g.min_z + z2 * g.cell,
                    y = sum / n,
                }
            end
        end
    end

    return rects
end

return M
