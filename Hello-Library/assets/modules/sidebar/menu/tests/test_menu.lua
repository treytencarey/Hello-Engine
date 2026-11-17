-- --host (windowed: UI layout and Interaction need a window)
-- The menu with a stand-in for the mods whose items it holds: the stand-in spawns two items into
-- each new list, linked to its own file, and observes its toggle's click as a real mod does.
--
--   M1 the local player's menu has its button in the bar, closed
--   M2 a click opens a panel in the container holding a list, and the stand-in's items in it in
--      `order`, each a button with its label
--   M3 a click on the toggle is the stand-in's, and its label follows `on`
--   M4 a reload of the menu keeps the panel open, with the stand-in's items once each
--   M5 a click on the button closes it, and opening it again gives fresh items
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Instances = require("modules/core/instances.lua")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("MenuSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/sidebar/menu/init.lua"
local original

local function finish()
    if original ~= nil then
        write_file_bytes(MOD_FILE, original)
    end
    suite.finish("MENU")
end

local camera, player

-- This client's world net, unconnected: what the client owns here is in its `core/net/owns`.
local own_net

app:add_systems(Startup, { Commands }, function(commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzmenu" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ Camera2d = {}, Camera = { order = 0 } }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        ["core/net/sync"] = false,
        input = {},
        ["input/mode"] = { mode = "input/game" },
        sidebar = {},
        ["sidebar/menu"] = {},
    }):id()
end)

-- The player becomes this client's once the net has declared ownership: an owner edge that comes
-- before the pair is declared finds no `core/net/owns` to join, and is spent.
local given = false
app:add_systems(Update, { Query[{ with = { "LuaRelationship" } }], Commands }, function(declared, commands)
    if given then return end
    for _, d in ipairs(declared:iter()) do
        if d:get("LuaRelationship").source == "core/net/owner" then given = true end
    end
    if not given then return end
    commands:entity(player):insert({ ["core/net/owner"] = own_net })
end)

-- The stand-in: what it spawns is linked to its file, as a mod's spawns are. Its toggle's state
-- lives outside the list, as a real mod keeps it on the player, so a new list shows it.
local STANDIN = "modules/zz_menu_items/init.lua"
Instances.mark_mod_script(STANDIN)
local alpha_on = false
local spawned = 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    for _, list in ipairs(world:query({ added = { "sidebar/menu/list" } })) do
        spawned = spawned + 1
        commands:spawn({
            ["sidebar/menu/item"] = { title = "Alpha", order = 2, on = alpha_on },
            ["zz/menu/alpha"] = {},
            ["core/script/owner"] = Instances.script_entity(STANDIN),
            ChildOf = list:id(),
        }):observe(On[Pointer[Click]], {
            Query[{ with = { "zz/menu/alpha", Mut["sidebar/menu/item"] } }],
        }, function(event, alphas)
            for _, a in ipairs(alphas:iter_many_mut({ event.entity })) do
                alpha_on = not alpha_on
                a:get_mut("sidebar/menu/item").on = alpha_on
            end
        end)
        commands:spawn({
            ["sidebar/menu/item"] = { title = "Beta", order = 1 },
            ["zz/menu/beta"] = {},
            ["core/script/owner"] = Instances.script_entity(STANDIN),
            ChildOf = list:id(),
        })
    end
end):in_set("zz/menu/standin")

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("sidebar/menu/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/menu/reload_watch")

local function button(world)
    return world:query({
        with = { "sidebar/menu/button" },
        optional = { "sidebar/button", "sidebar/button/open", "Button", "ChildOf" },
    })[1]
end

local function views(world)
    return world:query({ with = { "sidebar/menu/view" }, optional = { "sidebar/panel", "ChildOf" } })
end

local function lists(world)
    return world:query({ with = { "sidebar/menu/list" }, optional = { "Children", "ChildOf" } })
end

local function state_of(world)
    local me = world:query({ with = { "zz/player" }, optional = { "sidebar/menu/state" } })[1]
    return me:get("sidebar/menu/state") or {}
end

-- The list's items in its child order, each with its label.
local function listed(world)
    local out = {}
    local list = lists(world)[1]
    for _, child in ipairs(list and list:get("Children") or {}) do
        local item = world:query({
            iter_many = { child },
            with = { "sidebar/menu/item" },
            optional = { "Text", "Button", "Node", "ui/style", "zz/menu/alpha", "zz/menu/beta" },
        })[1]
        if item ~= nil then
            out[#out + 1] = item
        end
    end
    return out
end

local function labels(list)
    local out = {}
    for _, item in ipairs(list) do
        out[#out + 1] = tostring(item:get("Text"))
    end
    return table.concat(out, " | ")
end

local function styled(list)
    local all = #list > 0
    for _, item in ipairs(list) do
        all = all and item:has("Button") and item:has("Node") and item:has("ui/style") and item:has("Text")
    end
    return all
end

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

-- Frames as well as seconds: the frame the bar first appears can take over half a second (the UI's
-- first draw).
local phase, clock, frames = "built", 0, 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    if phase == "built" and button(world) ~= nil and button(world):has("Button") and clock > 0.5 and frames > 5 then
        local b = button(world)
        local data = b:get("sidebar/button")
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        T("M1_the_menu_s_button_is_in_the_bar", bar ~= nil and b:get("ChildOf") == bar:id() and data.title == "Menu"
            and data.order == 5 and data.icon == "icons/settings.png", tostring(data.title))
        T("M1_closed", not b:has("sidebar/button/open") and #views(world) == 0 and state_of(world).open == false)
        click(commands, b:id())
        step("opened")

    elseif phase == "opened" and #listed(world) == 2 and styled(listed(world)) and clock > 0.3 then
        local v = views(world)[1]
        local container = world:query({ with = { "sidebar/container" } })[1]
        local list = lists(world)[1]
        local scroll = world:query({ iter_many = world:descendants(v:id()), with = { "sidebar/panel/scroll" } })[1]
        T("M2_a_click_opens_a_panel_in_the_container_titled_menu", #views(world) == 1
            and v:get("ChildOf") == container:id() and v:get("sidebar/panel").title == "Menu"
            and state_of(world).open == true)
        T("M2_holding_one_list_in_its_scroll_area", #lists(world) == 1 and scroll ~= nil and list:get("ChildOf") == scroll:id())
        local items = listed(world)
        T("M2_the_stand_in_s_items_in_order_each_a_button_with_its_label",
            items[1]:has("zz/menu/beta") and items[2]:has("zz/menu/alpha") and labels(items) == "Beta | Alpha: Off",
            labels(items))
        mark.alpha = items[2]:id()
        click(commands, mark.alpha)
        step("toggled")

    elseif phase == "toggled" and clock > 0.3 then
        local items = listed(world)
        T("M3_a_click_on_the_toggle_is_its_mod_s_and_its_label_follows_on", alpha_on == true
            and labels(items) == "Beta | Alpha: On", labels(items))
        mark.button = button(world):id()
        mark.view = views(world)[1]:id()
        mark.spawned = spawned
        mark.reloads = reloads
        original = read_file_bytes(MOD_FILE)
        write_file_bytes(MOD_FILE, original .. "\n-- zz 1\n")
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 and #views(world) > 0 and #listed(world) > 0 and styled(listed(world)) then
        local b = button(world)
        local items = listed(world)
        T("M4_a_reload_keeps_the_panel_open_with_a_new_button_and_view", b ~= nil and b:id() ~= mark.button
            and b:has("sidebar/button/open") and #views(world) == 1 and views(world)[1]:id() ~= mark.view
            and state_of(world).open == true)
        T("M4_with_the_stand_in_s_items_once_each", #lists(world) == 1 and #items == 2 and spawned == mark.spawned + 1
            and labels(items) == "Beta | Alpha: On",
            string.format("lists %d items %d spawns %d: %s", #lists(world), #items, spawned - mark.spawned, labels(items)))
        click(commands, b:id())
        step("closed")

    elseif phase == "closed" and clock > 0.3 then
        T("M5_a_click_on_the_button_closes_it", #views(world) == 0 and #lists(world) == 0
            and #world:query({ with = { "sidebar/menu/item" } }) == 0 and state_of(world).open == false)
        mark.spawned = spawned
        click(commands, button(world):id())
        step("reopened")

    elseif phase == "reopened" and #listed(world) == 2 and styled(listed(world)) and clock > 0.3 then
        local items = listed(world)
        T("M5_opening_it_again_gives_fresh_items", #views(world) == 1 and spawned == mark.spawned + 1
            and labels(items) == "Beta | Alpha: On", labels(items))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 10 then
        T("M0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        finish()
    end
end):in_set("zz/menu/drive")
