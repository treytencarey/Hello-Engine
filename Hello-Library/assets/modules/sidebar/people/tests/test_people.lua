-- The people panel, driven headless with real clicks, with stand-in players replicated here and a
-- stand-in contributor: on each new row it adds a text and two buttons, out of order, linked to its
-- own file, and observes its first button's click as a real mod does.
--
-- P1  the local player's panel has its button in the bar, closed
-- R1  opened, the panel holds a row per player, each showing who the player is
-- L1  each row's `sidebar/people/row/player` names its player, and the player's target list names
--     the row
-- I1  the contributor's items are on each row, after the name, in `order`: a text, and buttons
--     with `Button`, `Node` and a hover and press style; a disabled one is dimmed
-- C1  a click on a button item reaches the contributor's own observer
-- A1  a player arriving gets a row, with the contributor's items
-- N1  a row's name follows its player's `user_id`
-- G1  a player leaving takes its row and its items
-- H1  a reload of the mod keeps the panel open and rebuilds the rows, and the contributor adds its
--     items again on the rebuilt rows, once each
-- X1  closing the panel takes the rows and their items
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Instances = require("modules/core/instances.lua")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("PeopleSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/sidebar/people/init.lua"
local original

local function finish()
    if original ~= nil then
        write_file_bytes(MOD_FILE, original)
    end
    suite.finish("PEOPLE")
end

local camera, me, alice, bob, carol

-- This client's world net, unconnected: what the client owns here is in its `core/net/owns`.
local own_net

app:add_systems(Startup, { Commands }, function(commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzpeople" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    me = commands:spawn({
        ["zz/player"] = {},
        ["core/net/sync"] = false,
        input = {},
        ["input/mode"] = { mode = "input/game" },
        sidebar = {},
        ["sidebar/people"] = {},
    }):id()
    alice = commands:spawn({
        ["zz/remote"] = {},
        player = { client_id = 2, user_id = "zz-alice" },
        ["core/net/sync"] = false,
    }):id()
    bob = commands:spawn({
        ["zz/remote"] = {},
        player = { client_id = 3, user_id = "" },
        ["core/net/sync"] = false,
    }):id()
end)

-- The carrier becomes this client's once the net has declared ownership: an owner edge that comes
-- before the pair is declared finds no `core/net/owns` to join, and is spent.
local given = false
app:add_systems(Update, { Query[{ with = { "LuaRelationship" } }], Commands }, function(declared, commands)
    if given then return end
    for _, d in ipairs(declared:iter()) do
        if d:get("LuaRelationship").source == "core/net/owner" then given = true end
    end
    if not given then return end
    commands:entity(me):insert({ ["core/net/owner"] = own_net })
end)

-- The stand-in contributor: what it spawns is linked to its file, as a mod's spawns are. It finds
-- the row's player through the row's link, and names its text after that player's client.
local STANDIN = "modules/zz_people_items/init.lua"
Instances.mark_mod_script(STANDIN)
local spawned = 0
local clicks = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    for _, row in ipairs(world:query({ added = { "sidebar/people/row" }, with = { "sidebar/people/row/player" } })) do
        local link = row:get("sidebar/people/row/player")
        local player = world:query({ iter_many = { link.entity }, with = { "player" } })[1]
        local client = player and player:get("player").client_id or "?"
        spawned = spawned + 1
        commands:spawn({
            ["sidebar/people/row/item"] = { order = 2, label = "Wave", button = true },
            ["zz/people/wave"] = {},
            ["core/script/owner"] = Instances.script_entity(STANDIN),
            ChildOf = row:id(),
        }):observe(On[Pointer[Click]], {
            Query[{ with = { "zz/people/wave" } }],
        }, function(event, waves)
            for _, w in ipairs(waves:iter_many({ event.entity })) do
                clicks[#clicks + 1] = w:id()
            end
        end)
        commands:spawn({
            ["sidebar/people/row/item"] = { order = 1, label = "dot-" .. tostring(client) },
            ["zz/people/dot"] = {},
            ["core/script/owner"] = Instances.script_entity(STANDIN),
            ChildOf = row:id(),
        })
        commands:spawn({
            ["sidebar/people/row/item"] = { order = 3, label = "Kick", button = true, enabled = false },
            ["zz/people/kick"] = {},
            ["core/script/owner"] = Instances.script_entity(STANDIN),
            ChildOf = row:id(),
        })
    end
end):in_set("zz/people/standin")

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("sidebar/people/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/people/reload_watch")

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function button(world)
    return world:query({
        with = { "sidebar/people/button" },
        optional = { "sidebar/button", "sidebar/button/open", "Node", "ChildOf" },
    })[1]
end

local function views(world)
    return world:query({ with = { "sidebar/people/view" }, optional = { "sidebar/panel", "ChildOf" } })
end

local function rows(world)
    return world:query({ with = { "sidebar/people/row" }, optional = { "sidebar/people/row/player", "Children" } })
end

local function state_of(world)
    local carrier = world:query({ with = { "zz/player" }, optional = { "sidebar/people/state" } })[1]
    return carrier:get("sidebar/people/state") or {}
end

local function row_of(world, player)
    for _, r in ipairs(rows(world)) do
        local link = r:get("sidebar/people/row/player")
        if link ~= nil and link.entity == player then return r end
    end
end

-- A row's children in their order, each as { id, text, item, button, style }.
local function children_of(world, row)
    local out = {}
    for _, child in ipairs(row and row:get("Children") or {}) do
        local c = world:query({
            iter_many = { child },
            optional = { "Text", "Button", "Node", "ui/style", "sidebar/people/row/item" },
        })[1]
        if c ~= nil then
            out[#out + 1] = {
                id = c:id(),
                text = c:get("Text"),
                item = c:has("sidebar/people/row/item"),
                button = c:has("Button") and c:has("Node"),
                style = c:get("ui/style") or {},
            }
        end
    end
    return out
end

local function texts(list)
    local out = {}
    for _, c in ipairs(list) do out[#out + 1] = tostring(c.text) end
    return table.concat(out, " | ")
end

-- The row for `player` holds its name and then the contributor's three items, in `order`, drawn.
local function laid_out(world, player, name, client)
    local list = children_of(world, row_of(world, player))
    return #list == 4 and texts(list) == name .. " | dot-" .. client .. " | Wave | Kick"
        and not list[1].item and list[2].item and not list[2].button
        and list[3].button and list[3].style.hover == "icon_hover" and list[3].style.press == "icon_active"
        and list[4].button and list[4].style.text == "text_dim" and list[4].style.hover == nil,
        texts(list)
end

local function items_count(world)
    return #world:query({ with = { "sidebar/people/row/item" } })
end

local function targets(world, player)
    local p = world:query({ iter_many = { player }, optional = { "sidebar/people/row/players" } })[1]
    return p and p:get("sidebar/people/row/players") or {}
end

local phase, clock, frames = "built", 0, 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    if phase == "built" and button(world) ~= nil and button(world):has("Node") and clock > 0.3 and frames > 5 then
        local b = button(world)
        local data = b:get("sidebar/button")
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        T("P1_the_panel_s_button_is_in_the_bar", bar ~= nil and b:get("ChildOf") == bar:id() and data.title == "People"
            and data.order == 6 and data.icon == "icons/friends.png", tostring(data.title))
        T("P1_closed", not b:has("sidebar/button/open") and #views(world) == 0 and state_of(world).open == false)
        commands:entity(me):insert({ ["sidebar/open"] = {} })
        click(commands, b:id())
        step("opened")

    elseif phase == "opened" and #rows(world) == 2 and items_count(world) == 6 and clock > 0.3 then
        local v = views(world)[1]
        local container = world:query({ with = { "sidebar/container" } })[1]
        T("R1_a_click_opens_a_panel_in_the_container_titled_people", #views(world) == 1
            and v:get("ChildOf") == container:id() and v:get("sidebar/panel").title == "People"
            and state_of(world).open == true)
        local a, b = row_of(world, alice), row_of(world, bob)
        T("R1_a_row_per_player_showing_who_it_is", a ~= nil and b ~= nil
            and children_of(world, a)[1].text == "zz-alice" and children_of(world, b)[1].text == "Player 3",
            texts(children_of(world, a)) .. " / " .. texts(children_of(world, b)))
        local ta, tb = targets(world, alice), targets(world, bob)
        T("L1_each_row_names_its_player_and_the_player_its_row", a ~= nil and b ~= nil
            and #ta == 1 and ta[1] == a:id() and #tb == 1 and tb[1] == b:id(),
            string.format("alice %d bob %d", #ta, #tb))
        local ok_a, why_a = laid_out(world, alice, "zz-alice", 2)
        local ok_b, why_b = laid_out(world, bob, "Player 3", 3)
        T("I1_items_after_the_name_in_order_as_buttons_or_text", ok_a and ok_b, why_a .. " / " .. why_b)
        mark.wave = children_of(world, a)[3].id
        click(commands, mark.wave)
        step("clicked")

    elseif phase == "clicked" and clock > 0.3 then
        T("C1_a_click_on_a_button_item_reaches_its_owner_s_observer", #clicks == 1 and clicks[1] == mark.wave,
            tostring(#clicks))
        carol = commands:spawn({
            ["zz/remote"] = {},
            player = { client_id = 4, user_id = "zz-carol" },
            ["core/net/sync"] = false,
        }):id()
        step("arrived")

    elseif phase == "arrived" and #rows(world) == 3 and items_count(world) == 9 and clock > 0.3 then
        local ok, why = laid_out(world, carol, "zz-carol", 4)
        T("A1_a_player_arriving_gets_a_row_with_the_items", ok and #targets(world, carol) == 1, why)
        commands:entity(alice):insert({ player = { client_id = 2, user_id = "zz-alice-renamed" } })
        step("renamed")

    elseif phase == "renamed" and clock > 0.3 then
        local a = row_of(world, alice)
        T("N1_a_row_s_name_follows_its_player", a ~= nil and children_of(world, a)[1].text == "zz-alice-renamed",
            a and texts(children_of(world, a)) or "no row")
        mark.bob_row = row_of(world, bob) and row_of(world, bob):id()
        commands:entity(bob):despawn()
        step("left")

    elseif phase == "left" and clock > 0.5 then
        local gone = mark.bob_row ~= nil and world:query({ iter_many = { mark.bob_row } })[1] == nil
        T("G1_a_player_leaving_takes_its_row_and_its_items", gone and #rows(world) == 2 and items_count(world) == 6,
            string.format("row gone %s, rows %d, items %d", tostring(gone), #rows(world), items_count(world)))
        mark.button = button(world):id()
        mark.view = views(world)[1]:id()
        mark.rows = { row_of(world, alice):id(), row_of(world, carol):id() }
        mark.spawned = spawned
        mark.reloads = reloads
        original = read_file_bytes(MOD_FILE)
        write_file_bytes(MOD_FILE, original .. "\n-- zz 1\n")
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 and #rows(world) == 2 then
        local b = button(world)
        local a, c = row_of(world, alice), row_of(world, carol)
        T("H1_a_reload_keeps_the_panel_open_with_a_new_button_and_view", b ~= nil and b:id() ~= mark.button
            and b:has("sidebar/button/open") and #views(world) == 1 and views(world)[1]:id() ~= mark.view
            and state_of(world).open == true)
        T("H1_and_rebuilds_the_rows", a ~= nil and c ~= nil and a:id() ~= mark.rows[1] and c:id() ~= mark.rows[2]
            and #targets(world, alice) == 1 and #targets(world, carol) == 1)
        local ok_a, why_a = laid_out(world, alice, "zz-alice-renamed", 2)
        local ok_c, why_c = laid_out(world, carol, "zz-carol", 4)
        T("H1_the_contributor_adds_its_items_again_once_each", ok_a and ok_c and spawned == mark.spawned + 2,
            string.format("spawns %d: %s / %s", spawned - mark.spawned, why_a, why_c))
        mark.rows = { a:id(), c:id() }
        click(commands, b:id())
        step("closed")

    elseif phase == "closed" and clock > 0.5 then
        local left = world:query({ iter_many = mark.rows })
        T("X1_closing_takes_the_rows_and_their_items", #views(world) == 0 and #rows(world) == 0 and #left == 0
            and items_count(world) == 0 and state_of(world).open == false,
            string.format("views %d rows %d items %d", #views(world), #rows(world), items_count(world)))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 10 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        finish()
    end
end):in_set("zz/people/drive")
