-- Carves a sampled volume into walkable rectangles, in plain functions: the caller supplies each
-- cell's floor heights. A 100x100 volume at 1 m is 10 000 cells but usually a handful of
-- rectangles, which keeps the navigation graph small.
--
-- grid = {
--     min_x, min_z, cell, w, h,
--     floor = { [iz] = { [ix] = { <y>, ... } } }: a cell's floors, the highest first,
--     blocked = { [iz] = { [ix] = { [<index in floor>] = true } } }: something stands on it,
--     walkable = { [iz] = { [ix] = { [<index in floor>] = true } } },
-- }

local M = {}

function M.new(min_x, min_z, max_x, max_z, cell)
    local w = math.max(1, math.ceil((max_x - min_x) / cell))
    local h = math.max(1, math.ceil((max_z - min_z) / cell))
    local floor, blocked, walkable = {}, {}, {}
    for iz = 1, h do
        floor[iz], blocked[iz], walkable[iz] = {}, {}, {}
        for ix = 1, w do
            floor[iz][ix], blocked[iz][ix], walkable[iz][ix] = {}, {}, {}
        end
    end
    return { min_x = min_x, min_z = min_z, cell = cell, w = w, h = h, floor = floor, blocked = blocked, walkable = walkable }
end

function M.cell_center(g, ix, iz)
    return g.min_x + (ix - 0.5) * g.cell, g.min_z + (iz - 0.5) * g.cell
end

-- A floor is walkable when every orthogonal neighbour that found a floor has one within
-- `max_step` of it, and nothing stands on it. So the flat ground around an obstacle stays, the slope
-- up it does not, and a cliff's edge is the boundary, with a storey overhead or underfoot making no
-- difference. A steep ramp and a wall look the same: both exceed the step. A floor something stands
-- on is still a level to its neighbours, so a thin wall takes only the cells it passes through.
function M.mark_walkable(g, max_step)
    local function level(y, floors)
        if floors == nil or #floors == 0 then
            return true
        end
        for _, other in ipairs(floors) do
            if math.abs(other - y) <= max_step then
                return true
            end
        end
        return false
    end

    local none = {}
    for iz = 1, g.h do
        local row, before, after = g.floor[iz], g.floor[iz - 1] or none, g.floor[iz + 1] or none
        for ix = 1, g.w do
            for k, y in ipairs(row[ix]) do
                if not g.blocked[iz][ix][k] and level(y, row[ix + 1]) and level(y, row[ix - 1]) and level(y, before[ix]) and level(y, after[ix]) then
                    g.walkable[iz][ix][k] = true
                end
            end
        end
    end
end

-- Greedy: from the first free floor, extend right, then down while the whole row below matches,
-- only through floors within `max_step` of the one it started from. So a storey carves apart from
-- the one over it, and a ramp into a run of rectangles, each a step high. Not optimal, but linear,
-- and open ground collapses to one or two boxes. A rectangle's y is its average floor, between its
-- min_y and max_y.
function M.merge_rects(g, max_step)
    local used, rects = {}, {}
    for iz = 1, g.h do
        used[iz] = {}
        for ix = 1, g.w do
            used[iz][ix] = {}
        end
    end

    -- The free floor in a cell within the step of a height.
    local function free(ix, iz, y)
        for k, other in ipairs(g.floor[iz][ix]) do
            if g.walkable[iz][ix][k] and not used[iz][ix][k] and math.abs(other - y) <= max_step then
                return k
            end
        end
        return nil
    end

    for iz = 1, g.h do
        for ix = 1, g.w do
            for k, y in ipairs(g.floor[iz][ix]) do
                if g.walkable[iz][ix][k] and not used[iz][ix][k] then
                    local x2 = ix
                    while x2 < g.w and free(x2 + 1, iz, y) do
                        x2 = x2 + 1
                    end

                    local z2 = iz
                    local extending = true
                    while extending and z2 < g.h do
                        for x = ix, x2 do
                            if not free(x, z2 + 1, y) then
                                extending = false
                            end
                        end
                        if extending then
                            z2 = z2 + 1
                        end
                    end

                    local sum, n, min_y, max_y = 0, 0, y, y
                    for z = iz, z2 do
                        for x = ix, x2 do
                            local taken = free(x, z, y)
                            used[z][x][taken] = true
                            local height = g.floor[z][x][taken]
                            sum, n = sum + height, n + 1
                            min_y, max_y = math.min(min_y, height), math.max(max_y, height)
                        end
                    end

                    rects[#rects + 1] = {
                        min_x = g.min_x + (ix - 1) * g.cell,
                        max_x = g.min_x + x2 * g.cell,
                        min_z = g.min_z + (iz - 1) * g.cell,
                        max_z = g.min_z + z2 * g.cell,
                        y = sum / n,
                        min_y = min_y,
                        max_y = max_y,
                    }
                end
            end
        end
    end

    return rects
end

return M
