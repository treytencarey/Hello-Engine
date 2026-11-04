-- --host (windowed: UI layout, Interaction and the propagation of a Pointer event need a window)
-- What test_file_browser_net.lua cannot see headless: the rows have a size and indent by depth, the
-- content overflows the scroll area, a click on a row's text reaches the row and the wheel over it
-- reaches the scroll area, as a real pointer's do, a row can be hovered, and a reload leaves the
-- panel laid out. A system here answers each ask with made-up entries, in the server's place.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Scroll = require("bevy::picking::prelude::Scroll")

local suite = helpers.create_suite("FileBrowserWindowedSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/sidebar/file_browser/client/init.lua"
local original = read_file_bytes(MOD_FILE)

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ Camera2d = {}, Camera = { order = 0 } }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1, spawn_index = 1 },
        ["core/net/local"] = {},
        ["sidebar/file_browser"] = {},
        ["core/net/sync"] = {
            ["sidebar/file_browser/request"] = { authority = "client", target = "owner" },
            ["sidebar/file_browser/answer"] = { authority = "server", target = "owner" },
        },
    }):id()
end)

-- The server's part, by the mod's own request: a folder at the top, and many files in it.
app:add_systems(Update, {
    Query[{
        changed = { "sidebar/file_browser/request" },
        optional = { "sidebar/file_browser/answer" },
    }],
    Commands,
}, function(asking, commands)
    for _, e in ipairs(asking:iter()) do
        local answers = {}
        for key, asked in pairs(e:get("sidebar/file_browser/request")) do
            local files = {}
            if asked.path == "" then
                files[1] = { name = "folder", path = "folder", is_directory = true, size = 0 }
                files[2] = { name = "a file with a rather long name to see how it lays out.txt", path = "long.txt", is_directory = false, size = 2048 }
            elseif asked.path == "folder" then
                for i = 1, 40 do
                    files[i] = { name = "f" .. i, path = "folder/f" .. i, is_directory = false, size = i }
                end
            end
            answers[key] = { op = "list", path = asked.path, offset = asked.offset, files = files, has_more = false, total_count = #files }
        end
        commands:entity(e:id()):insert({ ["sidebar/file_browser/answer"] = answers })
    end
end):in_set("zz/fb_windowed_server")

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

local function slot(world, path)
    for _, row in ipairs(world:query({ with = { "sidebar/file_browser/row" }, optional = { "ComputedNode", "Interaction", "Node", "BackgroundColor" } })) do
        if row:get("sidebar/file_browser/row").path == path then return row end
    end
end

local function name_in(world, row)
    return world:query({
        iter_many = world:descendants(row:id()),
        with = { "sidebar/file_browser/name" },
        optional = { "ComputedNode" },
    })[1]
end

local function scroll(world)
    return world:query({ with = { "sidebar/panel/scroll", "ScrollPosition" }, optional = { "ComputedNode" } })[1]
end

local phase, clock, reloads = "opening", 0, 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "opening" and clock > 0.3 then
        commands:entity(player):patch({ ["sidebar/open"] = {} })
        local button = world:query({ with = { "sidebar/file_browser/button" } })[1]
        if button ~= nil then
            click(commands, button:id())
            step("opened")
        end

    elseif phase == "opened" and slot(world, "folder") ~= nil and clock > 0.3 then
        local row = slot(world, "folder")
        local size = row:get("ComputedNode").size
        T("L1_a_row_has_a_size", size.x > 0 and size.y > 0, size.x .. " " .. size.y)
        local long = name_in(world, slot(world, "long.txt"))
        local panel = world:query({ with = { "sidebar/file_browser/view" }, optional = { "ComputedNode" } })[1]
        T("L2_a_long_name_stays_inside_the_panel", long:get("ComputedNode").size.x <= panel:get("ComputedNode").size.x,
            long:get("ComputedNode").size.x .. " " .. panel:get("ComputedNode").size.x)
        click(commands, name_in(world, row):id())
        step("expanded")

    elseif phase == "expanded" and slot(world, "folder/f40") ~= nil and clock > 0.3 then
        T("C1_a_click_on_a_rows_text_reaches_the_row", true)
        T("L3_a_row_in_a_folder_is_indented", slot(world, "folder/f1"):get("Node").padding.left.Px > slot(world, "folder"):get("Node").padding.left.Px)
        local area = scroll(world):get("ComputedNode")
        T("L4_the_content_overflows_the_scroll_area", area.content_size.y > area.size.y, area.content_size.y .. " " .. area.size.y)
        wheel(commands, name_in(world, slot(world, "folder/f1")):id(), -3)
        step("wheeled")

    elseif phase == "wheeled" and clock > 0.3 then
        T("C2_the_wheel_over_a_row_reaches_the_scroll_area", scroll(world):get("ScrollPosition").y > 0, tostring(scroll(world):get("ScrollPosition").y))
        T("C3_a_row_can_be_hovered", slot(world, "folder"):has("Interaction"))
        mark.button = world:query({ with = { "sidebar/file_browser/button" } })[1]:id()
        write_file_bytes(MOD_FILE, original .. "\n-- zz 1\n")
        step("reloaded")

    elseif phase == "reloaded" and clock > 2.5 and slot(world, "folder/f40") ~= nil then
        local size = slot(world, "folder/f40"):get("ComputedNode").size
        T("H1_after_a_reload_the_panel_is_laid_out_with_its_folder_expanded", size.x > 0 and size.y > 0, size.x .. " " .. size.y)
        T("H1_one_button", #world:query({ with = { "sidebar/file_browser/button" } }) == 1
            and world:query({ with = { "sidebar/file_browser/button" } })[1]:id() ~= mark.button)
        write_file_bytes(MOD_FILE, original)
        phase = "done"
        suite.finish("FILE_BROWSER_WINDOWED")
    end

    if phase ~= "done" and clock > 20 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        write_file_bytes(MOD_FILE, original)
        phase = "done"
        suite.finish("FILE_BROWSER_WINDOWED")
    end
end):in_set("zz/fb_windowed"):after("sidebar/file_browser/render")
