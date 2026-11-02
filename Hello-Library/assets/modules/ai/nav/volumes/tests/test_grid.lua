-- --host
-- Floor heights in, walkable rectangles out, with no rays: a fault here is in the carving, not in
-- what fed it.
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Grid = require("modules/ai/nav/volumes/shared/grid.lua")

local suite = helpers.create_suite("GridSuite")

local function flat(w, h, cell, y)
    local g = Grid.new(0, 0, w * cell, h * cell, cell)
    for i = 1, g.count do
        g.floor[i] = y
    end
    return g
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
    for _, r in ipairs(rects) do
        for iz = 1, g.h do
            for ix = 1, g.w do
                local x, z = Grid.cell_center(g, ix, iz)
                if x > r.min_x and x < r.max_x and z > r.min_z and z < r.max_z then
                    local i = Grid.index(g, ix, iz)
                    if not g.walkable[i] or hits[i] then
                        return false
                    end
                    hits[i] = true
                end
            end
        end
    end
    for i = 1, g.count do
        if g.walkable[i] and not hits[i] then
            return false
        end
    end
    return true
end

local finished = false

app:add_systems(Update, {}, function()
    if finished then return end
    finished = true

    local sized = Grid.new(0, 0, 7, 5, 1)
    local round = true
    for i = 1, sized.count do
        local ix, iz = Grid.coords(sized, i)
        round = round and Grid.index(sized, ix, iz) == i and ix >= 1 and ix <= 7 and iz >= 1 and iz <= 5
    end
    suite.assert_test("GR1_cells_number_and_locate", sized.count == 35 and round, "")
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

    local ramp = Grid.new(0, 0, 10, 10, 1)
    for i = 1, ramp.count do
        ramp.floor[i] = Grid.coords(ramp, i) * 0.1
    end
    Grid.mark_walkable(ramp, 0.45)
    local slope = Grid.merge_rects(ramp)
    suite.assert_test("GR6_a_gentle_slope_stays_walkable_at_its_average_height",
        #slope == 1 and math.abs(slope[1].y - 0.55) < 1e-6, "rects " .. #slope)

    local cliff = Grid.new(0, 0, 10, 10, 1)
    for i = 1, cliff.count do
        cliff.floor[i] = Grid.coords(cliff, i) <= 5 and 0 or 10
    end
    Grid.mark_walkable(cliff, 0.45)
    suite.assert_test("GR7_a_cliffs_edge_is_not_walkable_and_the_ground_beyond_is",
        not cliff.walkable[Grid.index(cliff, 5, 1)] and not cliff.walkable[Grid.index(cliff, 6, 1)]
            and cliff.walkable[Grid.index(cliff, 1, 1)] and cliff.walkable[Grid.index(cliff, 10, 10)], "")
    suite.assert_test("GR8_a_cliff_splits_the_ground", #Grid.merge_rects(cliff) == 2, "")
    local diagonal = Grid.new(0, 0, 3, 3, 1)
    for i = 1, diagonal.count do
        local ix, iz = Grid.coords(diagonal, i)
        diagonal.floor[i] = iz == 3 and 10 or (ix == 3 and 20 or 0)
    end
    Grid.mark_walkable(diagonal, 0.45)
    suite.assert_test("GR9_every_neighbour_counts",
        diagonal.walkable[Grid.index(diagonal, 1, 1)] and not diagonal.walkable[Grid.index(diagonal, 2, 1)]
            and not diagonal.walkable[Grid.index(diagonal, 1, 2)] and not diagonal.walkable[Grid.index(diagonal, 3, 3)], "")

    local holed = flat(5, 5, 1, 0)
    holed.floor[Grid.index(holed, 3, 3)] = false
    Grid.mark_walkable(holed, 0.45)
    suite.assert_test("GR10_a_cell_with_no_floor_is_a_hole_and_harms_no_neighbour",
        not holed.walkable[Grid.index(holed, 3, 3)] and holed.walkable[Grid.index(holed, 2, 3)]
            and holed.walkable[Grid.index(holed, 4, 3)], "")
    local around = Grid.merge_rects(holed)
    suite.assert_test("GR11_rectangles_tile_around_a_hole", tiles_exactly(holed, around) and area(holed, around) == 24,
        "area " .. area(holed, around))

    local sparse = flat(4, 4, 1, 0)
    sparse.floor[Grid.index(sparse, 2, 2)] = nil
    Grid.mark_walkable(sparse, 0.45)
    suite.assert_test("GR12_an_unsampled_cell_is_a_hole_too", not sparse.walkable[Grid.index(sparse, 2, 2)], "")

    local plus = Grid.new(0, 0, 5, 5, 1)
    for iz = 1, 5 do
        for ix = 1, 5 do
            if ix == 3 or iz == 3 then
                plus.floor[Grid.index(plus, ix, iz)] = 0
                plus.walkable[Grid.index(plus, ix, iz)] = true
            end
        end
    end
    local arms = Grid.merge_rects(plus)
    suite.assert_test("GR13_a_plus_tiles_exactly", tiles_exactly(plus, arms) and area(plus, arms) == 9, "")

    local stairs = Grid.new(0, 0, 6, 6, 1)
    for iz = 1, 6 do
        for ix = 1, iz do
            stairs.floor[Grid.index(stairs, ix, iz)] = 0
            stairs.walkable[Grid.index(stairs, ix, iz)] = true
        end
    end
    local steps = Grid.merge_rects(stairs)
    suite.assert_test("GR14_a_staircase_tiles_exactly", tiles_exactly(stairs, steps) and area(stairs, steps) == 21, "")

    local empty = flat(4, 4, 1, false)
    Grid.mark_walkable(empty, 0.45)
    suite.assert_test("GR15_nothing_walkable_is_no_rectangles", #Grid.merge_rects(empty) == 0, "")

    suite.finish("GridSuite")
end):in_set("zz/grid_suite")
