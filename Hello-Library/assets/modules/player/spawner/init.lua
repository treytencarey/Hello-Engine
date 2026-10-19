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

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "player/spawner" } })) do
        local s = e:get("player/spawner")
        e:patch({
            ["player/spawner"] = {
                count = s.count or 8,
                radius = s.radius or 3,
                height = s.height or 5,
            },
        })
    end
end, { label = "PlayerSpawnerInit" })

-- A client that is not only watching gets a player, unless it has one already: a new
-- connection (`changed` also fires when a component is added), or one that stopped only
-- watching. A spawner added later serves the clients already connected: this mod loads
-- with it, and a mod's first run sees every connection as changed. A point given in this
-- run counts as taken: what this run spawned is not in a query until the run ends.
register_system("First", function(world)
    local taken, owned = {}, {}
    for _, c in ipairs(world:query({ changed = { "core/net/connection" } })) do
        local connection = c:get("core/net/connection")
        for _, p in ipairs(world:query({ with = { "player", "core/net/owner" } })) do
            taken[p:get("player").spawn_index] = true
            owned[p:get("core/net/owner").client_id] = true
        end
        if not connection.observer and not owned[connection.client_id] then
            for _, spawner in ipairs(world:query({ with = { "player/spawner" }, limit = 1 })) do
                local s = spawner:get("player/spawner")
                local index = 0
                for i = s.count, 1, -1 do
                    if not taken[i] then index = i end
                end
                local at = { x = 0, y = s.height, z = 0 }
                if index > 0 then
                    at = world:call_static_method("Vec3", "add", at, world:call_static_method("Quat", "mul_vec3",
                        world:call_static_method("Quat", "from_rotation_y", index / s.count * 2 * math.pi),
                        { x = s.radius, y = 0, z = 0 }))
                end
                spawn({
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
                    ScriptOwned = false,
                })
                taken[index] = true
            end
        end
    end
end, { label = "PlayerSpawn", after = { "PlayerSpawnerInit" } })

-- A client that left, or went back to only watching: its player goes.
register_system("PreUpdate", function(world)
    for _, c in ipairs(world:query({
        ["or"] = {
            changed = { "core/net/connection" },
            removed = { "core/net/connection" },
        },
        optional = { "core/net/connection" },
    })) do
        local connection = c:get("core/net/connection")
        if connection ~= nil and (connection.observer or world:get_entity(c:id()) == nil) then
            for _, p in ipairs(world:query({ with = { "player", "core/net/owner" } })) do
                if p:get("core/net/owner").client_id == connection.client_id then
                    despawn(p:id())
                end
            end
        end
    end
end, { label = "PlayerLeft" })
