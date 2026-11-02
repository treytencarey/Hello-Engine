-- A top-down 2D camera: an eye, a Camera2d child of the carrier, kept `z` above it and
-- scaled by the carrier's `camera.distance` (1 is 1:1), which the scroll wheel changes. The eye follows
-- the carrier but not its rotation (`transform/follow`). Only the local player's carrier gets
-- an eye. It turns off while the player is in another world, goes with the carrier when it
-- despawns, and is despawned when `camera/2d` is removed.
--
-- camera/2d = {
--     zoom_step = <distance per unit of scroll>,
--     min_distance = <the closest view>,
--     max_distance = <the farthest view>,
--     z = <how far above the carrier the eye sits>,
-- }
--
-- camera/2d/eye = {}

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/2d", "camera", "core/net/local" },
        },
        with = { "camera/2d", "camera", "core/net/local" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/2d/eye", Mut["Camera"] },
    }],
    Commands,
}, function(carriers, all_eyes, commands)
    for _, e in ipairs(carriers:iter()) do
        local cam = e:get("camera")
        local c2d = e:get("camera/2d")
        local eyes = all_eyes:iter_many_mut(e:get("Children") or {})
        for _, eye in ipairs(eyes) do
            eye:patch({ Camera = { is_active = true } })
        end
        if #eyes == 0 then
            -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which
            -- can be a frame later; the eye starts 1:1 and is scaled when they arrive.
            local scale = cam.distance or 1
            local eye = commands:spawn({
                Camera2d = {},
                Camera = { order = 0, is_active = true },
                Transform = { scale = { x = scale, y = scale, z = 1 } },
                IsDefaultUiCamera = true,
                ["transform/follow"] = {
                    rotation = { x = 0, y = 0, z = 0, w = 1 },
                    offset = { x = 0, y = 0, z = c2d.z },
                },
                ["camera/2d/eye"] = {},
            }):id()
            commands:entity(e:id()):add_child(eye)
        end
    end
end):in_set("camera/2d/spawn")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/2d", "core/net/local", "input" },
        },
        with = { "camera/2d", "core/net/local" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        commands:entity(e:id()):patch({
            ["input/game"] = {
                camera_2d = {
                    zoom = { scroll = true },
                },
            },
        })
    end
end):in_set("camera/2d/bind")

-- The player left for another world: its eye stops rendering this one.
app:add_systems(First, {
    Query[{
        removed = { "core/net/local" },
        with = { "camera/2d" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/2d/eye", Mut["Camera"] },
    }],
}, function(carriers, all_eyes)
    for _, e in ipairs(carriers:iter()) do
        for _, eye in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
            eye:patch({ Camera = { is_active = false } })
        end
    end
end):in_set("camera/2d/teardown")

app:add_systems(First, {
    Query[{
        removed = { "camera/2d" },
        with = { "input/game" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        -- `removed` also fires on despawn, and a patch to an entity that is gone fails.
        local carrier = commands:get_entity(e:id())
        if carrier ~= nil then
            carrier:patch({ ["input/game"] = { camera_2d = null } })
        end
    end
end):in_set("camera/2d/remove")

app:add_systems(Update, {
    Query[{
        changed = { "input/game/camera_2d/zoom" },
        with = { Mut["camera"], "camera/2d" },
    }],
}, function(carriers)
    for _, e in ipairs(carriers:iter_mut()) do
        local cam = e:get("camera")
        local c2d = e:get("camera/2d")
        local zoom = e:get("input/game/camera_2d/zoom")
        -- `camera` arrives as `{}` and gets its defaults when its own mod loads, which can
        -- be a frame later. Filling them is a change to `camera`, which runs this again.
        if cam.distance ~= nil then
            local distance = cam.distance - zoom.dy * c2d.zoom_step
            e:patch({
                camera = {
                    distance = math.max(c2d.min_distance, math.min(c2d.max_distance, distance)),
                },
            })
        end
    end
end):in_set("camera/2d/zoom")

app:add_systems(Update, {
    Query[{
        ["or"] = {
            changed = { "camera", "camera/2d" },
        },
        with = { "camera", "camera/2d" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/2d/eye", Mut["Transform"], Mut["transform/follow"] },
    }],
}, function(carriers, all_eyes)
    for _, e in ipairs(carriers:iter()) do
        local cam = e:get("camera")
        local c2d = e:get("camera/2d")
        if cam.distance ~= nil then
            for _, eye in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
                eye:patch({
                    Transform = { scale = { x = cam.distance, y = cam.distance, z = 1 } },
                    ["transform/follow"] = {
                        rotation = { x = 0, y = 0, z = 0, w = 1 },
                        offset = { x = 0, y = 0, z = c2d.z },
                    },
                })
            end
        end
    end
end):in_set("camera/2d/aim"):after("camera/2d/zoom")

return {
    base = "camera",
    defaults = {
        ["camera/2d"] = {
            zoom_step = 0.1,
            min_distance = 0.25,
            max_distance = 4,
            z = 1000,
        },
    },
}
