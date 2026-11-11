-- The owning client places an entity: while it carries `placement`, it follows where this client's
-- player points, the VR pointer's ray or else the mouse, onto the first thing the ray meets: a
-- collider or a visible mesh, skipping what is not pickable (`Pickable.is_hoverable = false`).
-- Left click confirms; Escape (B in VR) or a right click cancels.
--
-- placement = {}: on the placed entity, synced with client authority, as is its Transform
--
-- Bindings, on this client's player while it owns a placing entity:
-- input/ui.placement = { confirm = { button = "Left" }, cancel = { key = "Escape", button = "Right", take = true } }

local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")
local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local Vec3 = require("bevy::math::Vec3")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "placement", "core/net/local" },
        },
        with = { "placement", "core/net/local" },
    }],
    Query[{
        ["or"] = {
            added = { "input", "core/net/local" },
        },
        with = { "input", "core/net/local" },
    }],
    Query[{ with = { "placement", "core/net/local" } }],
    Query[{ with = { "input", "core/net/local" } }],
    Commands,
}, function(started, arrived, placing, players, commands)
    local binding = arrived:iter()
    if not started:is_empty() then
        binding = players:iter()
    end
    if placing:is_empty() then
        binding = {}
    end
    for _, e in ipairs(binding) do
        commands:entity(e:id()):entry("input/ui"):or_default():and_modify(function(ui)
            ui.placement = {
                confirm = { button = "Left" },
                cancel = { key = "Escape", button = "Right", take = true },
            }
        end)
    end
end):in_set("placement/bind")

-- Cancel acts on its release, so its Escape is let go before the binding goes and the key is
-- never seen by the mode's other bindings of it.
app:add_systems(First, {
    Query[{ removed = { "placement" } }],
    Query[{ with = { "placement", "core/net/local" } }],
    Query[{ with = { "input", "input/ui", "core/net/local" } }],
    Commands,
}, function(ended, placing, players, commands)
    for _, _ in ipairs(ended:iter()) do
        if placing:is_empty() then
            for _, e in ipairs(players:iter()) do
                commands:entity(e:id()):entry("input/ui"):and_modify(function(ui)
                    ui.placement = nil
                end)
            end
        end
        break
    end
end):in_set("placement/unbind")

-- Follows, so it polls. The ray skips the placed entity and the player, with what hangs under
-- each: a ray from the hand starts inside the player's own body. In a world VM the camera draws
-- into an image the size of the window's physical pixels, so the cursor is read in those.
-- `viewport_to_world` reads the eye's own `GlobalTransform` and takes only the cursor. A room
-- may be a mesh with no collider, so both rays are cast and the nearer hit wins.
app:add_systems(Update, {
    ReadRapierContext,
    MeshRayCast,
    Query[{ with = { "placement", "core/net/local", Mut["Transform"] } }],
    Query[{
        with = { "input", "core/net/local" },
        optional = { "vr/pointer/ray", "Children" },
    }],
    Query[{ with = { "camera/3d/eye", "Camera", "GlobalTransform" } }],
    Query[{ with = { "Window" } }],
    Query[{ with = { "Pickable" } }],
}, function(rapier, ray_cast, placing, players, eyes, windows, pickables)
    for _, player in ipairs(players:iter()) do
        local ray = player:get("vr/pointer/ray")
        local eye = eyes:iter_many(player:get("Children") or {})[1]
        local window = windows:iter()[1]
        if ray == nil and eye ~= nil and window ~= nil then
            local cursor = window.Window:physical_cursor_position()
            -- It fails while the camera has no target size yet.
            local ok, seen = pcall(function() return cursor ~= nil and eye.Camera:viewport_to_world(cursor) or nil end)
            if ok and seen ~= nil then
                -- A `Dir3` may read back as its one field.
                local direction = seen.direction[1] or seen.direction
                ray = { origin = seen.origin, direction = direction }
            end
        end
        if ray ~= nil then
            local me = player:id()
            for _, p in ipairs(placing:iter_mut()) do
                local placed = p:id()
                local function passes(entity)
                    local root = players:root_ancestor(entity)
                    local pick = pickables:get(entity)
                    return root ~= placed and root ~= me
                        and not (pick ~= nil and pick:get("Pickable").is_hoverable == false)
                end
                local hit = rapier:cast_ray(ray.origin, ray.direction, 100, true, { predicate = passes })
                local far = hit ~= nil and hit.toi or nil
                local mesh = ray_cast:cast_ray(ray, { visibility = "Visible", filter = passes })[1]
                local near = mesh ~= nil and mesh.ray_mesh_hit.distance or nil
                if near ~= nil and (far == nil or near < far) then far = near end
                if far ~= nil then
                    p:get_mut("Transform").translation = Vec3.add(ray.origin, Vec3.mul(ray.direction, Vec3.splat(far)))
                end
            end
        end
        break
    end
end):in_set("placement/follow")

app:add_systems(Update, {
    Query[{
        added = { "input/ui/placement/confirm" },
        with = { "core/net/local" },
    }],
    Query[{ with = { "placement", "core/net/local" } }],
    Commands,
}, function(pressed, placing, commands)
    for _, _ in ipairs(pressed:iter()) do
        for _, p in ipairs(placing:iter()) do
            commands:entity(p:id()):remove("placement")
        end
        break
    end
end):in_set("placement/confirm")

-- A despawn here asks the server, which despawns it everywhere.
app:add_systems(Update, {
    Query[{
        removed = { "input/ui/placement/cancel" },
        with = { "core/net/local" },
    }],
    Query[{ with = { "placement", "core/net/local" } }],
    Commands,
}, function(released, placing, commands)
    for _, _ in ipairs(released:iter()) do
        for _, p in ipairs(placing:iter()) do
            commands:entity(p:id()):try_despawn()
        end
        break
    end
end):in_set("placement/cancel")
