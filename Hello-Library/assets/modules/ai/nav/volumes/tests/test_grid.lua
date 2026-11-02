-- --host
-- Floor heights in, walkable rectangles out, with no rays: a fault here is in the carving, not in
-- what fed it.
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Grid = require("modules/ai/nav/volumes/server/grid.lua")

local suite = helpers.create_suite("GridSuite")

-- Every cell's floor, from what `height` says for it.
local function fill(g, height)
    for iz = 1, g.h do
        for ix = 1, g.w do
            g.floor[iz][ix] = height(ix, iz)
        end
    end
    return g
end

local function flat(w, h, cell, y)
    return fill(Grid.new(0, 0, w * cell, h * cell, cell), function() return y end)
end

local function area(g, rects)
    local n = 0
    for _, r in ipairs(rects) do
        n = n + math.floor((r.max_x - r.min_x) / g.cell + 0.5) * math.floor((r.max_z - r.min_z) / g.cell + 0.5)
    end
    return n
end

-- Every walkable cell in exactly one rectangle, and no rectangle over any other cell.
local function tiles_exactly(g, rects)
    local hits = {}
    for iz = 1, g.h do
        hits[iz] = {}
    end
    for _, r in ipairs(rects) do
        for iz = 1, g.h do
            for ix = 1, g.w do
                local x, z = Grid.cell_center(g, ix, iz)
                if x > r.min_x and x < r.max_x and z > r.min_z and z < r.max_z then
                    if not g.walkable[iz][ix] or hits[iz][ix] then
                        return false
                    end
                    hits[iz][ix] = true
                end
            end
        end
    end
    for iz = 1, g.h do
        for ix = 1, g.w do
            if g.walkable[iz][ix] and not hits[iz][ix] then
                return false
            end
        end
    end
    return true
end

local finished = false

app:add_systems(Update, {}, function()
    if finished then return end
    finished = true

    local sized = Grid.new(0, 0, 7, 5, 1)
    suite.assert_test("GR1_a_grid_has_its_rows_and_columns", sized.w == 7 and sized.h == 5 and #sized.floor == 5, "")
    local x, z = Grid.cell_center(sized, 1, 1)
    suite.assert_test("GR2_a_cell_centre_is_half_a_cell_in", x == 0.5 and z == 0.5, "")
    suite.assert_test("GR3_a_part_cell_still_counts", Grid.new(0, 0, 2.5, 1, 1).w == 3, "")

    local plane = flat(37, 37, 1, 3.25)
    Grid.mark_walkable(plane, 0.45)
    local one = Grid.merge_rects(plane)
    suite.assert_test("GR4_a_flat_plane_is_one_rectangle_over_all_of_it",
        #one == 1 and one[1].min_x == 0 and one[1].max_x == 37 and one[1].min_z == 0 and one[1].max_z == 37
            and one[1].y == 3.25, "rects " .. #one)
    local coarse = flat(13, 7, 2.5, -4)
    Grid.mark_walkable(coarse, 0.45)
    local wide = Grid.merge_rects(coarse)
    suite.assert_test("GR5_the_cell_size_scales_it", #wide == 1 and wide[1].max_x == 32.5 and wide[1].max_z == 17.5, "")

    local ramp = fill(Grid.new(0, 0, 10, 10, 1), function(ix) return ix * 0.1 end)
    Grid.mark_walkable(ramp, 0.45)
    local slope = Grid.merge_rects(ramp)
    suite.assert_test("GR6_a_gentle_slope_stays_walkable_at_its_average_height",
        #slope == 1 and math.abs(slope[1].y - 0.55) < 1e-6, "rects " .. #slope)

    local cliff = fill(Grid.new(0, 0, 10, 10, 1), function(ix) return ix <= 5 and 0 or 10 end)
    Grid.mark_walkable(cliff, 0.45)
    suite.assert_test("GR7_a_cliffs_edge_is_not_walkable_and_the_ground_beyond_is",
        not cliff.walkable[1][5] and not cliff.walkable[1][6] and cliff.walkable[1][1] and cliff.walkable[10][10], "")
    suite.assert_test("GR8_a_cliff_splits_the_ground", #Grid.merge_rects(cliff) == 2, "")
    local diagonal = fill(Grid.new(0, 0, 3, 3, 1), function(ix, iz) return iz == 3 and 10 or (ix == 3 and 20 or 0) end)
    Grid.mark_walkable(diagonal, 0.45)
    suite.assert_test("GR9_every_neighbour_counts",
        diagonal.walkable[1][1] and not diagonal.walkable[1][2] and not diagonal.walkable[2][1]
            and not diagonal.walkable[3][3], "")

    local holed = flat(5, 5, 1, 0)
    holed.floor[3][3] = false
    Grid.mark_walkable(holed, 0.45)
    suite.assert_test("GR10_a_cell_with_no_floor_is_a_hole_and_harms_no_neighbour",
        not holed.walkable[3][3] and holed.walkable[3][2] and holed.walkable[3][4], "")
    local around = Grid.merge_rects(holed)
    suite.assert_test("GR11_rectangles_tile_around_a_hole", tiles_exactly(holed, around) and area(holed, around) == 24,
        "area " .. area(holed, around))

    local sparse = flat(4, 4, 1, 0)
    sparse.floor[2][2] = nil
    Grid.mark_walkable(sparse, 0.45)
    suite.assert_test("GR12_an_unsampled_cell_is_a_hole_too", not sparse.walkable[2][2], "")

    local plus = Grid.new(0, 0, 5, 5, 1)
    for iz = 1, 5 do
        for ix = 1, 5 do
            if ix == 3 or iz == 3 then
                plus.floor[iz][ix] = 0
                plus.walkable[iz][ix] = true
            end
        end
    end
    local arms = Grid.merge_rects(plus)
    suite.assert_test("GR13_a_plus_tiles_exactly", tiles_exactly(plus, arms) and area(plus, arms) == 9, "")

    local stairs = Grid.new(0, 0, 6, 6, 1)
    for iz = 1, 6 do
        for ix = 1, iz do
            stairs.floor[iz][ix] = 0
            stairs.walkable[iz][ix] = true
        end
    end
    local steps = Grid.merge_rects(stairs)
    suite.assert_test("GR14_a_staircase_tiles_exactly", tiles_exactly(stairs, steps) and area(stairs, steps) == 21, "")

    local empty = flat(4, 4, 1, false)
    Grid.mark_walkable(empty, 0.45)
    suite.assert_test("GR15_nothing_walkable_is_no_rectangles", #Grid.merge_rects(empty) == 0, "")

    suite.finish("GridSuite")
end):in_set("zz/grid_suite")
