-- --host (windowed: a ray meets only what a view sees, and a panel's UI is laid out and picked through its image)
-- The VR tools on this client's own player, fed the messages the engine's VR plugin writes, and the
-- real sidebar as the panel. A headset is not involved: this checks the panel in the window's view,
-- not in the eyes.
--
--   VU1 opening the sidebar builds one panel, sized as the container, and the container draws into it
--   VU2 placed in front of the right hand, its front to the head
--   VU3 the ray on a button hovers it, at the button's pixel, and the laser shows along the ray
--   VU4 neither the laser nor the player's body comes between: the hover stays
--   VU5 the trigger clicks the button, through Bevy's picking
--   VU6 a long press is a right click, and its release no left click
--   VU7 the grip grabs the panel and it follows the hand, facing the head
--   VU8 letting go drops it
--   VU9 a wider container resizes the same panel
--   VU10 closing hides it, stops its camera, and the ray leaves it
--   VU11 reopening places it in front of the hand again
--   VU12 a reload rebuilds one panel, drawn by its new camera
--   VU13 removal takes the panels and the container's camera
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Capsule3d = require("bevy::math::primitives::Capsule3d")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local VrInputRaw = require("hello::vr_messages::VrInputRaw")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("VrUiPanelsWindowedSuite")
local T = suite.assert_test
local MOD_FILE = "assets/modules/vr/ui_panels/init.lua"

local hand = { x = 0, y = 1.2, z = -0.3 }
local head = { x = 0, y = 1.5, z = 0 }
local aim = { x = 0, y = 0, z = 0, w = 1 }
local raw = {}
local clicks = {}
local unhovered = 0

app:add_systems(Startup, { ResMut[Assets[Mesh]], ResMut[Assets[StandardMaterial]], Commands }, function(meshes, materials, commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    commands:spawn({
        ["zz/eye"] = {},
        Camera3d = {},
        Camera = { order = 0 },
        IsDefaultUiCamera = true,
        Transform = { translation = { x = 0, y = 1.5, z = 0.5 } },
    })
    commands:spawn({
        ["zz/body"] = {},
        Mesh3d = meshes:add(Capsule3d.new(0.15, 0.3)),
        ["MeshMaterial3d<StandardMaterial>"] = materials:add({ base_color = { Srgba = { red = 0.5, green = 0.5, blue = 0.5, alpha = 1 } } }),
        Transform = { translation = hand },
        Visibility = "Visible",
    })
    commands:spawn({
        ["zz/me"] = {},
        sidebar = {},
        ["vr/input"] = {},
        ["vr/pointer"] = { pitch = 0, yaw = 0 },
        ["vr/grabbable"] = {},
        ["vr/ui_panels"] = {},
        input = {},
        ["input/mode"] = { mode = "input/game" },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = {},
    })
end)

-- A button in the bar, at pixels 6 to 42 across and 4 to 40 down: the bar is 48 wide with 4 of padding.
app:add_systems(Update, {
    Query[{ added = { "sidebar/bar" } }],
    Commands,
}, function(bars, commands)
    for _, bar in ipairs(bars:iter()) do
        local button = commands:spawn({
            ["zz/button"] = {},
            Button = {},
            Node = { width = { Px = 36 }, height = { Px = 36 } },
        })
        button:observe(On[Pointer[Click]], {}, function(event)
            clicks[event.event.button] = (clicks[event.event.button] or 0) + 1
        end)
        commands:entity(bar:id()):add_child(button:id())
    end
end):in_set("zz/vr_ui_panels/button")

app:add_systems(Update, {
    Query[{ removed = { "vr/pointer/hovered" } }],
}, function(left)
    unhovered = unhovered + #left:iter()
end):in_set("zz/vr_ui_panels/unhovered")

local function me(world)
    return world:query({ with = { "zz/me" }, optional = { "Children", "UiTargetCamera" } })[1]
end
local function container(world)
    return world:query({ with = { "sidebar/container" }, optional = { "ComputedNode", "UiTargetCamera" } })[1]
end
local function panels(world)
    return world:query({
        with = { "vr/ui_panels/panel" },
        optional = { "vr/pointer/target", "vr/pointer/hovered", "vr/grabbable/held", "Visibility", "NoFrustumCulling", "Children" },
    })
end
local function camera_of(world, panel)
    return world:query({ iter_many = world:descendants(panel:id()), with = { "vr/ui_panels/camera", "Camera" } })[1]
end
local function laser(world)
    return world:query({ with = { "vr/pointer/laser" }, optional = { "Visibility" } })[1]
end
local function global(world, e)
    return world:get_entity(e:id()).GlobalTransform:compute_transform()
end
local function near(a, b, d) return Vec3.distance(a, b) < (d or 0.01) end
local function show(v) return v and string.format("%.3f %.3f %.3f", v.x, v.y, v.z) or "nil" end

-- Turns the hand to the button's centre, (24, 22) in the image, on the panel as it stands.
local function aim_at_button(world)
    local panel = panels(world)[1]
    local p = panel:get("vr/ui_panels/panel")
    local at = global(world, panel)
    local local_point = {
        x = (24 / p.width - 0.5) * p.width * 0.0008,
        y = (0.5 - 22 / p.height) * p.height * 0.0008,
        z = 0,
    }
    local point = Vec3.add(at.translation, Quat.mul_vec3(at.rotation, local_point))
    aim = Quat.from_rotation_arc({ x = 0, y = 0, z = -1 }, Vec3.normalize(Vec3.sub(point, hand)))
end

local steps, at, t, mark = {}, 1, 0, 0
local state = {}
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end

step(function(world)
    return container(world) ~= nil and laser(world) ~= nil and me(world) ~= nil
end, function(world, commands)
    commands:entity(me(world):id()):insert({ ["sidebar/open"] = {} })
end)
step(function(world)
    return #panels(world) == 1 and t - mark > 0.8
end, function(world)
    local c = container(world)
    local panel = panels(world)[1]
    local p = panel:get("vr/ui_panels/panel")
    local size = c:get("ComputedNode").size
    local target = panel:get("vr/pointer/target")
    T("VU1_one_panel_sized_as_the_container", #panels(world) == 1 and p.width == math.floor(size.x) and p.height == math.floor(size.y),
        string.format("%s x %s against %.1f x %.1f", tostring(p.width), tostring(p.height), size.x, size.y))
    T("VU1_its_pointer_target_is_its_image", target.width == p.width and target.height == p.height and panel:has("NoFrustumCulling"), "")
    local cam = camera_of(world, panel)
    T("VU1_the_container_draws_into_it", cam ~= nil and c:get("UiTargetCamera") == cam:id(), tostring(c:get("UiTargetCamera")))
    local placed = global(world, panel)
    T("VU2_placed_in_front_of_the_hand", near(placed.translation, { x = 0, y = 1.2, z = -0.87 }), show(placed.translation))
    local front = Quat.mul_vec3(placed.rotation, { x = 0, y = 0, z = 1 })
    T("VU2_its_front_to_the_head", front.z > 0.99, show(front))
    aim_at_button(world)
end)
step(function(world)
    local panel = panels(world)[1]
    return panel:has("vr/pointer/hovered") or t - mark > 3
end, function(world)
    local h = panels(world)[1]:get("vr/pointer/hovered")
    T("VU3_the_ray_hovers_the_buttons_pixel", h ~= nil and math.abs(h.x - 24) < 2 and math.abs(h.y - 22) < 2,
        h and string.format("%.1f %.1f", h.x, h.y) or "not hovered")
    unhovered = 0
end)
step(after(0.5), function(world)
    local l = laser(world)
    T("VU3_the_laser_shows_along_the_ray", l:get("Visibility") == "Visible"
        and near(global(world, l).translation, Vec3.add(hand, Quat.mul_vec3(aim, { x = 0, y = 0, z = -1 }))),
        tostring(l:get("Visibility")) .. " " .. show(global(world, l).translation))
    T("VU4_neither_the_laser_nor_the_body_comes_between", unhovered == 0 and panels(world)[1]:has("vr/pointer/hovered"), tostring(unhovered))
    raw = { right_trigger = 1 }
end)
step(after(0.15), function() raw = {} end)
step(after(0.4), function()
    T("VU5_the_trigger_clicks_the_button", clicks.Primary == 1, tostring(clicks.Primary))
    raw = { right_trigger = 1 }
end)
step(after(0.9), function() raw = {} end)
step(after(0.4), function()
    T("VU6_a_long_press_is_a_right_click", clicks.Secondary == 1, tostring(clicks.Secondary))
    T("VU6_and_its_release_no_left_click", clicks.Primary == 1, tostring(clicks.Primary))
    raw = { right_grip = 1 }
end)
step(after(0.3), function(world)
    local panel = panels(world)[1]
    T("VU7_the_grip_grabs_the_panel", panel:has("vr/grabbable/held"), "")
    state.before = global(world, panel).translation
    hand = { x = 0.2, y = 1.2, z = -0.3 }
end)
step(after(0.4), function(world)
    local panel = panels(world)[1]
    local now = global(world, panel)
    T("VU7_it_follows_the_hand", near(now.translation, Vec3.add(state.before, { x = 0.2, y = 0, z = 0 })), show(now.translation))
    local front = Quat.mul_vec3(now.rotation, { x = 0, y = 0, z = 1 })
    local toward = Vec3.normalize({ x = head.x - now.translation.x, y = 0, z = head.z - now.translation.z })
    T("VU7_facing_the_head", Vec3.dot(front, toward) > 0.99, show(front))
    raw = {}
end)
step(after(0.3), function(world, commands)
    T("VU8_letting_go_drops_it", not panels(world)[1]:has("vr/grabbable/held"), "")
    state.panel = panels(world)[1]:id()
    state.width = panels(world)[1]:get("vr/ui_panels/panel").width
    commands:entity(container(world):id()):add_child(commands:spawn({
        ["zz/wide"] = {},
        Node = { width = { Px = 200 }, height = { Px = 50 } },
    }):id())
end)
step(function(world)
    local p = panels(world)[1]
    return (p ~= nil and p:get("vr/ui_panels/panel").width ~= state.width and t - mark > 0.5) or t - mark > 3
end, function(world)
    local panel = panels(world)[1]
    local p = panel:get("vr/ui_panels/panel")
    local size = container(world):get("ComputedNode").size
    T("VU9_a_wider_container_resizes_the_same_panel", #panels(world) == 1 and panel:id() == state.panel
        and p.width == math.floor(size.x) and panel:get("vr/pointer/target").width == p.width,
        string.format("%s against %.1f", tostring(p.width), size.x))
    T("VU9_still_drawn_by_its_camera", container(world):get("UiTargetCamera") == camera_of(world, panel):id(), "")
end)
step(after(0.1), function(world, commands)
    commands:entity(me(world):id()):remove("sidebar/open")
end)
step(after(0.5), function(world)
    local panel = panels(world)[1]
    T("VU10_closing_hides_it", panel:get("Visibility") == "Hidden", tostring(panel:get("Visibility")))
    T("VU10_stops_its_camera", camera_of(world, panel):get("Camera").is_active == false, "")
    T("VU10_and_the_ray_leaves_it", not panel:has("vr/pointer/hovered") and laser(world):get("Visibility") == "Hidden", "")
    hand = { x = 1, y = 1.2, z = -0.3 }
    head = { x = 1, y = 1.5, z = 0 }
end)
step(after(0.3), function(world, commands)
    commands:entity(me(world):id()):insert({ ["sidebar/open"] = {} })
end)
step(after(0.5), function(world)
    local panel = panels(world)[1]
    T("VU11_reopening_places_it_in_front_of_the_hand_again", panel:get("Visibility") == "Visible"
        and near(global(world, panel).translation, { x = 1, y = 1.2, z = -0.87 }), show(global(world, panel).translation))
    T("VU11_and_starts_its_camera", camera_of(world, panel):get("Camera").is_active == true, "")
    write_file_bytes(MOD_FILE, read_file_bytes(MOD_FILE))
end)
step(after(1.5), function(world, commands)
    local list = panels(world)
    T("VU12_a_reload_rebuilds_one_panel", #list == 1 and list[1]:get("Visibility") == "Visible", tostring(#list))
    T("VU12_drawn_by_its_new_camera", list[1] ~= nil and container(world):get("UiTargetCamera") == camera_of(world, list[1]):id(), "")
    commands:entity(me(world):id()):remove("vr/ui_panels")
end)
step(after(0.5), function(world)
    T("VU13_removal_takes_the_panels", #panels(world) == 0 and #world:query({ with = { "vr/ui_panels/camera" } }) == 0, tostring(#panels(world)))
    T("VU13_and_the_containers_camera", not container(world):has("UiTargetCamera"), "")
end)

local done = false
app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter[VrInputRaw],
    bevy.MessageWriter[VrPoseInput],
}, function(world, commands, write_raw, write_pose)
    t = t + world:delta_time()
    write_raw:write(raw)
    write_pose:write({
        hmd_position = head,
        hmd_rotation = { x = 0, y = 0, z = 0, w = 1 },
        hmd_forward = { x = 0, y = 0, z = -1 },
        right_position = hand,
        right_rotation = aim,
        right_forward = Quat.mul_vec3(aim, { x = 0, y = 0, z = -1 }),
    })
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("VrUiPanelsWindowedSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 15 then
        T("VU0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("VrUiPanelsWindowedSuite")
    end
end):in_set("zz/vr_ui_panels_drive")
