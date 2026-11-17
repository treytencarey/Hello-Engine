-- The client half of a player: the local player starts in game input with its sidebar, and
-- its own body turns dynamic, because this client drives its Transform. The body arrives
-- from the server with its collider and only changes type here: a body added after its
-- collider never attaches. The net client marks its own player `core/net/local` frames
-- after the player arrives, so both edges count.

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "player", "core/net/local" },
        },
        with = { "player", "core/net/local" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter()) do
        commands:entity(e:id()):patch({
            input = {},
            ["input/mode"] = { mode = "input/game" },
            sidebar = {},
            ["sidebar/profiler"] = {},
            ["sidebar/profile"] = {},
            ["sidebar/invites"] = {},
            ["sidebar/menu"] = {},
            ["git/collaborators"] = {},
            ["player/respawn"] = {},
        })
    end
end):in_set("player/local")

-- Its own body, dynamic, and again whenever the server's kind is written over it: a new owner is
-- sent its values a second time when the player spawns, and that can land after the edges above
-- (measured: a player walked in through a portal stood frozen). Beside it, a gravity scale of 1:
-- rapier applies `GravityScale3d` only when it changes and ignores its removal, so a body whose
-- scale something took off keeps the last one it had (measured: 0 left it climbing at 6 m/s).
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "player", "core/net/local" },
            changed = { "RigidBody3d" },
        },
        with = { "player", "core/net/local", Mut["RigidBody3d"] },
        optional = { "GravityScale3d" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter_mut()) do
        e:get_mut("RigidBody3d"):set_if_neq("Dynamic")
        if not e:has("GravityScale3d") then
            commands:entity(e:id()):insert({ GravityScale3d = { value = 1 } })
        end
    end
end):in_set("player/local")

-- Its body's gravity scale taken off: 1 goes back, which rapier applies as a change. The edge also
-- comes for a player that despawned or stopped being this client's, which has no row in `owned`,
-- and neither has one whose scale is back already.
app:add_systems(First, {
    Query[{ removed = { "GravityScale3d" } }],
    Query[{
        with = { "player", "core/net/local" },
        without = { "GravityScale3d" },
    }],
    Commands,
}, function(unscaled, owned, commands)
    local ids = {}
    for _, e in ipairs(unscaled:iter()) do
        ids[#ids + 1] = e:id()
    end
    for _, e in ipairs(owned:iter_many(ids)) do
        commands:entity(e:id()):insert({ GravityScale3d = { value = 1 } })
    end
end):in_set("player/local")

-- The player stopped being this client's and stays: another world's server took it, and it is
-- now moved by what this world's server sends. Its body goes back to the server's kind, at rest.
app:add_systems(First, {
    Query[{
        removed = { "core/net/local" },
        with = { "player" },
        optional = { "RigidBody3d", "Velocity3d" },
    }],
    Commands,
}, function(released, commands)
    for _, e in ipairs(released:iter()) do
        if e:has("RigidBody3d") then
            commands:entity(e:id()):insert({ RigidBody3d = "KinematicPositionBased" })
        end
        if e:has("Velocity3d") then
            commands:entity(e:id()):insert({
                Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
            })
        end
    end
end):in_set("player/local")

-- `player` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player" } }],
    Query[{
        any_of = {
            "input", "sidebar", "sidebar/profiler", "sidebar/profile", "sidebar/invites", "sidebar/menu",
            "git/collaborators", "player/respawn", "GravityScale3d",
        },
    }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove("input", "input/mode", "sidebar", "sidebar/profiler", "sidebar/profile",
            "sidebar/invites", "sidebar/menu", "git/collaborators", "player/respawn", "GravityScale3d")
    end
end):in_set("player/removed")
