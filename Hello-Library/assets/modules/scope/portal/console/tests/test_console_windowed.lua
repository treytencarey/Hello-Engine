-- --host (windowed: the screen's mesh bounds, its layout and the mouse pick need a window)
-- A console's screen on a client, with a real mesh, Bevy's bounds and layout, and the real pick.
-- The player's eye is stood in by a camera with `camera/3d/eye`, 2 m in front of the screen, looking
-- straight at it; a click is a left button through `input`, as the mouse's is, and the wheel is
-- `input`'s synthetic wheel.
--
--   WS1 the mesh's `Aabb` is read: the image is sized from it at 0.0008 m a pixel (1000 x 750 for a
--       0.8 m x 0.6 m screen), and the UI root is laid out at that size
--   WS2 the screen draws the camera's image, unlit
--   WS3 the UV assumption: the mesh has u along its X from the left and v down from the top, so a
--       ray at the point of a pixel meets the mesh at that pixel's uv
--   WS3 and a click there, on "List branches", lands on that row and asks root for the branches
--   WS8 the window's mouse moving while the ray rests on the row takes nothing from the pointer: a
--       click still lands on the row
--   WS4 a click 4 m away, past the 3 m reach, asks nothing
--   WS5 the mouse's own click after that, as Bevy's picking writes it for the real button with the
--       aim off the screen, clicks nothing on it: the pointer has left the screen's image
--   WS6 the wheel on the screen scrolls the row under the pointer
--   WS7 and while on the screen the wheel is not the camera's: the third-person zoom gets none of it,
--       and gets it again once the aim is off the screen
--   WS10 a branch list longer than the screen scrolls under the wheel
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Plane3d = require("bevy::math::primitives::Plane3d")
local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local Net = require("modules/core/net/shared/net.lua")
local bevy = require("bevy::prelude")
local PointerInput = require("bevy::picking::pointer::PointerInput")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Scroll = require("bevy::picking::prelude::Scroll")

local suite = helpers.create_suite("PortalConsoleWindowedSuite")
local T = suite.assert_test

-- This VM plays a client world, which is never root: root's own vault would take the console's ask.
world_id = 7

local ROOT = "github:zzwindow/world"
local SCREEN_AT = { x = 0, y = 1.5, z = -2 }
-- "List branches", the second line: 16 of padding, a 28 px line, a gap of 8, then a row of 6 + 28 px
-- + 6, so its middle is near 80 down; it spans from 64 across.
local ROW_PIXEL = { x = 150, y = 80 }

local own_net, player, eye

-- The point of the screen at pixel (x, y) of its 1000 x 750 image, under the UV assumption.
local function point_at(x, y)
    return { x = SCREEN_AT.x - 0.4 + (x / 1000) * 0.8, y = SCREEN_AT.y + 0.3 - (y / 750) * 0.6, z = SCREEN_AT.z }
end

app:add_systems(Startup, { World, ResMut[Assets[Mesh]], Commands }, function(world, meshes, commands)
    Net.declare_ownership(world, commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzwindow" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        ["core/world/status"] = { scope_key = ROOT .. ":main", scope_root = ROOT, mode = "client", status = "ready",
            observer = true },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        Name = "zz_door",
        ["scope/portal"] = { target = ROOT .. ":prologue", at = "zz_arrival" },
        Transform = { translation = { x = 10, y = 0, z = -10 } },
        ["core/net/sync"] = false,
    })
    local console = commands:spawn({
        ["scope/portal/console"] = { door = "zz_door", at = "zz_door" },
        Transform = { translation = SCREEN_AT },
        Visibility = "Visible",
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        ["zz/screen"] = {},
        Mesh3d = meshes:add(Plane3d.new({ x = 0, y = 0, z = 1 }, { x = 0.4, y = 0.3 })),
        Transform = {},
        Visibility = "Visible",
        ChildOf = console,
        ["core/net/sync"] = false,
    })
end)

local function asks(world)
    return world:query({ with = { "vault/github/branches", "Request" } })
end

local function view(world)
    return world:query({ with = { "ui/screen/root" }, optional = { "ComputedNode", "Node" } })[1]
end

local function row(world, label)
    for _, r in ipairs(world:query({ with = { "scope/portal/console/row", "Text" } })) do
        if r:get("Text") == label then return r end
    end
end

-- The eye is the player's child and the player stands at the origin, so its local place is its place.
local function aim(commands, pixel, distance)
    local p = point_at(pixel.x, pixel.y)
    commands:entity(eye):insert({
        Transform = { translation = { x = p.x, y = p.y, z = SCREEN_AT.z + distance }, rotation = { x = 0, y = 0, z = 0, w = 1 } },
    })
end

local clicks = {}
local function press()
    clicks[#clicks + 1] = { button = "Left", state = "Pressed" }
    clicks[#clicks + 1] = { button = "Left", state = "Released" }
end
app:add_systems(First, { World }, function(world)
    local c = table.remove(clicks, 1)
    if c ~= nil then world:write_message("input/synthetic_mouse_button", c) end
end):in_set("zz/console_windowed/clicks")

-- notches to turn, and which way: up (+1) or down (-1)
local wheel, wheel_y = 0, 1
app:add_systems(First, { World }, function(world)
    if wheel > 0 then
        wheel = wheel - 1
        world:write_message("input/synthetic_mouse_wheel", { x = 0, y = wheel_y })
    end
end):in_set("zz/console_windowed/wheel")


local zoomed, scrolled = false, false
app:add_systems(Update, { Query[{ with = { "zz/player", "input/game/third_person/zoom" } }] }, function(zooming)
    if not zooming:is_empty() then zoomed = true end
end):in_set("zz/console_windowed/zoom")

-- The real button, as `bevy_picking`'s mouse input writes it: a press and a release of the mouse
-- pointer, which picking sends to what the pointer hovers. Where it says it is doesn't matter to
-- a press; the screen's image is a location Lua can build.
local mouse = {}
app:add_systems(First, {
    Query[{ with = { "zz/screen", "pointer/target" } }],
    bevy.MessageWriter[PointerInput],
}, function(screens, pointer)
    local action = table.remove(mouse, 1)
    local screen = screens:iter()[1]
    if action == nil or screen == nil then return end
    pointer:write({
        pointer_id = "Mouse",
        location = { target = { Image = screen:get("pointer/target").image }, position = { x = -10, y = -10 } },
        action = action,
    })
end):in_set("zz/console_windowed/mouse")

local phase, clock = "spawn", 0

app:add_systems(Update, { World, MeshRayCast, Res[Assets[StandardMaterial]], Commands }, function(world, ray_cast, materials, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" and clock > 0.5 then
        player = commands:spawn({
            ["zz/player"] = {},
            player = { client_id = 1 },
            input = {},
            ["input/mode"] = { mode = "input/game" },
            -- the zoom as `camera/third_person` binds it
            ["input/game"] = { third_person = { zoom = { scroll = true } } },
            ["core/net/owner"] = own_net,
            Transform = {},
            Visibility = "Visible",
            ["core/net/sync"] = false,
        }):id()
        eye = commands:spawn({
            ["camera/3d/eye"] = {},
            Camera3d = {},
            Camera = { order = 0 },
            Transform = {},
            ChildOf = player,
        }):id()
        aim(commands, ROW_PIXEL, 2)
        step("built")

    elseif phase == "built" then
        local v = view(world)
        local laid = v and v:get("ComputedNode")
        if not ((laid ~= nil and laid.size.x > 0 and clock > 0.5) or clock > 10) then return end
        local node = v and v:get("Node")
        T("WS1_the_image_is_sized_from_the_mesh_s_aabb", node ~= nil and node.width.Px == 1000 and node.height.Px == 750,
            node and (tostring(node.width.Px) .. "x" .. tostring(node.height.Px)) or "no screen: was the Aabb read?")
        T("WS1_and_the_ui_root_is_laid_out_at_that_size", laid ~= nil and math.abs(laid.size.x - 1000) < 1
            and math.abs(laid.size.y - 750) < 1, laid and (tostring(laid.size.x) .. "x" .. tostring(laid.size.y)) or "none")
        local mesh = world:query({ with = { "zz/screen", "MeshMaterial3d<StandardMaterial>" } })[1]
        local cam = world:query({ with = { "ui/screen/camera", "Camera" } })[1]
        local material = mesh and materials:get(mesh:get("MeshMaterial3d<StandardMaterial>"))
        T("WS2_the_screen_draws_the_camera_s_image_unlit", material ~= nil and material.unlit == true
            and material.base_color_texture ~= nil and cam ~= nil and cam:get("Camera").target ~= nil,
            tostring(material and material.unlit))
        -- The suite's own ray, as the pick casts it: from the eye, along its forward.
        local from = point_at(ROW_PIXEL.x, ROW_PIXEL.y)
        local hit = ray_cast:cast_ray({ origin = { x = from.x, y = from.y, z = SCREEN_AT.z + 2 }, direction = { x = 0, y = 0, z = -1 } },
            { visibility = "Any" })[1]
        local uv = hit and hit.ray_mesh_hit.uv
        local want = { x = ROW_PIXEL.x / 1000, y = ROW_PIXEL.y / 750 }
        T("WS3_a_ray_at_a_pixel_s_point_meets_the_mesh_at_its_uv", uv ~= nil and math.abs(uv.x - want.x) < 0.01
            and math.abs(uv.y - want.y) < 0.01, uv and string.format("uv %.3f,%.3f against %.3f,%.3f", uv.x, uv.y, want.x, want.y)
            or (hit and "a hit with no uv" or "no hit"))
        press()
        step("clicked")

    elseif phase == "clicked" and (#asks(world) > 0 or clock > 3) then
        T("WS3_and_a_click_on_list_branches_lands_on_its_row", #asks(world) == 1, tostring(#asks(world)) .. " asks")
        for _, a in ipairs(asks(world)) do commands:entity(a:id()):despawn() end
        -- the real mouse moving, as Bevy's picking writes it, somewhere off the row
        mouse[#mouse + 1] = { Move = { delta = { x = 1, y = 1 } } }
        step("stolen")

    elseif phase == "stolen" and clock > 0.5 then
        press()
        step("stolen_clicked")

    elseif phase == "stolen_clicked" and (#asks(world) > 0 or clock > 3) then
        T("WS8_the_window_s_mouse_moving_takes_nothing_from_the_pointer", #asks(world) == 1,
            tostring(#asks(world)) .. " asks: the mouse's move took the pointer off the row")
        for _, a in ipairs(asks(world)) do commands:entity(a:id()):despawn() end
        aim(commands, ROW_PIXEL, 4)
        step("far")

    elseif phase == "far" and clock > 0.5 then
        press()
        step("far_clicked")

    elseif phase == "far_clicked" and clock > 2 then
        T("WS4_past_3_m_a_click_asks_nothing", #asks(world) == 0, tostring(#asks(world)) .. " asks")
        mouse[#mouse + 1] = { Press = "Primary" }
        mouse[#mouse + 1] = { Release = "Primary" }
        step("mouse_clicked")

    elseif phase == "mouse_clicked" and clock > 1 then
        T("WS5_the_mouse_s_own_click_off_the_screen_clicks_nothing_on_it", #asks(world) == 0,
            tostring(#asks(world)) .. " asks: the pointer still hovers the row")
        for _, a in ipairs(asks(world)) do commands:entity(a:id()):despawn() end
        aim(commands, ROW_PIXEL, 2)
        local r = row(world, "List branches")
        if r ~= nil then
            commands:entity(r:id()):observe(On[Pointer[Scroll]], {}, function()
                scrolled = true
            end)
        end
        step("observed")

    elseif phase == "observed" and clock > 0.3 then
        zoomed, scrolled = false, false
        wheel = 5
        step("wheel")

    elseif phase == "wheel" and clock > 1 then
        T("WS6_the_wheel_on_the_screen_scrolls_the_row_under_the_pointer", scrolled)
        T("WS7_while_on_the_screen_the_wheel_does_not_zoom", not zoomed)
        commands:entity(eye):insert({
            Transform = { translation = { x = SCREEN_AT.x + 3, y = SCREEN_AT.y, z = SCREEN_AT.z + 2 }, rotation = { x = 0, y = 0, z = 0, w = 1 } },
        })
        step("away")

    elseif phase == "away" and clock > 0.5 then
        zoomed = false
        wheel = 5
        step("away_wheel")

    elseif phase == "away_wheel" and clock > 1 then
        T("WS7_and_off_the_screen_the_zoom_has_the_wheel_again", zoomed)
        for _, a in ipairs(asks(world)) do commands:entity(a:id()):despawn() end
        aim(commands, ROW_PIXEL, 2)
        step("long_aim")

    elseif phase == "long_aim" and clock > 0.5 then
        press()
        step("long_asked")

    elseif phase == "long_asked" and (#asks(world) > 0 or clock > 3) then
        -- root's answer: more branches than the screen has room for
        local branches = {}
        for i = 1, 40 do branches[#branches + 1] = string.format("zz-branch-%02d", i) end
        local a = asks(world)[1]
        if a ~= nil then commands:entity(a:id()):insert({ ["vault/github/branches/reply"] = { branches = branches } }) end
        step("long_listed")

    elseif phase == "long_listed" and (row(world, "zz-branch-40") ~= nil or clock > 3) and clock > 1 then
        wheel, wheel_y = 5, -1
        step("long_wheel")

    elseif phase == "long_wheel" and clock > 1 then
        local moved = false
        for _, e in ipairs(world:query({ with = { "ScrollPosition" }, iter_many = world:descendants(view(world):id()) })) do
            moved = moved or e:get("ScrollPosition").y > 0
        end
        T("WS10_a_branch_list_longer_than_the_screen_scrolls_under_the_wheel", moved)
        phase = "done"
        suite.finish("PORTAL_CONSOLE_WINDOWED")
    end

    if phase ~= "done" and clock > 15 then
        T("WS0_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        suite.finish("PORTAL_CONSOLE_WINDOWED")
    end
end):in_set("zz/console_windowed")
