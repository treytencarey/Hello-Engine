-- The client half of a player: the local player starts in game input with its sidebar, and
-- its own body turns dynamic, because this client drives its Transform. The body arrives
-- from the server with its collider and only changes type here: a body added after its
-- collider never attaches. The net client marks its own player `core/net/local` frames
-- after the player arrives, so both edges count.

local app = ...

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
            input = { mode = "input/game" },
            sidebar = {},
        })
        if e:has("RigidBody3d") then
            e:set({ RigidBody3d = "Dynamic" })
        end
    end
end):in_set("player/local")

-- `player` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player" } }],
    Query[{ any_of = { "input", "sidebar" } }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove("input", "sidebar")
    end
end):in_set("player/removed")
