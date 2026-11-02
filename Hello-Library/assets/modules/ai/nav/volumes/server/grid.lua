-- Carves a sampled volume into walkable rectangles, in plain functions: the caller supplies the
-- floor heights. A 100x100 volume at 1 m is 10 000 cells but usually a handful of rectangles,
-- which keeps the navigation graph small.
--
-- grid = { min_x, min_z, cell, w, h, floor = { [iz] = { [ix] = <y> or false } }, walkable = { [iz] = { [ix] = true } } }

local M = {}

function M.new(min_x, min_z, max_x, max_z, cell)
    local w = math.max(1, math.ceil((max_x - min_x) / cell))
    local h = math.max(1, math.ceil((max_z - min_z) / cell))
    local floor, walkable = {}, {}
    for iz = 1, h do
        floor[iz], walkable[iz] = {}, {}
    end
    return { min_x = min_x, min_z = min_z, cell = cell, w = w, h = h, floor = floor, walkable = walkable }
end

function M.cell_center(g, ix, iz)
    return g.min_x + (ix - 0.5) * g.cell, g.min_z + (iz - 0.5) * g.cell
end

-- A cell is walkable when it found a floor and every orthogonal neighbour that found one is
-- within `max_step` of it. So the flat ground around an obstacle stays, the slope up it does
-- not, and a cliff's edge is the boundary. A steep ramp and a wall look the same: both exceed
-- the step.
function M.mark_walkable(g, max_step)
    local function level(y, other)
        return not other or math.abs(other - y) <= max_step
    end

    local none = {}
    for iz = 1, g.h do
        local row, before, after = g.floor[iz], g.floor[iz - 1] or none, g.floor[iz + 1] or none
        for ix = 1, g.w do
            local y = row[ix]
            if y and level(y, row[ix + 1]) and level(y, row[ix - 1]) and level(y, before[ix]) and level(y, after[ix]) then
                g.walkable[iz][ix] = true
            end
        end
    end
end

-- Greedy: from the first free cell, extend right while walkable, then down while the whole row
-- below matches. Not optimal, but linear, and open ground collapses to one or two boxes. A
-- rectangle's y is its average floor, so a gentle slope sits sensibly.
function M.merge_rects(g)
    local used, rects = {}, {}
    for iz = 1, g.h do
        used[iz] = {}
    end

    local function free(ix, iz)
        return g.walkable[iz][ix] and not used[iz][ix]
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
                        used[z][x] = true
                        sum, n = sum + g.floor[z][x], n + 1
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
