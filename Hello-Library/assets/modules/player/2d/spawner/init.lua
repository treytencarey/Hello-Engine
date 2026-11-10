-- The 2D player spawner, on a world's server: a 2D player for each connected client, at a free
-- spawn point, despawned when the client leaves. Points sit on a circle around the spawner's
-- origin, in the plane. Missing fields get defaults when it is added.
--
-- The owning client drives its player's Transform, as there is no client prediction yet:
-- `Transform` syncs with client authority into the `core/net/sync/Transform` shadow
-- seeded here, which `player/2d` follows on the server. The server's body is kinematic; the
-- owner switches its own to dynamic (`player/2d`).
--
-- player/2d/spawner = {
--     count = <spawn points>,
--     radius = <pixels from the origin>,
--     z = <how far above the origin the players are drawn>,
--     sprite = <the `animation/sprite` every player starts with; a world names its own sheet here>,
-- }

local Quat = require("bevy::math::Quat")

-- A client that is not only watching gets a player, unless it has one already: a new
-- connection (`changed` also fires when a component is added), or one that stopped only
-- watching. A spawner added later serves the clients already connected: this mod loads
-- with it, and a mod's first run sees every connection as changed. A point given in this
-- run counts as taken: what this run spawned is not in a query until the run ends.
app:add_systems(First, {
    Query[{ changed = { "core/net/connection" } }],
    Query[{ with = { "player/2d", "core/net/owner" } }],
    Query[{ with = { "player/2d/spawner" } }],
    Commands,
}, function(connections, players, spawners, commands)
    local taken, owned = {}, {}
    for _, p in ipairs(players:iter()) do
        taken[p:get("player/2d").spawn_index] = true
        owned[p:get("core/net/owner").client_id] = true
    end
    for _, c in ipairs(connections:iter()) do
        local connection = c:get("core/net/connection")
        local spawner = spawners:iter()[1]
        if spawner and not connection.observer and not owned[connection.client_id] then
            local s = spawner:get("player/2d/spawner")
            local index = 0
            for i = s.count, 1, -1 do
                if not taken[i] then index = i end
            end
            local at = { x = 0, y = 0, z = s.z }
            if index > 0 then
                local on_circle = Quat.mul_vec3(Quat.from_rotation_z(index / s.count * 2 * math.pi),
                    { x = s.radius, y = 0, z = 0 })
                at = { x = on_circle.x, y = on_circle.y, z = s.z }
            end
            commands:spawn({
                ["player/2d"] = { client_id = connection.client_id, spawn_index = index },
                -- `camera` defaults its distance to a 3D one, and in 2D it is the zoom.
                camera = { distance = 1 },
                ["animation/sprite"] = s.sprite,
                Transform = { translation = at },
                RigidBody2d = "KinematicPositionBased",
                Collider2d = { capsule_y = { radius = 8, half_height = 10 } },
                LockedAxes2d = "ROTATION_LOCKED",
                GravityScale2d = 0,
                Velocity2d = { linvel = { x = 0, y = 0 }, angvel = 0 },
                ["core/net/owner"] = { client_id = connection.client_id },
                ["core/net/sync/Transform"] = { translation = at, rotation = { x = 0, y = 0, z = 0, w = 1 } },
                ["core/net/sync"] = {
                    Transform = { authority = "client", reliable = false },
                    RigidBody2d = { authority = "server" },
                    Collider2d = { authority = "server" },
                    LockedAxes2d = { authority = "server" },
                    GravityScale2d = { authority = "server" },
                },
                ["core/script/owner"] = false,
            })
            taken[index] = true
        end
    end
end):in_set("player/2d/spawner/spawn")

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
    Query[{ with = { "player/2d", "core/net/owner" } }],
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
end):in_set("player/2d/spawner/left")

return {
    defaults = {
        ["player/2d/spawner"] = {
            count = 8,
            radius = 96,
            z = 0,
            sprite = {},
        },
    },
}
