-- The player spawner, on a world's server: a player for each connected client, on a free, ready
-- spawn point that the world's map carries, despawned when the client leaves, and linked to its
-- spawner. A client waits with no player until a point is ready. A game's spawner has this mod as
-- its base and adds what its players need beyond it. Missing fields get defaults when it is added.
--
-- The owning client drives its player's Transform, as there is no client prediction
-- yet: `Transform` syncs with client authority into the
-- `core/net/sync/Transform` shadow seeded here, which `player` follows on the server. The
-- server's body is kinematic; the owner switches its own to dynamic (`player`).
--
-- player/spawner = {
--     lift = <metres above a point, along its up, that a player's body is placed>,
-- }
--
-- player/spawner/point = {}: on a map's node, with its Name and its place
-- player/spawner/player = { entity = <its spawner> }: on a player
-- player/spawner/players: a spawner's players, kept by the engine

local Quat = require("bevy::math::Quat")
local TransformSystems = require("bevy::transform::TransformSystems")

-- After Bevy's transform propagation: a point spawned this frame has its world place only then. A
-- player's place and camera ride its spawn, as the owning client keeps its own after that; so do
-- the camera's sync and that of the timers a handed player carries (a portal's crossing timer),
-- which its client must have from the first frame. A spawner added later serves the clients
-- already connected: a condition's first run sees every connection as changed. Claims go by Name,
-- which a re-export keeps.
app:add_systems(PostUpdate, {
    Query[{ with = { "core/net/connection" } }],
    Query[{ with = { "player", "core/net/owner" } }],
    Query[{ with = { "player/spawner/point", "Name", "GlobalTransform" } }],
    Query[{
        with = { "SceneRoot" },
        optional = { "collider/status" },
    }],
    Query[{ with = { "player/spawner" } }],
    Commands,
}, function(connections, players, points, roots, spawners, commands)
    local held, owned = {}, {}
    for _, p in ipairs(players:iter()) do
        local player = p:get("player")
        local owner = p:get("core/net/owner")
        if player.spawn_point ~= nil then
            held[player.spawn_point] = (held[player.spawn_point] or 0) + 1
        end
        owned[owner.client_id] = true
    end
    local ready = {}
    for _, point in ipairs(points:iter()) do
        local root = roots:iter_many(roots:iter_ancestors(point:id()))[1]
        local status = root and root:get("collider/status")
        if root == nil or (status ~= nil and status.state == "done") then
            local name = point:get("Name")
            ready[#ready + 1] = { point = point, name = name.name }
        end
    end
    table.sort(ready, function(a, b) return a.name < b.name end)

    local spawner = spawners:iter()[1]
    local waiting = 0
    for _, c in ipairs(connections:iter()) do
        local connection = c:get("core/net/connection")
        if spawner and not connection.observer and not owned[connection.client_id] then
            local s = spawner:get("player/spawner")
            local handed = connection.synced_state or {}
            local stood = handed.Transform
            local at, facing, camera, claim
            if stood and stood.translation then
                at = stood.translation
                facing = stood.rotation or { x = 0, y = 0, z = 0, w = 1 }
                camera = handed.camera
            else
                for _, r in ipairs(ready) do
                    if claim == nil or (held[r.name] or 0) < (held[claim.name] or 0) then
                        claim = r
                    end
                end
                if claim ~= nil then
                    at = claim.point.GlobalTransform:transform_point({ x = 0, y = s.lift, z = 0 })
                    facing = { x = 0, y = 0, z = 0, w = 1 }
                    -- The body's rotation is locked: the camera's yaw is what turns a player.
                    camera = { yaw = Quat.to_euler(claim.point.GlobalTransform:compute_transform().rotation, "YXZ")[1] }
                    held[claim.name] = (held[claim.name] or 0) + 1
                end
            end
            if at == nil then
                waiting = waiting + 1
            else
                commands:spawn({
                    player = { client_id = connection.client_id, spawn_point = claim and claim.name },
                    ["player/spawner/player"] = { entity = spawner:id() },
                    Transform = { translation = at, rotation = facing },
                    RigidBody3d = "KinematicPositionBased",
                    Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
                    LockedAxes3d = "ROTATION_LOCKED",
                    Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
                    camera = camera,
                    cooldown = handed.cooldown,
                    ["core/net/owner"] = { client_id = connection.client_id },
                    ["core/net/peer/share"] = { stable_id = "player_" .. tostring(connection.client_id) },
                    ["core/net/sync/Transform"] = { translation = at, rotation = facing },
                    ["core/net/sync"] = {
                        Transform = { authority = "client", reliable = false },
                        RigidBody3d = { authority = "server" },
                        Collider3d = { authority = "server" },
                        LockedAxes3d = { authority = "server" },
                        camera = camera and { authority = "client", target = "owner" } or nil,
                        cooldown = handed.cooldown and { authority = "server", target = "owner" } or nil,
                    },
                    ["core/script/owner"] = false,
                })
                owned[connection.client_id] = true
            end
        end
    end
    if waiting > 0 then
        print(string.format("[PLAYER/SPAWNER] %d client(s) waiting for a ready player/spawner/point", waiting))
    end
end):in_set("player/spawner/spawn"):after(TransformSystems.Propagate):run_if({
    Query[{ changed = { "core/net/connection" } }],
    Query[{ changed = { "collider/status" } }],
    Query[{ added = { "player/spawner/point" } }],
}, function(connections, statuses, points)
    return not (connections:is_empty() and statuses:is_empty() and points:is_empty())
end)

-- A client that left, or went back to only watching: its player goes. A connection whose
-- entity is gone has no row in `connected`.
app:add_systems(PreUpdate, {
    Query[{
        ["or"] = {
            changed = { "core/net/connection" },
            removed = { "core/net/connection" },
        },
        optional = { "core/net/connection" },
    }],
    Query[{ with = { "core/net/connection" } }],
    Query[{ with = { "player", "core/net/owner" } }],
    Commands,
}, function(connections, connected, players, commands)
    for _, c in ipairs(connections:iter()) do
        local connection = c:get("core/net/connection")
        if connection ~= nil and (connection.observer or not connected:contains(c:id())) then
            for _, p in ipairs(players:iter()) do
                if p:get("core/net/owner").client_id == connection.client_id then
                    commands:entity(p:id()):despawn()
                end
            end
        end
    end
end):in_set("player/spawner/left")

-- A player handed to another world takes its whole camera in the switch itself, which core sends
-- in this same frame: the target's mirror of the player may be an update behind. Only the camera's
-- entry is written: the portal handing it over puts its timer beside it.
app:add_systems(PostUpdate, {
    Query[{
        added = { "core/net/peer/switch" },
        with = { "player", Mut["core/net/peer/share"] },
        optional = { "camera" },
    }],
}, function(leaving)
    for _, p in ipairs(leaving:iter_mut()) do
        local camera = p:get("camera")
        if camera ~= nil then
            local share = p:get_mut("core/net/peer/share")
            local carried = share.transfer_data or {}
            carried.camera = camera
            share.transfer_data = carried
        end
    end
end):in_set("player/spawner/left"):before("core/net/peer/authority_switch")

return {
    defaults = {
        ["player/spawner"] = {
            lift = 1,
        },
    },
    relationships = {
        -- A player lives as long as its client stays, so its spawner going leaves it, unlinked.
        ["player/spawner/player"] = { target = "player/spawner/players", linked_spawn = false },
    },
}
