-- --host
-- `vr/ui_panels` building, sizing, placing and taking down a panel, headless. A headless run lays
-- out no UI, so the container's `ComputedNode` is written here in the layout's place; that the
-- panel is drawn and picked is `test_vr_ui_panels_windowed.lua`.
--
--   VUP1 a container with a size gets one panel, linked to it, carrying the pointer's and the grip's
--        targets, with a camera child the container draws into
--   VUP2 placed in front of the right hand, nearer by the container's z index, its front to the head
--   VUP3 a new size resizes the same panel and its pointer target
--   VUP4 hidden with the container, its camera stopped; shown again in front of where the hand is now
--   VUP5 a reload rebuilds one panel, drawn by its new camera
--   VUP6 removal takes the panels and the container's camera
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local suite = helpers.create_suite("VrUiPanelsSuite")
local T = suite.assert_test
local MOD_FILE = "assets/modules/vr/ui_panels/init.lua"

local hand = { x = 0, y = 1.2, z = -0.3 }
local head = { x = 0, y = 1.5, z = 0 }

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/me"] = {},
        ["vr/input"] = {},
        ["vr/ui_panels"] = {},
        input = {},
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = {},
    })
    commands:spawn({
        ["sidebar/container"] = {},
        Node = { display = "Flex" },
        ComputedNode = { size = { x = 300, y = 500 } },
        GlobalZIndex = { value = 100 },
    })
end)

local function me(world)
    return world:query({ with = { "zz/me" } })[1]
end
local function container(world)
    return world:query({
        with = { "sidebar/container" },
        optional = { "UiTargetCamera", "vr/ui_panels/panels" },
    })[1]
end
local function panels(world)
    return world:query({
        with = { "vr/ui_panels/panel", "Transform" },
        optional = { "vr/pointer/target", "vr/grabbable/target", "Visibility", "NoFrustumCulling", "Mesh3d" },
    })
end
local function camera_of(world, panel)
    return world:query({ iter_many = world:descendants(panel:id()), with = { "vr/ui_panels/camera", "Camera", "Camera2d" } })[1]
end
local function near(a, b) return Vec3.distance(a, b) < 1e-3 end
local function show(v) return v and string.format("%.3f %.3f %.3f", v.x, v.y, v.z) or "nil" end

local steps, at, t, mark = {}, 1, 0, 0
local state = {}
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end

step(function(world)
    return #panels(world) == 1
end, function(world, commands)
    local panel = panels(world)[1]
    local c = container(world)
    local p = panel:get("vr/ui_panels/panel")
    local target = panel:get("vr/pointer/target")
    T("VUP1_one_panel_linked_to_the_container", p.entity == c:id() and #(c:get("vr/ui_panels/panels") or {}) == 1
        and p.width == 300 and p.height == 500, tostring(p.width) .. " x " .. tostring(p.height))
    T("VUP1_it_is_a_pointer_target_on_its_image", target ~= nil and target.width == 300 and target.height == 500 and target.image ~= nil, "")
    T("VUP1_and_a_grip_target_that_faces", panel:get("vr/grabbable/target").face == true and panel:has("NoFrustumCulling"), "")
    local cam = camera_of(world, panel)
    T("VUP1_the_container_draws_into_its_camera", cam ~= nil and c:get("UiTargetCamera") == cam:id() and cam:get("Camera").order == -200,
        tostring(c:get("UiTargetCamera")))
    local placed = panel:get("Transform")
    -- 0.6 nearer by 100 * 0.0003, straight on from the head through the hand
    T("VUP2_placed_in_front_of_the_hand", near(placed.translation, { x = 0, y = 1.2, z = -0.87 }), show(placed.translation))
    T("VUP2_its_front_to_the_head", Quat.mul_vec3(placed.rotation, { x = 0, y = 0, z = 1 }).z > 0.999, "")
    state.panel, state.camera = panel:id(), cam:id()
    commands:entity(c:id()):insert({ ComputedNode = { size = { x = 420, y = 500 } } })
end)
step(after(0.3), function(world, commands)
    local panel = panels(world)[1]
    local p = panel:get("vr/ui_panels/panel")
    T("VUP3_a_new_size_resizes_the_same_panel", #panels(world) == 1 and panel:id() == state.panel and p.width == 420,
        tostring(#panels(world)) .. " " .. tostring(p.width))
    T("VUP3_and_its_pointer_target", panel:get("vr/pointer/target").width == 420, "")
    T("VUP3_drawn_by_the_same_camera", container(world):get("UiTargetCamera") == state.camera, "")
    commands:entity(container(world):id()):insert({ Node = { display = "None" } })
end)
step(after(0.3), function(world, commands)
    local panel = panels(world)[1]
    T("VUP4_hidden_with_the_container", panel:get("Visibility") == "Hidden", tostring(panel:get("Visibility")))
    T("VUP4_its_camera_stopped", camera_of(world, panel):get("Camera").is_active == false, "")
    hand = { x = 2, y = 1.2, z = -0.3 }
    head = { x = 2.3, y = 1.5, z = 0.1 }
end)
step(after(0.3), function(world, commands)
    commands:entity(container(world):id()):insert({ Node = { display = "Flex" } })
end)
step(after(0.3), function(world)
    local panel = panels(world)[1]
    local placed = panel:get("Transform")
    local ahead = Vec3.normalize({ x = hand.x - head.x, y = 0, z = hand.z - head.z })
    local expect = Vec3.add(hand, Vec3.mul(ahead, Vec3.splat(0.57)))
    T("VUP4_shown_again_in_front_of_the_hand_now", panel:get("Visibility") == "Visible" and near(placed.translation, expect),
        show(placed.translation) .. " against " .. show(expect))
    local front = Quat.mul_vec3(placed.rotation, { x = 0, y = 0, z = 1 })
    T("VUP4_facing_the_head", Vec3.dot(front, { x = -ahead.x, y = 0, z = -ahead.z }) > 0.999, show(front))
    T("VUP4_its_camera_running", camera_of(world, panel):get("Camera").is_active == true, "")
    write_file_bytes(MOD_FILE, read_file_bytes(MOD_FILE))
end)
step(after(1.0), function(world, commands)
    local list = panels(world)
    local cam = list[1] and camera_of(world, list[1])
    T("VUP5_a_reload_rebuilds_one_panel", #list == 1 and list[1]:id() ~= state.panel, tostring(#list))
    T("VUP5_drawn_by_its_new_camera", cam ~= nil and cam:id() ~= state.camera and container(world):get("UiTargetCamera") == cam:id(), "")
    commands:entity(me(world):id()):remove("vr/ui_panels")
end)
step(after(0.5), function(world)
    T("VUP6_removal_takes_the_panels", #panels(world) == 0 and #world:query({ with = { "vr/ui_panels/camera" } }) == 0, tostring(#panels(world)))
    T("VUP6_and_the_containers_camera", not container(world):has("UiTargetCamera"), "")
end)

local done = false
app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter[VrPoseInput],
}, function(world, commands, write_pose)
    t = t + world:delta_time()
    write_pose:write({
        hmd_position = head,
        hmd_rotation = { x = 0, y = 0, z = 0, w = 1 },
        hmd_forward = { x = 0, y = 0, z = -1 },
        right_position = hand,
        right_rotation = { x = 0, y = 0, z = 0, w = 1 },
        right_forward = { x = 0, y = 0, z = -1 },
    })
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("VrUiPanelsSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 15 then
        T("VUP0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("VrUiPanelsSuite")
    end
end):in_set("zz/vr_ui_panels_drive")
