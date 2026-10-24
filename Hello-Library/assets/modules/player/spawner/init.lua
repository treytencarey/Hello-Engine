-- The player spawner, on a world's server: a player for each connected client, at a free
-- spawn point, despawned when the client leaves. Points sit on a circle around the
-- spawner's origin. Missing fields get defaults when it is added.
--
-- The owning client drives its player's Transform (until prediction
-- returns with the net rewrite): `Transform` syncs with client authority into the
-- `core/net/sync/Transform` shadow seeded here, which `player` follows on the server. The
-- server's body is kinematic; the owner switches its own to dynamic (`player`).
--
-- player/spawner = {
--     count = <spawn points>,
--     radius = <metres from the origin>,
--     height = <metres above the origin>,
-- }

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

app:add_systems(First, {
    Query[{ added = { "player/spawner" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local s = e:get("player/spawner")
        commands:entity(e:id()):patch({
            ["player/spawner"] = {
                count = s.count or 8,
                radius = s.radius or 3,
                height = s.height or 5,
            },
        })
    end
end):in_set("player/spawner/init")

-- A client that is not only watching gets a player, unless it has one already: a new
-- connection (`changed` also fires when a component is added), or one that stopped only
-- watching. A spawner added later serves the clients already connected: this mod loads
-- with it, and a mod's first run sees every connection as changed. A point given in this
-- run counts as taken: what this run spawned is not in a query until the run ends.
app:add_systems(First, {
    Query[{ changed = { "core/net/connection" } }],
    Query[{ with = { "player", "core/net/owner" } }],
    Query[{ with = { "player/spawner" } }],
    Commands,
}, function(connections, players, spawners, commands)
    local taken, owned = {}, {}
    for _, p in ipairs(players:iter()) do
        taken[p:get("player").spawn_index] = true
        owned[p:get("core/net/owner").client_id] = true
    end
    for _, c in ipairs(connections:iter()) do
        local connection = c:get("core/net/connection")
        local spawner = spawners:iter()[1]
        if spawner and not connection.observer and not owned[connection.client_id] then
            local s = spawner:get("player/spawner")
            local index = 0
            for i = s.count, 1, -1 do
                if not taken[i] then index = i end
            end
            local at = { x = 0, y = s.height, z = 0 }
            if index > 0 then
                at = Vec3.add(at, Quat.mul_vec3(Quat.from_rotation_y(index / s.count * 2 * math.pi),
                    { x = s.radius, y = 0, z = 0 }))
            end
            commands:spawn({
                player = { client_id = connection.client_id, spawn_index = index },
                Transform = { translation = at },
                RigidBody3d = "KinematicPositionBased",
                Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
                LockedAxes3d = "ROTATION_LOCKED",
                Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
                ["core/net/owner"] = { client_id = connection.client_id },
                ["core/net/sync/Transform"] = { translation = at, rotation = { x = 0, y = 0, z = 0, w = 1 } },
                ["core/net/sync"] = {
                    Transform = { authority = "client", reliable = false },
                    RigidBody3d = { authority = "server" },
                    Collider3d = { authority = "server" },
                    LockedAxes3d = { authority = "server" },
                },
                -- Not reaped with this mod: a player lives until its client leaves.
                ["core/script/owner"] = false,
            })
            taken[index] = true
        end
    end
end):in_set("player/spawner/spawn"):after("player/spawner/init")

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
