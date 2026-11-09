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
        optional = { Mut["RigidBody3d"] },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter_mut()) do
        commands:entity(e:id()):patch({
            input = {},
            ["input/mode"] = { mode = "input/game" },
            sidebar = {},
            ["sidebar/profiler"] = {},
            ["sidebar/profile"] = {},
        })
        if e:has("RigidBody3d") then
            e:set({ RigidBody3d = "Dynamic" })
        end
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
    Query[{ any_of = { "input", "sidebar", "sidebar/profiler", "sidebar/profile" } }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove("input", "input/mode", "sidebar", "sidebar/profiler", "sidebar/profile")
    end
end):in_set("player/removed")
