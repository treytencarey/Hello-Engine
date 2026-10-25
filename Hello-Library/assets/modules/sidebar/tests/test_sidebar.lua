-- --host (windowed: UI layout and Interaction need a window)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("SidebarSuite")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

local camera

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    camera = commands:spawn({ Camera2d = {}, Camera = { order = 0 } }):id()
end)

-- What a script spawns is linked to its file. The panel stand-in below spawns its buttons
-- as a panel mod would, linked to that mod's file.
local Instances = require("modules/core/instances.lua")
local PANEL = "modules/zz_panel/init.lua"
Instances.mark_mod_script(PANEL)

-- The reload (R14) rewrites the sidebar's own file with the same bytes: an immediate watcher.
local SOURCE = "assets/modules/sidebar/init.lua"
local fw = define_resource("_FileWatcherState", {})
fw.poll_interval = 0
fw.debounce = 0

-- The panel stand-in: when a bar appears, a local player with `zz/panel` gets its two
-- buttons in it.
app:add_systems(Update, { World, Commands }, function(world, commands)
    for _, bar in ipairs(world:query({ added = { "sidebar/bar" } })) do
        for _, _ in ipairs(world:query({ with = { "zz/panel", "core/net/local" }, limit = 1 })) do
            commands:entity(bar:id())
                :add_child(commands:spawn({ ["sidebar/button"] = { title = "Alpha", order = 2 }, ["core/script/owner"] = Instances.script_entity(PANEL) }):id())
                :add_child(commands:spawn({ ["sidebar/button"] = { title = "Beta", order = 1 }, ["core/script/owner"] = Instances.script_entity(PANEL) }):id())
        end
    end
end):in_set("zz/sidebar_suite_panel")

-- Keys go through `input` as the real ones do: pressed one frame, released two frames later.
local key_frames = {}

app:add_systems(First, { World }, function(world)
    local ev = table.remove(key_frames, 1)
    if ev ~= nil and ev.key_code ~= nil then world:write_event("SyntheticKeyInput", ev) end
end):in_set("zz/sidebar_suite_keys")

local function escape()
    key_frames[#key_frames + 1] = { key_code = "Escape", state = "Pressed" }
    key_frames[#key_frames + 1] = {}
    key_frames[#key_frames + 1] = { key_code = "Escape", state = "Released" }
end

local function player(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/player" },
        optional = { "sidebar/open", "input" },
    })) do
        if e:get("zz/player").name == name then
            return e
        end
    end
end

local function button(world, title)
    for _, b in ipairs(world:query({
        with = { "sidebar/button" },
        optional = { "sidebar/button/open", "ui/style", "Button" },
    })) do
        if b:get("sidebar/button").title == title then
            return b
        end
    end
end

local function container(world)
    return world:query({ with = { "sidebar/container" }, optional = { "Node" } })[1]
end

local function bar(world)
    return world:query({ with = { "sidebar/bar" }, optional = { "Children" } })[1]
end

-- The bar's icons, in its child order.
local function icons(world)
    local out = {}
    local b = bar(world)
    for _, child in ipairs(b and b:get("Children") or {}) do
        local e = world:get_entity(child)
        if e and e:has("sidebar/button") then out[#out + 1] = e end
    end
    return out
end

local function letters(world, b)
    return world:query({ entities = { b:id() }, with = { "Text" } })
end

-- A click on an icon, as Bevy's picking triggers it: a Pointer<Click> on the entity it lands on.
local function click(world, commands, title)
    local b = button(world, title)
    commands:trigger(Pointer[Click], {
        entity = b:id(),
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function shown(c) return c:get("Node").display.Flex ~= nil end

-- Frames as well as seconds: the frame the bar first appears can take over half a second
-- (the UI's first draw), and the panel's buttons are styled two frames after it.
local phase, clock, frames = "spawn", 0, 0
local old_bar

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end
    local me = player(world, "me")

    if phase == "spawn" then
        commands:spawn({
            ["zz/player"] = { name = "me" },
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            input = { mode = "input/game" },
            sidebar = {},
            ["zz/panel"] = {},
        })
        commands:spawn({
            ["zz/player"] = { name = "remote" },
            ["core/net/sync"] = false,
            sidebar = {},
        })
        step("built")

    elseif phase == "built" and me and container(world) and clock > 0.5 and frames > 5 then
        local list = icons(world)
        local beta = button(world, "Beta")
        suite.assert_test("R1_the_local_player_gets_a_hidden_sidebar_with_its_panels_buttons_as_icons_in_order",
            not shown(container(world)) and #list == 2
                and list[1]:id() == beta:id() and list[2]:id() == button(world, "Alpha"):id()
                and beta:has("Button") and #letters(world, beta) == 1,
            "icons=" .. #list)
        suite.assert_test("R2_a_remote_player_gets_no_sidebar",
            #world:query({ with = { "sidebar/container" } }) == 1, "")
        escape()
        step("opened")

    elseif phase == "opened" and clock > 0.4 then
        suite.assert_test("R3_escape_opens_the_sidebar_and_switches_to_ui_input",
            me:has("sidebar/open") and shown(container(world))
                and me:get("input").mode == "input/ui" and me:get("input").show_cursor == true,
            "mode=" .. tostring(me:get("input").mode))
        click(world, commands, "Alpha")
        step("alpha")

    elseif phase == "alpha" and clock > 0.3 then
        local alpha = button(world, "Alpha")
        suite.assert_test("R4_clicking_an_icon_opens_its_panel_and_marks_the_icon",
            alpha:has("sidebar/button/open") and alpha:get("ui/style").background == "icon_active", "")
        click(world, commands, "Beta")
        step("beta")

    elseif phase == "beta" and clock > 0.3 then
        escape()
        step("closed newest")

    elseif phase == "closed newest" and clock > 0.4 then
        suite.assert_test("R5_escape_closes_the_newest_panel_first",
            not button(world, "Beta"):has("sidebar/button/open")
                and button(world, "Alpha"):has("sidebar/button/open") and me:has("sidebar/open"), "")
        click(world, commands, "Alpha")
        step("clicked closed")

    elseif phase == "clicked closed" and clock > 0.3 then
        local alpha = button(world, "Alpha")
        suite.assert_test("R6_clicking_an_open_icon_closes_its_panel",
            not alpha:has("sidebar/button/open") and alpha:get("ui/style").background == "icon_bg", "")
        click(world, commands, "Beta")
        step("reorder 1")

    -- Beta, then Alpha, then Beta closed and opened again: Beta is the newest. (Beta is the
    -- second row a query returns, so a tie in order would pick Alpha.)
    elseif phase == "reorder 1" and clock > 0.3 then
        click(world, commands, "Alpha")
        step("reorder 2")

    elseif phase == "reorder 2" and clock > 0.3 then
        click(world, commands, "Beta")
        step("reorder 3")

    elseif phase == "reorder 3" and clock > 0.3 then
        click(world, commands, "Beta")
        step("reorder 4")

    elseif phase == "reorder 4" and clock > 0.3 then
        escape()
        step("reorder escaped")

    elseif phase == "reorder escaped" and clock > 0.4 then
        suite.assert_test("R5b_a_panel_opened_again_is_the_newest",
            not button(world, "Beta"):has("sidebar/button/open") and button(world, "Alpha"):has("sidebar/button/open"), "")
        step("beta again")

    elseif phase == "beta again" and clock > 0.3 then
        escape()
        step("one more")

    elseif phase == "one more" and clock > 0.4 then
        escape()
        step("sidebar closed")

    elseif phase == "sidebar closed" and clock > 0.4 then
        suite.assert_test("R7_escape_with_no_panel_open_closes_the_sidebar",
            not me:has("sidebar/open") and not shown(container(world))
                and me:get("input").mode == "input/game", "mode=" .. tostring(me:get("input").mode))
        escape()
        step("reopened")

    elseif phase == "reopened" and clock > 0.4 then
        click(world, commands, "Beta")
        step("closing with a panel open")

    elseif phase == "closing with a panel open" and clock > 0.3 then
        me:patch({ ["sidebar/open"] = null })
        step("closed with panel")

    elseif phase == "closed with panel" and clock > 0.3 then
        suite.assert_test("R8_closing_the_sidebar_closes_its_panels",
            not button(world, "Beta"):has("sidebar/button/open"), "")
        commands:entity(button(world, "Alpha"):id()):despawn()
        step("button gone")

    elseif phase == "button gone" and clock > 0.3 then
        local list = icons(world)
        suite.assert_test("R9_a_removed_button_leaves_the_bar",
            #list == 1 and list[1]:id() == button(world, "Beta"):id(), "icons=" .. #list)
        commands:entity(bar(world):id())
            :add_child(commands:spawn({ ["sidebar/button"] = { title = "Gamma", order = 0 }, ["core/script/owner"] = Instances.script_entity(PANEL) }):id())
        step("gamma")

    elseif phase == "gamma" and clock > 0.3 then
        local list = icons(world)
        suite.assert_test("R9b_a_later_button_joins_in_order_and_the_others_keep_one_letter",
            #list == 2 and list[1]:id() == button(world, "Gamma"):id() and list[2]:id() == button(world, "Beta"):id()
                and #letters(world, button(world, "Beta")) == 1 and #letters(world, button(world, "Gamma")) == 1,
            "icons=" .. #list)
        commands:entity(button(world, "Gamma"):id()):despawn()
        escape()
        step("open before leaving")

    elseif phase == "open before leaving" and clock > 0.4 then
        me:patch({ ["core/net/local"] = null })
        step("left")

    elseif phase == "left" and clock > 0.3 then
        suite.assert_test("R11_leaving_the_world_closes_the_sidebar",
            not me:has("sidebar/open") and not shown(container(world)), "")
        me:patch({ ["core/net/local"] = {} })
        step("returned")

    elseif phase == "returned" and clock > 0.3 then
        suite.assert_test("R16_coming_back_keeps_the_one_sidebar",
            #world:query({ with = { "sidebar/container" } }) == 1 and #world:query({ with = { "sidebar/bar" } }) == 1
                and #icons(world) == 1, "")
        me:remove("sidebar")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        suite.assert_test("R10_removing_sidebar_removes_its_container_with_the_buttons_in_it",
            container(world) == nil and #world:query({ with = { "sidebar/button" } }) == 0, "")
        me:patch({ sidebar = {} })
        step("re-added")

    elseif phase == "re-added" and clock > 0.5 then
        local list = icons(world)
        suite.assert_test("R13_a_new_sidebar_gets_new_buttons_from_its_panels",
            #list == 2 and list[1]:id() == button(world, "Beta"):id() and list[2]:id() == button(world, "Alpha"):id(),
            "icons=" .. #list)
        escape()
        step("open for reload")

    elseif phase == "open for reload" and clock > 0.4 then
        click(world, commands, "Beta")
        step("beta open for reload")

    elseif phase == "beta open for reload" and clock > 0.3 then
        old_bar = bar(world):id()
        write_file_bytes(SOURCE, read_file_bytes(SOURCE))
        step("reloading")

    elseif phase == "reloading" and bar(world) and bar(world):id() ~= old_bar and clock > 0.5 then
        local list = icons(world)
        suite.assert_test("R14_a_sidebar_reload_rebuilds_it_open_with_new_buttons",
            #list == 2 and shown(container(world)) and #world:query({ with = { "sidebar/container" } }) == 1
                and #world:query({ with = { "sidebar/button" } }) == 2
                and #world:query({ with = { "sidebar/button", "sidebar/button/open" } }) == 0,
            string.format("icons=%d buttons=%d", #list, #world:query({ with = { "sidebar/button" } })))
        Instances.reap_module_entities(world, PANEL)
        step("panel gone")

    elseif phase == "panel gone" and clock > 0.3 then
        suite.assert_test("R15_a_panels_reload_takes_its_buttons_with_their_letters",
            #world:query({ with = { "sidebar/button" } }) == 0 and #icons(world) == 0
                and #world:query({ entities = { bar(world):id() }, with = { "Text" } }) == 0, "")
        player(world, "me"):remove("input")
        step("no input")

    -- `input` taken off and added again: the bindings go with it and come back.
    elseif phase == "no input" and clock > 0.3 then
        local who = player(world, "me")
        suite.assert_test("R17a_removing_input_takes_the_bindings", (world:get_entity(who:id()):get("input/game") or {}).sidebar == nil, "")
        who:patch({ input = { mode = "input/game" } })
        step("input back")

    elseif phase == "input back" and clock > 0.3 then
        local who = player(world, "me")
        suite.assert_test("R17b_input_added_again_binds_again", (world:get_entity(who:id()):get("input/game") or {}).sidebar ~= nil, "")
        phase = "done"
        suite.finish("SidebarSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("R0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("SidebarSuite")
    end
end):in_set("zz/sidebar_suite")
