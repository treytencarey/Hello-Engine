-- The sidebar as a panel in the world for this client's own player in VR. The panel is a mesh
-- carrying `ui/screen`, which draws UI into an image on it, by a camera of its own, and makes it a
-- pointer target; the sidebar's container is pointed at that camera, and the screen's own root is
-- left empty. The grip can carry it. Each time the sidebar opens, the panel is placed in front of
-- the right hand again, facing the head.
--
-- vr/ui_panels = {
--     pixels_to_meters = <metres per pixel of the panel>,
--     distance = <metres in front of the hand>,
--     min_distance = <the least it comes to>,
--     z_index_scale = <metres nearer for each step of the container's GlobalZIndex>,
-- }
--
-- vr/ui_panels/panel = {
--     entity = <the container>,
--     width, height = <pixels of its image>,
-- }: on the mesh
--
-- vr/ui_panels/panels: a container's panels, kept by the engine

local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
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
    Query[{ with = { Mut["vr/ui_panels/panel"] } }],
    ResMut[Assets[Mesh]],
    Commands,
}, function(changed, containers, arrived, players, panels, meshes, commands)
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
            local mesh = meshes:add(Plane3d.new({ x = 0, y = 0, z = 1 }, { x = w * cfg.pixels_to_meters / 2, y = h * cfg.pixels_to_meters / 2 }))
            if panel == nil then
                local at, facing = in_front(player:get("vr/input/pose"), cfg, c:get("GlobalZIndex") or 0)
                commands:spawn({
                    ["vr/ui_panels/panel"] = { entity = c:id(), width = w, height = h },
                    ["ui/screen"] = { width = w, height = h },
                    ["vr/grabbable/target"] = { face = true },
                    Mesh3d = mesh,
                    Transform = { translation = at, rotation = facing },
                    Visibility = "Visible",
                })
            else
                local p = panel:get_mut("vr/ui_panels/panel")
                p.width, p.height = w, h
                -- Bevy computes a mesh's `Aabb` only while it has none, and the ray cast and culling
                -- read it, so the new mesh's is computed again.
                commands:entity(panel:id()):insert({ Mesh3d = mesh, ["ui/screen"] = { width = w, height = h } })
                commands:entity(panel:id()):remove("Aabb")
            end
        elseif panel == nil and c:has("UiTargetCamera") then
            commands:entity(c:id()):remove("UiTargetCamera")
        end
    end
end):in_set("vr/ui_panels/build")

-- The panel's screen camera, once `ui/screen` made it: the container draws through it.
app:add_systems(First, {
    Query[{ added = { "ui/screen/camera" }, with = { "ChildOf" } }],
    Query[{ with = { "vr/ui_panels/panel" } }],
    Commands,
}, function(cameras, panels, commands)
    for _, cam in ipairs(cameras:iter()) do
        local panel = panels:iter_many({ cam:get("ChildOf") })[1]
        if panel ~= nil then
            commands:entity(panel:get("vr/ui_panels/panel").entity):insert({ UiTargetCamera = { entity = cam:id() } })
        end
    end
end):in_set("vr/ui_panels/target")

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
    Query[{ with = { "ui/screen/camera", Mut["Camera"] } }],
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
        },
    },
    relationships = {
        ["vr/ui_panels/panel"] = { target = "vr/ui_panels/panels", linked_spawn = true },
    },
}
