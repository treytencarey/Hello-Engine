-- The sidebar as a panel in the world for this client's own player in VR. Its container is drawn
-- into an image by a camera of its own, and the image is shown on a mesh that the pointer can
-- point at and the grip can carry. Each time the sidebar opens, the panel is placed in front of
-- the right hand again, facing the head.
--
-- vr/ui_panels = {
--     pixels_to_meters = <metres per pixel of the panel>,
--     distance = <metres in front of the hand>,
--     min_distance = <the least it comes to>,
--     z_index_scale = <metres nearer for each step of the container's GlobalZIndex>,
--     camera_order = <the panel camera's order>,
-- }
--
-- vr/ui_panels/panel = {
--     entity = <the container>,
--     width, height = <pixels of its image>,
--     image = <the image handle>,
-- }: on the mesh
--
-- vr/ui_panels/panels: a container's panels, kept by the engine
--
-- vr/ui_panels/camera = {}: the camera drawing the container, a child of the mesh

local Assets = require("bevy::asset::Assets")
local Image = require("bevy::image::Image")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Plane3d = require("bevy::math::primitives::Plane3d")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

-- `from_rotation_arc` between two level directions turns about Y only, except for exactly
-- opposite ones, which may turn about another axis.
local function in_front(pose, cfg, z)
    local hand = pose.right_position
    local ahead = Vec3.normalize_or_zero({ x = hand.x - pose.hmd_position.x, y = 0, z = hand.z - pose.hmd_position.z })
    if Vec3.length(ahead) == 0 then
        ahead = { x = 0, y = 0, z = -1 }
    end
    local distance = math.max(cfg.min_distance, cfg.distance - z * cfg.z_index_scale)
    return Vec3.add(hand, Vec3.mul(ahead, Vec3.splat(distance))),
        Quat.from_rotation_arc({ x = 0, y = 0, z = 1 }, { x = -ahead.x, y = 0, z = -ahead.z })
end

-- A container is laid out against the window first, and against its image once it targets the
-- panel's camera, so it is built when it has a size and rebuilt when the size changes. The first
-- pose can land after the container's edge, so a player arriving looks at every container. A
-- container whose camera went with a reload still targets it, and a UI root targeting no camera
-- is never laid out again, so it goes back to the window's.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "sidebar/container" },
            changed = { "ComputedNode" },
        },
        with = { "sidebar/container", "ComputedNode" },
        optional = { "vr/ui_panels/panels", "GlobalZIndex", "UiTargetCamera" },
    }],
    Query[{
        with = { "sidebar/container", "ComputedNode" },
        optional = { "vr/ui_panels/panels", "GlobalZIndex", "UiTargetCamera" },
    }],
    Query[{
        ["or"] = {
            added = { "vr/ui_panels", "vr/input/pose" },
        },
        with = { "vr/ui_panels", "vr/input/pose" },
    }],
    Query[{ with = { "vr/ui_panels", "vr/input/pose" } }],
    Query[{
        with = { Mut["vr/ui_panels/panel"], Mut["vr/pointer/target"] },
        optional = { "Children" },
    }],
    Query[{ with = { "vr/ui_panels/camera", Mut["Camera"] } }],
    ResMut[Assets[Image]],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(changed, containers, arrived, players, panels, cameras, images, meshes, materials, commands)
    local player = players:iter()[1]
    local touched = changed:iter()
    if not arrived:is_empty() then
        touched = containers:iter()
    end
    for _, c in ipairs(touched) do
        local size = c:get("ComputedNode").size
        local w, h = math.floor(size.x), math.floor(size.y)
        local panel = panels:iter_many_mut(c:get("vr/ui_panels/panels") or {})[1]
        local built = panel and panel:get("vr/ui_panels/panel")
        if player ~= nil and w > 0 and h > 0 and (built == nil or built.width ~= w or built.height ~= h) then
            local cfg = player:get("vr/ui_panels")
            local image = images:add(Image.new_target_texture(w, h, "bgra8unorm-srgb"))
            local mesh = meshes:add(Plane3d.new({ x = 0, y = 0, z = 1 }, { x = w * cfg.pixels_to_meters / 2, y = h * cfg.pixels_to_meters / 2 }))
            local material = materials:add({ base_color_texture = image, unlit = true })
            if panel == nil then
                local at, facing = in_front(player:get("vr/input/pose"), cfg, c:get("GlobalZIndex") or 0)
                local camera = commands:spawn({
                    ["vr/ui_panels/camera"] = {},
                    Camera2d = {},
                    Camera = { order = cfg.camera_order, target = { Image = image } },
                }):id()
                commands:spawn({
                    ["vr/ui_panels/panel"] = { entity = c:id(), width = w, height = h, image = image },
                    ["vr/pointer/target"] = { image = image, width = w, height = h },
                    ["vr/grabbable/target"] = { face = true },
                    Mesh3d = mesh,
                    ["MeshMaterial3d<StandardMaterial>"] = material,
                    Transform = { translation = at, rotation = facing },
                    Visibility = "Visible",
                    NoFrustumCulling = {},
                }):add_child(camera)
                commands:entity(c:id()):insert({ UiTargetCamera = { entity = camera } })
            else
                local p = panel:get_mut("vr/ui_panels/panel")
                p.width, p.height, p.image = w, h, image
                local target = panel:get_mut("vr/pointer/target")
                target.width, target.height, target.image = w, h, image
                commands:entity(panel:id()):insert({
                    Mesh3d = mesh,
                    ["MeshMaterial3d<StandardMaterial>"] = material,
                })
                for _, cam in ipairs(cameras:iter_many_mut(panel:get("Children") or {})) do
                    cam:get_mut("Camera").target = { Image = image }
                end
            end
        elseif panel == nil and c:has("UiTargetCamera") then
            commands:entity(c:id()):remove("UiTargetCamera")
        end
    end
end):in_set("vr/ui_panels/build")

-- A hidden panel stops its camera, and answers no pointer, as the ray only meets what is seen.
app:add_systems(First, {
    Query[{
        changed = { "Node" },
        with = { "sidebar/container", "Node", "vr/ui_panels/panels" },
        optional = { "GlobalZIndex" },
    }],
    Query[{ with = { "vr/ui_panels", "vr/input/pose" } }],
    Query[{
        with = { "vr/ui_panels/panel", Mut["Visibility"], Mut["Transform"] },
        optional = { "Children" },
    }],
    Query[{ with = { "vr/ui_panels/camera", Mut["Camera"] } }],
}, function(containers, players, panels, cameras)
    local player = players:iter()[1]
    for _, c in ipairs(containers:iter()) do
        local shown = c:get("Node").display ~= "None"
        for _, panel in ipairs(panels:iter_many_mut(c:get("vr/ui_panels/panels"))) do
            local was = panel:get("Visibility") ~= "Hidden"
            if shown and not was and player ~= nil then
                local t = panel:get_mut("Transform")
                t.translation, t.rotation = in_front(player:get("vr/input/pose"), player:get("vr/ui_panels"), c:get("GlobalZIndex") or 0)
            end
            if shown ~= was then
                panel:get_mut("Visibility"):set_if_neq(shown and "Visible" or "Hidden")
                for _, cam in ipairs(cameras:iter_many_mut(panel:get("Children") or {})) do
                    cam:get_mut("Camera").is_active = shown
                end
            end
        end
    end
end):in_set("vr/ui_panels/show"):after("vr/ui_panels/build")

-- The panels are world roots, so they do not go with the player.
app:add_systems(First, {
    Query[{ removed = { "vr/ui_panels" } }],
    Query[{ with = { "vr/ui_panels/panel" } }],
    Query[{ with = { "sidebar/container", "vr/ui_panels/panels" } }],
    Commands,
}, function(removed, panels, containers, commands)
    for _, _ in ipairs(removed:iter()) do
        for _, p in ipairs(panels:iter()) do
            commands:entity(p:id()):try_despawn()
        end
        for _, c in ipairs(containers:iter()) do
            commands:entity(c:id()):try_remove("UiTargetCamera")
        end
        break
    end
end):in_set("vr/ui_panels/removed")

return {
    defaults = {
        ["vr/ui_panels"] = {
            pixels_to_meters = 0.0008,
            distance = 0.6,
            min_distance = 0.35,
            z_index_scale = 0.0003,
            camera_order = -200,
        },
    },
    relationships = {
        ["vr/ui_panels/panel"] = { target = "vr/ui_panels/panels", linked_spawn = true },
    },
}
