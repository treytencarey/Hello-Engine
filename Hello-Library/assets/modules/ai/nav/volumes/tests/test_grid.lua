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
            local y = height(ix, iz)
            g.floor[iz][ix] = y and { y } or {}
        end
    end
    return g
end

-- A rectangle's tile over a cell, whichever floor it took.
local function any_walkable(g, ix, iz)
    return next(g.walkable[iz][ix]) ~= nil
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
                    if not any_walkable(g, ix, iz) or hits[iz][ix] then
                        return false
                    end
                    hits[iz][ix] = true
                end
            end
        end
    end
    for iz = 1, g.h do
        for ix = 1, g.w do
            if any_walkable(g, ix, iz) and not hits[iz][ix] then
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
    local one = Grid.merge_rects(plane, 0.45)
    suite.assert_test("GR4_a_flat_plane_is_one_rectangle_over_all_of_it",
        #one == 1 and one[1].min_x == 0 and one[1].max_x == 37 and one[1].min_z == 0 and one[1].max_z == 37
            and one[1].y == 3.25, "rects " .. #one)
    local coarse = flat(13, 7, 2.5, -4)
    Grid.mark_walkable(coarse, 0.45)
    local wide = Grid.merge_rects(coarse, 0.45)
    suite.assert_test("GR5_the_cell_size_scales_it", #wide == 1 and wide[1].max_x == 32.5 and wide[1].max_z == 17.5, "")

    local ramp = fill(Grid.new(0, 0, 10, 10, 1), function(ix) return ix * 0.1 end)
    Grid.mark_walkable(ramp, 0.45)
    local slope = Grid.merge_rects(ramp, 0.45)
    suite.assert_test("GR6_a_slope_carves_into_rectangles_a_step_high",
        #slope == 2 and math.abs(slope[1].y - 0.3) < 1e-6 and math.abs(slope[1].min_y - 0.1) < 1e-6
            and math.abs(slope[1].max_y - 0.5) < 1e-6 and math.abs(slope[2].min_y - 0.6) < 1e-6 and math.abs(slope[2].max_y - 1) < 1e-6,
        "rects " .. #slope)
    local down = fill(Grid.new(0, 0, 4, 4, 1), function(ix) return 1 - ix * 0.1 end)
    Grid.mark_walkable(down, 0.45)
    local falling = Grid.merge_rects(down, 0.45)
    suite.assert_test("GR6c_a_rectangle_records_the_lowest_it_goes", #falling == 1 and math.abs(falling[1].min_y - 0.6) < 1e-6
        and math.abs(falling[1].max_y - 0.9) < 1e-6, "rects " .. #falling)
    local gentle = fill(Grid.new(0, 0, 4, 4, 1), function(ix) return ix * 0.1 end)
    Grid.mark_walkable(gentle, 0.45)
    local whole = Grid.merge_rects(gentle, 0.45)
    suite.assert_test("GR6b_a_slope_within_a_step_stays_one_rectangle_at_its_average_height", #whole == 1
        and math.abs(whole[1].y - 0.25) < 1e-6, "rects " .. #whole)

    local cliff = fill(Grid.new(0, 0, 10, 10, 1), function(ix) return ix <= 5 and 0 or 10 end)
    Grid.mark_walkable(cliff, 0.45)
    suite.assert_test("GR7_a_cliffs_edge_is_not_walkable_and_the_ground_beyond_is",
        not any_walkable(cliff, 5, 1) and not any_walkable(cliff, 6, 1) and any_walkable(cliff, 1, 1)
            and any_walkable(cliff, 10, 10), "")
    suite.assert_test("GR8_a_cliff_splits_the_ground", #Grid.merge_rects(cliff, 0.45) == 2, "")
    local diagonal = fill(Grid.new(0, 0, 3, 3, 1), function(ix, iz) return iz == 3 and 10 or (ix == 3 and 20 or 0) end)
    Grid.mark_walkable(diagonal, 0.45)
    suite.assert_test("GR9_every_neighbour_counts",
        any_walkable(diagonal, 1, 1) and not any_walkable(diagonal, 2, 1) and not any_walkable(diagonal, 1, 2)
            and not any_walkable(diagonal, 3, 3), "")

    local holed = flat(5, 5, 1, 0)
    holed.floor[3][3] = {}
    Grid.mark_walkable(holed, 0.45)
    suite.assert_test("GR10_a_cell_with_no_floor_is_a_hole_and_harms_no_neighbour",
        not any_walkable(holed, 3, 3) and any_walkable(holed, 2, 3) and any_walkable(holed, 4, 3), "")
    local around = Grid.merge_rects(holed, 0.45)
    suite.assert_test("GR11_rectangles_tile_around_a_hole", tiles_exactly(holed, around) and area(holed, around) == 24,
        "area " .. area(holed, around))

    -- Two storeys, 4 m apart: the upper over the middle, with the ground running on past it.
    local two = fill(Grid.new(0, 0, 8, 3, 1), function() return 0 end)
    for iz = 1, 3 do
        for ix = 3, 6 do
            two.floor[iz][ix] = { 4, 0 }
        end
    end
    Grid.mark_walkable(two, 0.45)
    local carved = Grid.merge_rects(two, 0.45)
    local ground_rect, upper_rects = nil, 0
    for _, r in ipairs(carved) do
        if r.y == 0 and r.min_x == 0 and r.max_x == 8 then
            ground_rect = r
        end
        if r.y == 4 then
            upper_rects = upper_rects + 1
        end
    end
    suite.assert_test("GR12_each_storey_carves_apart", ground_rect ~= nil and ground_rect.max_z == 3, "rects " .. #carved)
    suite.assert_test("GR12b_a_floors_neighbour_on_another_floor_is_a_cliff_edge",
        not two.walkable[1][3][1] and not two.walkable[1][6][1], "")
    suite.assert_test("GR12c_the_floor_under_a_storey_is_level_with_the_ground_beside_it",
        two.walkable[1][3][2] == true and two.walkable[1][2][1] == true, "")
    suite.assert_test("GR12d_no_cell_of_the_upper_floor_goes_to_the_ground", upper_rects >= 1, "upper " .. upper_rects)
    -- The storey over the corner the scan starts in: the lower floor begins a rectangle too.
    local cornered = fill(Grid.new(0, 0, 6, 2, 1), function() return 0 end)
    for iz = 1, 2 do
        for ix = 1, 3 do
            cornered.floor[iz][ix] = { 4, 0 }
        end
    end
    Grid.mark_walkable(cornered, 0.45)
    local lower_rect = nil
    for _, r in ipairs(Grid.merge_rects(cornered, 0.45)) do
        if r.y == 0 then
            lower_rect = r
        end
    end
    suite.assert_test("GR12e_a_floor_under_another_can_start_a_rectangle",
        lower_rect ~= nil and lower_rect.min_x == 0 and lower_rect.max_x == 6, "")

    local plus = Grid.new(0, 0, 5, 5, 1)
    for iz = 1, 5 do
        for ix = 1, 5 do
            if ix == 3 or iz == 3 then
                plus.floor[iz][ix] = { 0 }
                plus.walkable[iz][ix] = { true }
            end
        end
    end
    local arms = Grid.merge_rects(plus, 0.45)
    suite.assert_test("GR13_a_plus_tiles_exactly", tiles_exactly(plus, arms) and area(plus, arms) == 9, "")

    local stairs = Grid.new(0, 0, 6, 6, 1)
    for iz = 1, 6 do
        for ix = 1, iz do
            stairs.floor[iz][ix] = { 0 }
            stairs.walkable[iz][ix] = { true }
        end
    end
    local steps = Grid.merge_rects(stairs, 0.45)
    suite.assert_test("GR14_a_staircase_tiles_exactly", tiles_exactly(stairs, steps) and area(stairs, steps) == 21, "")

    local empty = flat(4, 4, 1, false)
    Grid.mark_walkable(empty, 0.45)
    suite.assert_test("GR15_nothing_walkable_is_no_rectangles", #Grid.merge_rects(empty, 0.45) == 0, "")

    suite.finish("GridSuite")
end):in_set("zz/grid_suite")
