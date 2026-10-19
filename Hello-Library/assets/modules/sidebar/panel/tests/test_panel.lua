-- --host (windowed: UI layout needs a window)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("SidebarPanelSuite")

spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
spawn({ Camera2d = {}, Camera = { order = 0 } })

local function panel(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/panel" },
        optional = { "sidebar/panel", "Node", "ui/style" },
    })) do
        if e:get("zz/panel").name == name then
            return e
        end
    end
end

local function part(world, e, marker)
    return world:query({
        entities = { e:id() },
        with = { marker },
        optional = { "Node", "Text", "ScrollPosition", "sidebar/panel/scroll", "ComputedNode" },
    })[1]
end

local function width(e)
    local w = (e:get("Node") or {}).width
    return w and w.Px
end

local phase, clock = "spawn", 0
local room

register_system("Update", function(world)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        spawn({ ["zz/panel"] = { name = "files" }, ["sidebar/panel"] = { scroll_speed = 25 } })
        spawn({ ["zz/panel"] = { name = "bare" }, ["sidebar/panel"] = { title = "", width = 48 } })
        step("built")

    elseif phase == "built" and clock > 0.5 then
        local files = panel(world, "files")
        local header = part(world, files, "sidebar/panel/header")
        local loading = part(world, files, "sidebar/panel/loading")
        suite.assert_test("L1_a_new_panel_is_loading_with_its_header_hidden",
            width(files) == 280 and header ~= nil and header:get("Node").display.None ~= nil
                and loading ~= nil and part(world, files, "sidebar/panel/scroll") ~= nil
                and files:get("ui/style").background == "bg",
            "width=" .. tostring(width(files)))
        local bare = panel(world, "bare")
        local bare_header = part(world, bare, "sidebar/panel/header")
        suite.assert_test("L2_an_empty_title_hides_the_header_and_is_not_loading",
            width(bare) == 48 and bare_header:get("Node").display.None ~= nil
                and bare:get("sidebar/panel").scroll_speed == 20
                and part(world, bare, "sidebar/panel/loading") == nil, "")
        files:patch({ ["sidebar/panel"] = { title = "Files", width = 320 } })
        step("titled")

    elseif phase == "titled" and clock > 0.3 then
        local files = panel(world, "files")
        local header = part(world, files, "sidebar/panel/header")
        local title = part(world, files, "sidebar/panel/title")
        suite.assert_test("L3_a_title_shows_the_header_and_ends_loading",
            header:get("Node").display.Flex ~= nil and title:get("Text") == "Files"
                and part(world, files, "sidebar/panel/loading") == nil, "")
        suite.assert_test("L4_width_follows_the_config", width(files) == 320, "width=" .. tostring(width(files)))
        local scroll = part(world, files, "sidebar/panel/scroll")
        for i = 1, 40 do
            spawn({ ["zz/row"] = {}, Node = { height = { Px = 30 }, flex_shrink = 0 } }):with_parent(scroll:id())
        end
        step("filled")

    elseif phase == "filled" and clock > 0.5 then
        local scroll = part(world, panel(world, "files"), "sidebar/panel/scroll")
        local node = scroll:get("ComputedNode")
        room = node.content_size.y - node.size.y
        scroll:invoke_observer("Pointer<Scroll>", { event = { y = 3 } })
        step("at top")

    elseif phase == "at top" and clock > 0.3 then
        local scroll = part(world, panel(world, "files"), "sidebar/panel/scroll")
        suite.assert_test("L5a_scrolling_up_at_the_top_stays_at_the_top",
            scroll:get("sidebar/panel/scroll").offset == 0, "offset=" .. tostring(scroll:get("sidebar/panel/scroll").offset))
        scroll:invoke_observer("Pointer<Scroll>", { event = { y = -3 } })
        step("scrolled")

    elseif phase == "scrolled" and clock > 0.3 then
        local scroll = part(world, panel(world, "files"), "sidebar/panel/scroll")
        local s = scroll:get("sidebar/panel/scroll")
        suite.assert_test("L5_wheel_steps_scroll_by_speed",
            room > 100 and s.offset == 75 and scroll:get("ScrollPosition").y == 75,
            string.format("room=%.0f offset=%s", room, tostring(s.offset)))
        scroll:invoke_observer("Pointer<Scroll>", { event = { y = -1000 } })
        step("scrolled far")

    elseif phase == "scrolled far" and clock > 0.3 then
        local scroll = part(world, panel(world, "files"), "sidebar/panel/scroll")
        local s = scroll:get("sidebar/panel/scroll")
        suite.assert_test("L6_scrolling_stops_at_the_end_of_the_content", math.abs(s.offset - room) < 1,
            string.format("room=%.0f offset=%s", room, tostring(s.offset)))
        for _, row in ipairs(world:query({ with = { "zz/row" } })) do
            despawn(row:id())
        end
        step("emptied")

    elseif phase == "emptied" and clock > 0.5 then
        part(world, panel(world, "files"), "sidebar/panel/scroll"):invoke_observer("Pointer<Scroll>", { event = { y = -1 } })
        step("stepped")

    elseif phase == "stepped" and clock > 0.3 then
        local scroll = part(world, panel(world, "files"), "sidebar/panel/scroll")
        local s = scroll:get("sidebar/panel/scroll")
        suite.assert_test("L7_after_content_shrinks_the_next_step_stays_within_it", s.offset == 0, "offset=" .. tostring(s.offset))
        panel(world, "files"):remove("sidebar/panel")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local files = panel(world, "files")
        suite.assert_test("L8_removing_the_panel_takes_off_what_the_base_added",
            files ~= nil and part(world, files, "sidebar/panel/header") == nil
                and part(world, files, "sidebar/panel/scroll") == nil
                and files:get("Node") == nil and files:get("ui/style") == nil, "")
        phase = "done"
        suite.finish("SidebarPanelSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("L0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("SidebarPanelSuite")
    end
end, { label = "SidebarPanelSuite" })
