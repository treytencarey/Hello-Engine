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
--     distance = <the camera's distance, the zoom, metres>,
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

--- A player's camera as this world frames one arriving, new or back: a new player's, with the
--- look on it; the camera's defaults and a game's spawner fill the rest. How a world frames a
--- player (eye height, offset, mode, the body's scale) is that world's; only the look crosses.
--- Its yaw crossed relative to the body, so it is turned by the facing the body arrives with (a
--- door's place may turn it).
local function framed(look, facing)
    look = look or {}
    return {
        yaw = (look.yaw or 0) + Quat.to_euler(facing, "YXZ")[1],
        pitch = look.pitch,
        distance = look.distance,
    }
end

--- What a body with `camera` looks with: the yaw relative to the body, which holds in any frame.
local function look_of(body, camera)
    if camera == nil then return nil end
    return {
        yaw = (camera.yaw or 0) - Quat.to_euler(body.rotation, "YXZ")[1],
        pitch = camera.pitch or 0,
        distance = camera.distance,
    }
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
        if player.spawn_point ~= nil then
            held[player.spawn_point] = (held[player.spawn_point] or 0) + 1
        end
        -- By its owner, the connection.
        owned[p:get("core/net/owner")] = true
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
        if spawner and not connection.observer and not owned[c:id()] then
            local s = spawner:get("player/spawner")
            local handed = connection.synced_state or {}
            local stood = handed.Transform
            local look = handed["player/spawner/look"]
            local at, facing, camera
            local claim = least_held(ready, held)
            -- A handed player claims a point like any other, and arrives where it stood, framed as
            -- a new player is (`framed`).
            if stood and stood.translation then
                at = stood.translation
                facing = stood.rotation or { x = 0, y = 0, z = 0, w = 1 }
                camera = framed(look, facing)
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
                    ["core/net/owner"] = c:id(),
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
                owned[c:id()] = true
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

-- A client that went back to only watching: the players its connection owns go. One that left:
-- its connection going takes the owner off its players, which keep the entity, and they go. A
-- demotion takes the owner too, but leaves a mirror.
app:add_systems(PreUpdate, {
    Query[{ changed = { "core/net/connection" }, optional = { "core/net/owns" } }],
    Query[{ with = { "player" }, optional = { "core/net/owner" } }],
    Query[{
        ["or"] = { removed = { "core/net/owner" } },
        with = { "player" },
        without = { "core/net/peer/mirror" },
    }],
    Commands,
}, function(connections, players, unowned, commands)
    for _, c in ipairs(connections:iter()) do
        if c:get("core/net/connection").observer then
            for _, p in ipairs(players:iter_many(c:get("core/net/owns") or {})) do
                commands:entity(p:id()):despawn()
            end
        end
    end
    -- A removed edge also comes for an entity that despawned: only a player still here, and still
    -- unowned, goes.
    for _, p in ipairs(unowned:iter()) do
        local player = players:get(p:id())
        if player ~= nil and not player:has("core/net/owner") then
            commands:entity(p:id()):despawn()
        end
    end
end):in_set("player/spawner/left")

-- A player handed to another world takes its body's place and its look in the switch itself,
-- which core sends in this same frame: the target's mirror of the player may be an update behind.
-- What the player did crosses, and how this world frames it does not: the camera stays here.
-- Core places the body at a door's place there, which may turn it; the camera's yaw does not turn
-- with it, so the look carries the yaw relative to the body, which holds in any frame. Only these
-- entries are written: the portal handing it over puts its timer beside them.
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
        if p:has("Transform") then
            local body = p:get("Transform")
            carried.Transform = body
            carried["player/spawner/look"] = look_of(body, p:get("camera"))
        end
        share.transfer_data = carried
    end
end):in_set("player/spawner/left"):before("core/net/peer/authority_switch")

-- Back in a world that holds it as a mirror, core makes the player its own again: with what was
-- handed set whole, its look among it, or, when the world it went to died, where that world last
-- had it, with the look it had there. While it was away the target's updates wrote its mirror here,
-- camera and scale too, so it is framed again as a new player is: a new player's camera with the
-- look on it, and a new player's scale; a game's spawner then frames it its own way on the owner's
-- `added` edge, as it does a new player. In `First`, after core's peer inbound that re-promotes it,
-- and before the world net tracks it, on the owner's `added` edge; a new player, whose link to its
-- spawner is added with its owner, is framed already, and a game frames it on the same edge. The
-- mirror's `removed` edge comes a frame late, after the world net sent the body with the far camera.
app:add_systems(First, {
    Query[{
        added = { "core/net/owner" },
        with = { "player", Mut["Transform"] },
        optional = { "player/spawner/look", "camera" },
    }],
    Query[{ added = { "player/spawner/player" }, with = { "player" } }],
    Commands,
}, function(arrived, new, commands)
    local fresh = {}
    for _, p in ipairs(new:iter()) do fresh[p:id()] = true end
    for _, p in ipairs(arrived:iter_mut()) do
        local body = p:get_mut("Transform")
        if body ~= nil and not fresh[p:id()] then
            body.scale = { x = 1, y = 1, z = 1 }
            local look = p:get("player/spawner/look") or look_of(body, p:get("camera"))
            commands:entity(p:id()):insert({ camera = framed(look, body.rotation) })
            commands:entity(p:id()):try_remove("player/spawner/look")
        end
    end
end):in_set("player/spawner/spawn")
    :after("core/net/peer/server_inbound")
    :after("core/net/peer/client_inbound")
    :before("core/net/sync_track")

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
