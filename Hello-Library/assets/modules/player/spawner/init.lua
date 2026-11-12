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
-- player/spawner/look = {
--     yaw = <the camera's yaw less the body's facing, radians>,
--     pitch = <the camera's pitch, radians>,
-- }: what a handed player looks with, in the switch; in place, core sets it on the player

local Quat = require("bevy::math::Quat")
local TransformSystems = require("bevy::transform::TransformSystems")

-- The first ready point by name that nobody holds, else the least held.
local function least_held(ready, held)
    local claim
    for _, r in ipairs(ready) do
        if claim == nil or (held[r.name] or 0) < (held[claim.name] or 0) then
            claim = r
        end
    end
    return claim
end

-- After Bevy's transform propagation: a point spawned this frame has its world place only then. A
-- player's place and camera ride its spawn, as the owning client keeps its own after that; so do
-- the camera's sync and that of the timers a handed player carries (a portal's crossing timer),
-- which its client must have from the first frame. A spawner added later serves the clients
-- already connected: a condition's first run sees every connection as changed. Claims go by Name,
-- which a re-export keeps. A player whose claim names no point, as after a re-export that renamed
-- or deleted it, or that arrived when none was ready, claims the least held ready point.
app:add_systems(PostUpdate, {
    Query[{ with = { "core/net/connection" } }],
    Query[{
        with = { Mut["player"], "core/net/owner" },
        optional = { "core/net/peer/mirror" },
    }],
    Query[{ with = { "player/spawner/point", "Name", "GlobalTransform" } }],
    Query[{
        with = { "SceneRoot" },
        optional = { "collider/status" },
    }],
    Query[{ with = { "player/spawner" } }],
    Commands,
}, function(connections, players, points, roots, spawners, commands)
    local held, owned, named = {}, {}, {}
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
        local name = point:get("Name")
        named[name.name] = true
        local root = roots:iter_many(roots:iter_ancestors(point:id()))[1]
        local status = root and root:get("collider/status")
        if root == nil or (status ~= nil and status.state == "done") then
            ready[#ready + 1] = { point = point, name = name.name }
        end
    end
    table.sort(ready, function(a, b) return a.name < b.name end)

    for _, p in ipairs(players:iter_mut()) do
        local was = p:get("player").spawn_point
        if not p:has("core/net/peer/mirror") and (was == nil or not named[was]) then
            local claim = least_held(ready, held)
            if claim ~= nil then
                p:get_mut("player").spawn_point = claim.name
                held[claim.name] = (held[claim.name] or 0) + 1
            end
        end
    end

    local spawner = spawners:iter()[1]
    local waiting = 0
    for _, c in ipairs(connections:iter()) do
        local connection = c:get("core/net/connection")
        if spawner and not connection.observer and not owned[connection.client_id] then
            local s = spawner:get("player/spawner")
            local handed = connection.synced_state or {}
            local stood = handed.Transform
            local look = handed["player/spawner/look"]
            local at, facing, camera
            local claim = least_held(ready, held)
            -- A handed player claims a point like any other, and arrives where it stood, with its
            -- whole camera. The body may arrive turned (a door's place), so only the camera's yaw
            -- is taken from the look, which crossed relative to the body, turned by the facing it
            -- arrives with. A copy: the table `get` answers is the connection's own value.
            if stood and stood.translation then
                at = stood.translation
                facing = stood.rotation or { x = 0, y = 0, z = 0, w = 1 }
                if handed.camera ~= nil then
                    camera = {}
                    for field, value in pairs(handed.camera) do
                        camera[field] = value
                    end
                end
                if look ~= nil then
                    camera = camera or { pitch = look.pitch }
                    camera.yaw = (look.yaw or 0) + Quat.to_euler(facing, "YXZ")[1]
                end
            elseif claim ~= nil then
                at = claim.point.GlobalTransform:transform_point({ x = 0, y = s.lift, z = 0 })
                facing = { x = 0, y = 0, z = 0, w = 1 }
                -- The body's rotation is locked: the camera's yaw is what turns a player.
                camera = { yaw = Quat.to_euler(claim.point.GlobalTransform:compute_transform().rotation, "YXZ")[1] }
            end
            if claim ~= nil and at ~= nil then
                held[claim.name] = (held[claim.name] or 0) + 1
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
                    -- The portal's switch, which its client follows, is listed here: a name added
                    -- to the sync in the switch's own frame is not sent until the next.
                    ["core/net/sync"] = {
                        Transform = { authority = "client", reliable = false },
                        RigidBody3d = { authority = "server" },
                        Collider3d = { authority = "server" },
                        LockedAxes3d = { authority = "server" },
                        camera = camera and { authority = "client", target = "owner" } or nil,
                        cooldown = handed.cooldown and { authority = "server", target = "owner" } or nil,
                        ["core/net/peer/switch"] = { authority = "server", target = "owner" },
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

-- A player handed to another world takes its body's place, its whole camera and its look in the
-- switch itself, which core sends in this same frame: the target's mirror of the player may be an
-- update behind. Core places the body at a door's place there, which may turn it; the camera's yaw
-- does not turn with it, so the look carries the yaw relative to the body, which holds in any
-- frame. Only these entries are written: the portal handing it over puts its timer beside them.
app:add_systems(PostUpdate, {
    Query[{
        added = { "core/net/peer/switch" },
        with = { "player", Mut["core/net/peer/share"] },
        optional = { "Transform", "camera" },
    }],
}, function(leaving)
    for _, p in ipairs(leaving:iter_mut()) do
        local share = p:get_mut("core/net/peer/share")
        local carried = share.transfer_data or {}
        if p:has("camera") then
            carried.camera = p:get("camera")
        end
        if p:has("Transform") then
            local body = p:get("Transform")
            carried.Transform = body
            if p:has("camera") then
                local camera = p:get("camera")
                carried["player/spawner/look"] = {
                    yaw = (camera.yaw or 0) - Quat.to_euler(body.rotation, "YXZ")[1],
                    pitch = camera.pitch or 0,
                }
            end
        end
        share.transfer_data = carried
    end
end):in_set("player/spawner/left"):before("core/net/peer/authority_switch")

-- Back in a world that holds it as a mirror, core sets what was handed whole on the player, its
-- camera and its look among it: the camera's yaw is the one it left with, so the look turns it by
-- the facing the body arrived with, as for a new player, and goes. Before the world net's
-- outbound, so the owner is never sent the yaw of the world it left.
app:add_systems(Update, {
    Query[{
        added = { "player/spawner/look" },
        with = { "player", "Transform", Mut["camera"] },
    }],
    Commands,
}, function(arrived, commands)
    for _, p in ipairs(arrived:iter_mut()) do
        local look = p:get("player/spawner/look")
        local body = p:get("Transform")
        local camera = p:get_mut("camera")
        camera.yaw = (look.yaw or 0) + Quat.to_euler(body.rotation, "YXZ")[1]
        camera.pitch = look.pitch or 0
        commands:entity(p:id()):remove("player/spawner/look")
    end
end):in_set("player/spawner/spawn")

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
