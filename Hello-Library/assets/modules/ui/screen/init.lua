-- A UI drawn on a mesh: `ui/screen` gives a mesh an image of `width` x `height` pixels, a camera of
-- its own drawing UI into it (a child of the mesh), a UI root on that camera, the image unlit on the
-- mesh, and `pointer/target`, so a pointer's ray works it. A mod puts its UI under the root, or
-- points a root of its own at the camera. A size changed builds a new image for the same camera
-- and root.
--
-- ui/screen = { width = <pixels>, height = <pixels> }: on a mesh
--
-- ui/screen/camera = {}: the camera drawing the screen, a child of the mesh
--
-- ui/screen/root = {}: the screen's UI root, `width` x `height`, on that camera; a root of its own,
-- as a UI node under a scene is not laid out

local Assets = require("bevy::asset::Assets")
local Image = require("bevy::image::Image")
local StandardMaterial = require("bevy::pbr::StandardMaterial")

-- Its camera draws before the window's.
local CAMERA_ORDER = -200

app:add_systems(First, {
    Query[{
        ["or"] = { added = { "ui/screen" }, changed = { "ui/screen" } },
        optional = { "Children", "pointer/target" },
    }],
    Query[{ with = { "ui/screen/camera", Mut["Camera"] } }],
    Query[{ with = { "ui/screen/root", "UiTargetCamera", Mut["Node"] } }],
    ResMut[Assets[Image]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(screens, cameras, roots, images, materials, commands)
    for _, e in ipairs(screens:iter()) do
        local s = e:get("ui/screen")
        local w, h = math.floor(s.width or 0), math.floor(s.height or 0)
        local target = e:get("pointer/target")
        if w > 0 and h > 0 and (target == nil or target.width ~= w or target.height ~= h) then
            local image = images:add(Image.new_target_texture(w, h, "bgra8unorm-srgb"))
            local camera = cameras:iter_many_mut(e:get("Children") or {})[1]
            if camera == nil then
                local id = commands:spawn({
                    ["ui/screen/camera"] = {},
                    Camera2d = {},
                    Camera = { order = CAMERA_ORDER, target = { Image = image } },
                    ChildOf = e:id(),
                }):id()
                commands:spawn({
                    ["ui/screen/root"] = {},
                    Node = { width = { Px = w }, height = { Px = h } },
                    -- The root covers the image: it must not stand between the pointer and its UI.
                    Pickable = { should_block_lower = false, is_hoverable = false },
                    UiTargetCamera = { entity = id },
                })
            else
                camera:get_mut("Camera").target = { Image = image }
                for _, r in ipairs(roots:iter_mut()) do
                    if r:get("UiTargetCamera") == camera:id() then
                        local node = r:get_mut("Node")
                        node.width, node.height = { Px = w }, { Px = h }
                    end
                end
            end
            commands:entity(e:id()):insert({
                ["MeshMaterial3d<StandardMaterial>"] = materials:add({ base_color_texture = image, unlit = true }),
                ["pointer/target"] = { image = image, width = w, height = h },
            })
        end
    end
end):in_set("ui/screen/build")

-- `pointer/target` is a part of `pointer`, which the registry takes off every entity when the
-- pointer's last source goes: a screen that stays builds again, and has it back.
app:add_systems(First, {
    Query[{ removed = { "pointer/target" } }],
    Query[{ with = { "ui/screen" } }],
    Commands,
}, function(removed, screens, commands)
    local ids = {}
    for _, e in ipairs(removed:iter()) do ids[#ids + 1] = e:id() end
    for _, e in ipairs(screens:iter_many(ids)) do
        commands:entity(e:id()):insert({ ["ui/screen"] = e:get("ui/screen") })
    end
end):in_set("ui/screen/target_back")

-- A screen's camera gone (its mesh gone, or `ui/screen` taken off): its root goes too.
app:add_systems(First, {
    Query[{ removed = { "ui/screen/camera" } }],
    Query[{ with = { "ui/screen/root", "UiTargetCamera" } }],
    Query[{ with = { "ui/screen/camera" } }],
    Commands,
}, function(removed, roots, cameras, commands)
    if removed:is_empty() then return end
    for _, r in ipairs(roots:iter()) do
        if not cameras:contains(r:get("UiTargetCamera")) then
            commands:entity(r:id()):try_despawn()
        end
    end
end):in_set("ui/screen/removed")

-- `ui/screen` taken off a mesh that stays: what it added goes.
app:add_systems(First, {
    Query[{ removed = { "ui/screen" } }],
    Query[{ with = { "ui/screen/camera" } }],
    Query[{ with = { "Children" } }],
    Commands,
}, function(removed, cameras, parents, commands)
    for _, e in ipairs(removed:iter()) do
        local mesh = commands:get_entity(e:id())
        if mesh ~= nil then
            mesh:try_remove("pointer/target", "MeshMaterial3d<StandardMaterial>")
            local p = parents:iter_many({ e:id() })[1]
            for _, c in ipairs(cameras:iter_many(p and p:get("Children") or {})) do
                commands:entity(c:id()):try_despawn()
            end
        end
    end
end):in_set("ui/screen/taken_off"):before("ui/screen/removed")
