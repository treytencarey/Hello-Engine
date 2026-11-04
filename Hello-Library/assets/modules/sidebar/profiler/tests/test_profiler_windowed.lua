-- --host (windowed: UI layout, Interaction and the propagation of a Pointer event need a window)
-- What test_profiler.lua cannot see headless: the rows have a size and the content overflows the
-- scroll area, a click on a row's text reaches the row and the wheel over it reaches the scroll
-- area, as a real pointer's do, a row can be hovered, and a reload leaves the panel laid out.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Scroll = require("bevy::picking::prelude::Scroll")

local suite = helpers.create_suite("ProfilerWindowedSuite")
local T = suite.assert_test

-- The reload rewrites the mod's own file with the same bytes: an immediate watcher.
local MOD_FILE = "assets/modules/sidebar/profiler/init.lua"
local fw = define_resource("_FileWatcherState", {})
fw.poll_interval = 0
fw.debounce = 0

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    commands:spawn({ ["zz/work"] = {} })
    camera = commands:spawn({ Camera2d = {}, Camera = { order = 0 } }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1, spawn_index = 1 },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
    }):id()
end)

app:add_systems(Update, { Query[{ with = { "zz/work" } }] }, function(rows)
    rows:iter()
    for _ = 1, 40000 do local _ = math.sqrt(2) end
end):in_set("zz/profiler_windowed/own")

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function wheel(commands, entity, y)
    commands:trigger(Pointer[Scroll], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { unit = "Line", y = y, hit = { camera = camera } },
    })
end

local function own_row(world)
    for _, row in ipairs(world:query({ with = { "sidebar/profiler/row" }, optional = { "ComputedNode", "Interaction", "ui/style" } })) do
        if row:get("sidebar/profiler/row").name == "zz/profiler_windowed/own" then return row end
    end
end

local function own_text(world, row)
    return world:query({ iter_many = world:descendants(row:id()), with = { "sidebar/profiler/name" } })[1]
end

local function scroll_area(world)
    local view = world:query({ with = { "sidebar/profiler/view" } })[1]
    return world:query({
        iter_many = world:descendants(view:id()),
        with = { "sidebar/panel/scroll" },
        optional = { "ComputedNode" },
    })[1]
end

local phase, clock = "button", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local button = world:query({ with = { "sidebar/profiler/button" } })[1]

    if phase == "button" and button ~= nil and clock > 0.5 then
        commands:entity(player):patch({ ["sidebar/open"] = {} })
        click(commands, button:id())
        step("rows")

    elseif phase == "rows" and own_row(world) ~= nil and clock > 2.5 then
        local all = world:query({ with = { "sidebar/profiler/row" }, optional = { "ComputedNode" } })
        local sized, total = 0, 0
        for _, row in ipairs(all) do
            local node = row:get("ComputedNode")
            if node and node.size.y > 0 and node.size.x > 0 then
                sized = sized + 1
                total = total + node.size.y
            end
        end
        T("W1_every_row_has_a_size", #all > 0 and sized == #all, sized .. " of " .. #all)
        local node = scroll_area(world):get("ComputedNode")
        T("W2_the_rows_fill_the_scroll_area_s_content", node.content_size.y >= total, node.content_size.y .. " against " .. total)
        click(commands, own_text(world, own_row(world)):id())
        step("expanded")

    elseif phase == "expanded" and clock > 0.4 then
        local me = world:query({ with = { "zz/player", "sidebar/profiler/state" } })[1]
        local state = me:get("sidebar/profiler/state")
        T("W3_a_click_on_a_row_s_text_reaches_the_row", state.expanded == "zz/profiler_windowed/own", tostring(state.expanded))
        local inside = world:descendants(own_row(world):id())
        local query_row = world:query({ iter_many = inside, with = { "sidebar/profiler/query", "ComputedNode" } })[1]
        T("W3_and_its_query_row_shows_with_a_size", query_row ~= nil and query_row:get("ComputedNode").size.y > 0)
        wheel(commands, own_text(world, own_row(world)):id(), -2)
        step("scrolled")

    elseif phase == "scrolled" and clock > 0.3 then
        local area = scroll_area(world)
        T("W4_the_wheel_over_a_row_scrolls_the_panel", area:get("sidebar/panel/scroll").offset > 0, tostring(area:get("sidebar/panel/scroll").offset))
        click(commands, own_row(world):id())
        step("hover")

    -- A suite has no pointer, and Bevy rewrites a patched `Interaction` next frame, so this checks what
    -- `ui/style` reads when a real pointer hovers. Its own suite proves the colour.
    elseif phase == "hover" and clock > 0.3 then
        local row = own_row(world)
        local style = row:get("ui/style")
        T("W5_a_row_can_be_hovered_and_names_its_hover_colour", row:has("Interaction") and style.hover == "row_hover",
            tostring(style.hover))
        write_file_bytes(MOD_FILE, read_file_bytes(MOD_FILE))
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local row = own_row(world)
        local node = row and row:get("ComputedNode")
        T("W6_a_reload_keeps_the_panel_open_and_laid_out", #world:query({ with = { "sidebar/profiler/view" } }) == 1
            and node ~= nil and node.size.y > 0 and #world:query({ with = { "sidebar/profiler/button", "sidebar/button/open" } }) == 1)
        phase = "done"
        suite.finish("PROFILER_WINDOWED")
    end

    if phase ~= "done" and clock > 15 then
        T("W0_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        suite.finish("PROFILER_WINDOWED")
    end
end):in_set("zz/profiler_windowed/suite")
