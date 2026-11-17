-- The owning client places an entity: while it carries `placement`, it follows where this client's
-- player points, the VR pointer's ray or else the mouse, onto the first thing the ray meets: a
-- collider or a visible mesh, skipping what is not pickable (`Pickable.is_hoverable = false`).
-- Left click confirms; Escape (B in VR) or a right click cancels.
--
-- placement = {}: on the placed entity, synced with client authority, as is its Transform
--
-- What this client owns is what its own nets' `core/net/owns` list: the placed entity (a
-- prediction, owned by the world net) and its player.
--
-- Bindings, on this client's player while it owns a placing entity:
-- input/ui.placement = { confirm = { button = "Left" }, cancel = { key = "Escape", button = "Right", take = true } }

local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")
local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local Vec3 = require("bevy::math::Vec3")

--- The rows of `q` (its owner named) that belong to this client.
local function mine(own, q)
    local out = {}
    for _, e in ipairs(q:iter()) do
        local owner = e:get("core/net/owner")
        if owner ~= nil and own:contains(owner) then out[#out + 1] = e end
    end
    return out
end

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "placement", "core/net/owner" },
            changed = { "core/net/owner" },
        },
        with = { "placement", "core/net/owner" },
    }],
    Query[{
        ["or"] = {
            added = { "input", "core/net/owner" },
            changed = { "core/net/owner" },
        },
        with = { "input", "core/net/owner" },
    }],
    Query[{ with = { "placement" } }],
    Query[{ with = { "input" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(started, arrived, placing, players, own, commands)
    local placed = false
    for _, n in ipairs(own:iter()) do
        placed = placed or placing:iter_many(n:get("core/net/owns"))[1] ~= nil
    end
    if not placed then return end
    local function bind(e)
        commands:entity(e:id()):entry("input/ui"):or_default():and_modify(function(ui)
            ui.placement = {
                confirm = { button = "Left" },
                cancel = { key = "Escape", button = "Right", take = true },
            }
        end)
    end
    if #mine(own, started) > 0 then
        for _, n in ipairs(own:iter()) do
            for _, e in ipairs(players:iter_many(n:get("core/net/owns"))) do
                bind(e)
            end
        end
    else
        for _, e in ipairs(mine(own, arrived)) do
            bind(e)
        end
    end
end):in_set("placement/bind")

-- Cancel acts on its release, so its Escape is let go before the binding goes and the key is
-- never seen by the mode's other bindings of it.
app:add_systems(First, {
    Query[{ removed = { "placement" } }],
    Query[{ with = { "placement" } }],
    Query[{ with = { "input", "input/ui" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(ended, placing, players, own, commands)
    for _, _ in ipairs(ended:iter()) do
        local placed = false
        for _, n in ipairs(own:iter()) do
            placed = placed or placing:iter_many(n:get("core/net/owns"))[1] ~= nil
        end
        if not placed then
            for _, n in ipairs(own:iter()) do
                for _, e in ipairs(players:iter_many(n:get("core/net/owns"))) do
                    commands:entity(e:id()):entry("input/ui"):and_modify(function(ui)
                        ui.placement = nil
                    end)
                end
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
    Query[{ with = { "placement", Mut["Transform"] } }],
    Query[{
        with = { "input" },
        optional = { "vr/pointer/ray", "Children" },
    }],
    Query[{ with = { "camera/3d/eye", "Camera", "GlobalTransform" } }],
    Query[{ with = { "Window" } }],
    Query[{ with = { "Pickable" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
}, function(rapier, ray_cast, placing, players, eyes, windows, pickables, own)
    for _, n in ipairs(own:iter()) do
        for _, player in ipairs(players:iter_many(n:get("core/net/owns"))) do
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
                for _, n in ipairs(own:iter()) do
                    for _, p in ipairs(placing:iter_many_mut(n:get("core/net/owns"))) do
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
            end
            -- the first player only
            return
        end
    end
end):in_set("placement/follow")

app:add_systems(Update, {
    Query[{
        added = { "input/ui/placement/confirm" },
        with = { "core/net/owner" },
    }],
    Query[{ with = { "placement" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(pressed, placing, own, commands)
    for _, _ in ipairs(mine(own, pressed)) do
        for _, n in ipairs(own:iter()) do
            for _, p in ipairs(placing:iter_many(n:get("core/net/owns"))) do
                commands:entity(p:id()):remove("placement")
            end
        end
        break
    end
end):in_set("placement/confirm")

-- A despawn here asks the server, which despawns it everywhere.
app:add_systems(Update, {
    Query[{
        removed = { "input/ui/placement/cancel" },
        with = { "core/net/owner" },
    }],
    Query[{ with = { "placement" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(released, placing, own, commands)
    for _, _ in ipairs(mine(own, released)) do
        for _, n in ipairs(own:iter()) do
            for _, p in ipairs(placing:iter_many(n:get("core/net/owns"))) do
                commands:entity(p:id()):try_despawn()
            end
        end
        break
    end
end):in_set("placement/cancel")
