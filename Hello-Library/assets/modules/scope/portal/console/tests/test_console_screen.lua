-- --host
-- A console's screen on a client, headless. A headless run computes no mesh bounds and lays out no
-- UI, so the screen mesh's `Aabb` is written here in Bevy's place, and the rows are clicked by
-- triggering Bevy's click on them; that the screen is drawn, sized from its real mesh, and picked by
-- the mouse is `test_console_windowed.lua`. Root's branch list and the load are answered by hand.
--
--   P0 the console binds no click of its own: the click is `pointer`'s, on this client's own player,
--      in game input and in UI input
--   P1 the screen: a `ui/screen` on the mesh, sized from it at 0.0008 m a pixel, its camera a child
--      of the mesh, and its root on that camera, styled as the console's column
--   P2 before any ask, "Points to <branch>" and "List branches"; a click asks root for this world's
--      repository's branches, under the console
--   P3 a refused list says why, and "List branches" stays
--  P10 a list root answers `not-installed` shows "the Hello Engine app isn't installed on
--      <owner>/<name>" with Install, and no branch rows; Install asks root's `vault/open_url` for
--      root's `install_url`, under the console, and root's answer closes it
--   P4 the branches, the door's own marked, then "New branch"; the ask goes
--   P5 a click on a branch asks the server to re-point the door, on this client's own player
--   P6 "New branch" opens the name field and gives the player UI input; typing writes the name
--   P7 Create asks root to load the new branch's world; once it is ready the door is re-pointed at
--      it, the load goes, the field closes and game input comes back
--   P9 a door with no target: "Points to nothing", and no branch marked as the door's
--   P8 a screen's mesh gone, its UI root goes; the last console taken off a node that stays, its
--      mesh's screen goes: `ui/screen`, its camera and its root
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local Plane3d = require("bevy::math::primitives::Plane3d")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local KeyboardInput = require("bevy::input::keyboard::KeyboardInput")
local Net = require("modules/core/net/shared/net.lua")

local suite = helpers.create_suite("PortalConsoleScreenSuite")
local T = suite.assert_test

-- This VM plays a client world, which is never root: root's own vault would take the console's ask.
world_id = 7

local ROOT = "github:zzscreen/world"
local AUTHORED = ROOT .. ":prologue"
local INSTALL_URL = "https://github.com/apps/zz-app/installations/new"

local own_net, player, screen, camera

app:add_systems(Startup, { World, ResMut[Assets[Mesh]], Commands }, function(world, meshes, commands)
    -- declared first, as the net does when it starts: an owner stored before it gets no owner edge
    Net.declare_ownership(world, commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzscreen" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        ["core/world/status"] = { scope_key = ROOT .. ":main", scope_root = ROOT, mode = "client", status = "ready",
            observer = true },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    commands:spawn({
        Name = "zz_door",
        ["scope/portal"] = { target = AUTHORED, at = "zz_arrival" },
        Transform = { translation = { x = 0, y = 0, z = -10 } },
        ["core/net/sync"] = false,
    })
    -- The screen node, as a glTF node with a mesh lands: the mesh on a child of the node.
    local console = commands:spawn({
        ["scope/portal/console"] = { door = "zz_door", at = "zz_door" },
        Transform = { translation = { x = 2, y = 1, z = -2 } },
        ["core/net/sync"] = false,
    }):id()
    screen = commands:spawn({
        ["zz/screen"] = {},
        Mesh3d = meshes:add(Plane3d.new({ x = 0, y = 0, z = 1 }, { x = 0.4, y = 0.3 })),
        Transform = {},
        ChildOf = console,
        ["core/net/sync"] = false,
    }):id()
end)

local keys = {}
app:add_systems(Update, { bevy.MessageWriter[KeyboardInput] }, function(write)
    for _, k in ipairs(keys) do write:write(k) end
    keys = {}
end):in_set("zz/console_screen/keys")
local function type_key(char, logical)
    keys[#keys + 1] = { key_code = "KeyA", logical_key = logical or { Character = char }, state = "Pressed",
        text = char, ["repeat"] = false, window = camera }
end

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function me(world)
    return world:query({
        with = { "zz/player" },
        optional = { "input/game", "input/ui", "input/mode", "scope/portal/console/request" },
    })[1]
end

local function console_of(world)
    return world:query({ with = { "scope/portal/console" }, optional = { "scope/portal/console/state", "Children" } })[1]
end

local function roots(world)
    return world:query({ with = { "ui/screen/root" }, optional = { "UiTargetCamera", "Node", "Children" } })
end
local function view(world)
    return roots(world)[1]
end

-- The screen's texts in order, and its rows by label: the branches sit in a list of their own.
local function shown(world)
    local v = view(world)
    local texts, rows = {}, {}
    for _, child in ipairs(v and world:descendants(v:id()) or {}) do
        local e = world:query({ iter_many = { child }, with = { "Text" }, optional = { "scope/portal/console/row" } })[1]
        if e ~= nil then
            texts[#texts + 1] = e:get("Text")
            if e:has("scope/portal/console/row") then rows[e:get("Text")] = e:id() end
        end
    end
    return texts, rows
end

local function said(world)
    local texts = shown(world)
    return (table.concat(texts, " | "):gsub("[^%g%s]+", "?"))
end

local function asks(world, name)
    return world:query({ with = { name, "Request" }, optional = { "ChildOf", name .. "/reply" } })
end

local function loads(world)
    return world:query({ with = { "core/world/load" } })
end

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local texts, rows = shown(world)

    if phase == "spawn" and clock > 0.3 then
        player = commands:spawn({
            ["zz/player"] = {},
            player = { client_id = 1 },
            input = {},
            ["input/mode"] = { mode = "input/game" },
            ["core/net/owner"] = own_net,
            ["core/net/sync"] = false,
        }):id()
        -- In Bevy's place: the bounds it computes for the mesh once it loads.
        commands:entity(screen):insert({ Aabb = { center = { x = 0, y = 0, z = 0 }, half_extents = { x = 0.4, y = 0.3, z = 0 } } })
        step("built")

    -- the pointer binds when its source arrives on the player, which may come after the screen
    elseif phase == "built" and (view(world) ~= nil and #texts > 0 and me(world) ~= nil
        and (me(world):get("input/ui") or {}).pointer ~= nil or clock > 5) then
        local p = me(world)
        local game, ui = p:get("input/game") or {}, p:get("input/ui") or {}
        T("P0_the_console_binds_no_click_of_its_own", game.portal_console == nil and ui.portal_console == nil)
        T("P0_the_click_is_the_pointer_s_in_game_and_ui_input", game.pointer ~= nil and game.pointer.press.button == "Left"
            and ui.pointer ~= nil and ui.pointer.press.button == "Left")
        local mesh = world:query({ iter_many = { screen }, with = { "ui/screen" } })[1]
        local size = mesh and mesh:get("ui/screen")
        local cam = world:query({ iter_many = world:descendants(screen), with = { "ui/screen/camera", "Camera", "Camera2d", "ChildOf" } })[1]
        local v = view(world)
        local node = v and v:get("Node")
        T("P1_a_ui_screen_sized_from_the_mesh_at_0_0008_m_a_pixel", size ~= nil and size.width == 1000 and size.height == 750,
            size and (tostring(size.width) .. "x" .. tostring(size.height)) or "no ui/screen")
        T("P1_its_camera_is_a_child_of_the_mesh", cam ~= nil and cam:get("ChildOf") == screen)
        T("P1_its_root_is_on_that_camera", v ~= nil and cam ~= nil and v:get("UiTargetCamera") == cam:id())
        T("P1_the_root_is_the_console_s_column_at_the_image_s_size", node ~= nil and node.width.Px == 1000 and node.height.Px == 750
            and node.flex_direction == "Column" and node.padding.left.Px == 64,
            node and (tostring(node.width.Px) .. "x" .. tostring(node.height.Px) .. " " .. tostring(node.flex_direction)) or "no node")
        T("P2_before_any_ask_points_to_and_list_branches", texts[1] == "Points to prologue" and rows["List branches"] ~= nil, said(world))
        click(commands, rows["List branches"])
        step("listing")

    elseif phase == "listing" and (#asks(world, "vault/github/branches") > 0 or clock > 5) then
        local a = asks(world, "vault/github/branches")[1]
        local wish = a and a:get("vault/github/branches")
        T("P2_a_click_asks_root_for_this_repository_s_branches", a ~= nil and wish.owner == "zzscreen" and wish.name == "world"
            and a:get("ChildOf") == console_of(world):id())
        commands:entity(a:id()):insert({ ["vault/github/branches/reply"] = { error = "denied" } })
        step("denied")

    elseif phase == "denied" and (said(world):find("denied", 1, true) or clock > 5) then
        T("P3_a_refused_list_says_why_and_list_branches_stays", said(world):find("denied", 1, true) ~= nil
            and rows["List branches"] ~= nil and #asks(world, "vault/github/branches") == 0, said(world))
        click(commands, rows["List branches"])
        step("listing_again")

    elseif phase == "listing_again" and (#asks(world, "vault/github/branches") > 0 or clock > 5) then
        local a = asks(world, "vault/github/branches")[1]
        commands:entity(a:id()):insert({ ["vault/github/branches/reply"] = {
            error = "http-404", status = 404, reason = "not-installed", install_url = INSTALL_URL,
        } })
        step("missing")

    elseif phase == "missing" and (rows["Install"] ~= nil or clock > 5) then
        T("P10_not_installed_shows_the_line_with_install", said(world):find("the Hello Engine app isn't installed on zzscreen/world", 1, true) ~= nil
            and rows["Install"] ~= nil and not said(world):find("http-404", 1, true), said(world))
        T("P10_and_no_branch_rows", rows["New branch"] == nil and rows["main"] == nil and rows["List branches"] ~= nil, said(world))
        if rows["Install"] == nil then
            phase = "done"
            suite.finish("PORTAL_CONSOLE_SCREEN")
            return
        end
        click(commands, rows["Install"])
        step("install")

    elseif phase == "install" and (#asks(world, "vault/open_url") > 0 or clock > 5) then
        local o = asks(world, "vault/open_url")
        T("P10_install_asks_root_to_open_its_install_url", #o == 1 and o[1]:get("vault/open_url").url == INSTALL_URL
            and o[1]:get("ChildOf") == console_of(world):id(), tostring(#o))
        if o[1] == nil then
            phase = "done"
            suite.finish("PORTAL_CONSOLE_SCREEN")
            return
        end
        commands:entity(o[1]:id()):insert({ ["vault/open_url/reply"] = { status = "opened" } })
        step("installed")

    elseif phase == "installed" and (#asks(world, "vault/open_url") == 0 or clock > 5) then
        T("P10_root_s_answer_closes_the_ask", #asks(world, "vault/open_url") == 0)
        click(commands, rows["List branches"])
        step("listing_third")

    elseif phase == "listing_third" and (#asks(world, "vault/github/branches") > 0 or clock > 5) then
        local a = asks(world, "vault/github/branches")[1]
        commands:entity(a:id()):insert({ ["vault/github/branches/reply"] = { branches = { "main", "prologue", "feature" } } })
        step("listed")

    elseif phase == "listed" and (rows["feature"] ~= nil or clock > 5) then
        T("P4_the_branches_the_door_s_own_marked_then_new_branch", rows["main"] ~= nil and rows["feature"] ~= nil
            and rows["New branch"] ~= nil and #asks(world, "vault/github/branches") == 0
            and said(world):find("prologue", 1, true) ~= nil and rows["prologue"] == nil, said(world))
        click(commands, rows["feature"])
        step("picked")

    elseif phase == "picked" and (me(world):has("scope/portal/console/request") or clock > 5) then
        local r = me(world):get("scope/portal/console/request") or {}
        T("P5_a_branch_asks_the_server_to_re_point_the_door", r.door == "zz_door" and r.target == ROOT .. ":feature",
            tostring(r.target))
        click(commands, rows["New branch"])
        step("field")

    elseif phase == "field" and ((console_of(world):get("scope/portal/console/state") or {}).typing ~= nil or clock > 5) then
        local mode = me(world):get("input/mode") or {}
        T("P6_new_branch_opens_the_field_and_gives_ui_input", (console_of(world):get("scope/portal/console/state") or {}).typing == ""
            and mode.mode == "input/ui" and mode.show_cursor == true, tostring(mode.mode))
        for _, ch in ipairs({ "z", "z", "-", "n", "e", "x" }) do type_key(ch) end
        type_key(nil, "Backspace")
        type_key("w")
        step("typed")

    elseif phase == "typed" and (rows["Create"] ~= nil and said(world):find("zz-new", 1, true) or clock > 5) then
        T("P6_typing_writes_the_name", (console_of(world):get("scope/portal/console/state") or {}).typing == "zz-new", said(world))
        click(commands, rows["Create"])
        step("loading")

    elseif phase == "loading" and (#loads(world) > 0 or clock > 5) then
        local l = loads(world)[1]
        T("P7_create_asks_root_to_load_the_new_branch", l ~= nil and l:get("core/world/load").scope == ROOT .. ":zz-new"
            and l:get("core/world/load").join_only == nil)
        if l == nil then
            phase = "done"
            suite.finish("PORTAL_CONSOLE_SCREEN")
            return
        end
        commands:entity(l:id()):entry("core/world/load"):and_modify(function(ask) ask.status = "ready" end)
        step("ready")

    elseif phase == "ready" and (#loads(world) == 0 or clock > 5) then
        local r = me(world):get("scope/portal/console/request") or {}
        local mode = me(world):get("input/mode") or {}
        T("P7_once_ready_the_door_is_re_pointed_at_it_and_the_load_goes", r.target == ROOT .. ":zz-new" and #loads(world) == 0,
            tostring(r.target))
        T("P7_and_the_field_closes_with_game_input_back", (console_of(world):get("scope/portal/console/state") or {}).typing == nil
            and mode.mode == "input/game", tostring(mode.mode))
        for _, d in ipairs(world:query({ with = { "scope/portal", "Name" } })) do
            if d:get("Name").name == "zz_door" then
                commands:entity(d:id()):insert({ ["scope/portal"] = { at = "zz_arrival" } })
            end
        end
        step("blank")

    elseif phase == "blank" and (said(world):find("nothing", 1, true) or clock > 5) then
        T("P9_a_door_with_no_target_points_to_nothing_and_marks_no_branch", texts[1] == "Points to nothing"
            and rows["main"] ~= nil and rows["prologue"] ~= nil and not said(world):find("?", 1, true), said(world))
        -- A second console with a screen of its own, so the mod stays loaded when the first goes.
        local spare = commands:spawn({ ["zz/spare"] = {}, ["scope/portal/console"] = { door = "zz_door", at = "zz_door" },
            Transform = { translation = { x = -2, y = 1, z = -2 } }, ["core/net/sync"] = false }):id()
        commands:spawn({
            ["zz/spare_screen"] = {},
            Mesh3d = world:query({ iter_many = { screen }, with = { "Mesh3d" } })[1]:get("Mesh3d"),
            Transform = {},
            Aabb = { center = { x = 0, y = 0, z = 0 }, half_extents = { x = 0.4, y = 0.3, z = 0 } },
            ChildOf = spare,
            ["core/net/sync"] = false,
        })
        step("held")

    elseif phase == "held" and (#roots(world) == 2 or clock > 5) then
        commands:entity(screen):despawn()
        step("removed")

    elseif phase == "removed" and (#roots(world) == 1 or clock > 5) then
        local left = roots(world)[1]
        local spare_cam = world:query({ with = { "ui/screen/camera", "ChildOf" } })[1]
        T("P8_a_screen_s_mesh_gone_its_ui_root_goes", #roots(world) == 1 and spare_cam ~= nil
            and left:get("UiTargetCamera") == spare_cam:id(), tostring(#roots(world)))
        for _, c in ipairs(world:query({ with = { "scope/portal/console" } })) do
            commands:entity(c:id()):remove("scope/portal/console")
        end
        step("last")

    elseif phase == "last" and clock > 0.5 then
        local spare = world:query({ with = { "zz/spare_screen" }, optional = { "ui/screen", "pointer/target" } })[1]
        T("P8_the_last_console_taken_off_its_mesh_s_screen_goes", spare ~= nil and not spare:has("ui/screen")
            and not spare:has("pointer/target") and #world:query({ with = { "ui/screen/camera" } }) == 0 and #roots(world) == 0,
            tostring(spare and spare:has("ui/screen")) .. " " .. tostring(#roots(world)))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_SCREEN")
    end

    if phase ~= "done" and clock > 10 then
        T("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "': " .. said(world))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_SCREEN")
    end
end):in_set("zz/console_screen")
