-- --host
-- A console's screen on a client, headless. A headless run computes no mesh bounds and lays out no
-- UI, so the screen mesh's `Aabb` is written here in Bevy's place, and the rows are clicked by
-- triggering Bevy's click on them; that the screen is drawn, sized from its real mesh, and picked by
-- the mouse is `test_console_windowed.lua`. Root's branch list and the load are answered by hand.
--
--   P0 the click is bound on this client's own player, in game input and in UI input
--   P1 the screen: an image sized from the mesh at 0.0008 m a pixel, a camera drawing into it, a
--      child of the mesh with its marker, and the UI root on that camera
--   P2 before any ask, "Points to <branch>" and "List branches"; a click asks root for this world's
--      repository's branches, under the console
--   P3 a refused list says why, and "List branches" stays
--   P4 the branches, the door's own marked, then "New branch"; the ask goes
--   P5 a click on a branch asks the server to re-point the door, on this client's own player
--   P6 "New branch" opens the name field and gives the player UI input; typing writes the name
--   P7 Create asks root to load the new branch's world; once it is ready the door is re-pointed at
--      it, the load goes, the field closes and game input comes back
--   P8 a screen's mesh gone, its UI root goes, and the click stays while a console does; the last
--      console gone, the click is unbound
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

local function view(world)
    return world:query({ with = { "scope/portal/console/view" }, optional = { "UiTargetCamera", "Node", "Children" } })[1]
end

-- The screen's texts in order, and its rows by label.
local function shown(world)
    local v = view(world)
    local texts, rows = {}, {}
    for _, child in ipairs(v and v:get("Children") or {}) do
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

    elseif phase == "built" and (view(world) ~= nil and #texts > 0 or clock > 5) then
        local p = me(world)
        local game, ui = p:get("input/game") or {}, p:get("input/ui") or {}
        T("P0_the_click_is_bound_in_game_and_ui_input", game.portal_console ~= nil and game.portal_console.press.button == "Left"
            and ui.portal_console ~= nil and ui.portal_console.press.button == "Left")
        local cam = world:query({ iter_many = world:descendants(screen), with = { "scope/portal/console/camera", "Camera", "Camera2d", "ChildOf" } })[1]
        local v = view(world)
        local node = v and v:get("Node")
        T("P1_a_camera_with_its_marker_is_a_child_of_the_mesh", cam ~= nil and cam:get("ChildOf") == screen)
        T("P1_the_ui_root_is_on_that_camera", v ~= nil and cam ~= nil and v:get("UiTargetCamera") == cam:id())
        T("P1_the_image_is_sized_from_the_mesh_at_0_0008_m_a_pixel", node ~= nil and node.width.Px == 1000 and node.height.Px == 750,
            node and (tostring(node.width.Px) .. "x" .. tostring(node.height.Px)) or "no node")
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
        -- A second console, with no screen, so the mod stays loaded when the first goes: with its last
        -- carrier gone, the mod unloads and takes its own entities with it.
        commands:spawn({ ["zz/spare"] = {}, ["scope/portal/console"] = { door = "zz_door", at = "zz_door" },
            ["core/net/sync"] = false })
        step("held")

    elseif phase == "held" and clock > 0.3 then
        commands:entity(screen):despawn()
        step("removed")

    elseif phase == "removed" and (view(world) == nil or clock > 5) then
        local game = me(world):get("input/game") or {}
        T("P8_a_screen_gone_its_ui_root_goes_and_the_click_stays_while_a_console_does", view(world) == nil
            and game.portal_console ~= nil)
        for _, c in ipairs(world:query({ with = { "scope/portal/console" } })) do commands:entity(c:id()):despawn() end
        step("last")

    elseif phase == "last" and clock > 0.5 then
        local game, ui = me(world):get("input/game") or {}, me(world):get("input/ui") or {}
        T("P8_the_last_console_gone_the_click_is_unbound", game.portal_console == nil and ui.portal_console == nil)
        phase = "done"
        suite.finish("PORTAL_CONSOLE_SCREEN")
    end

    if phase ~= "done" and clock > 10 then
        T("P0_reached_" .. phase, false, "stuck in phase '" .. phase .. "': " .. said(world))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_SCREEN")
    end
end):in_set("zz/console_screen")
