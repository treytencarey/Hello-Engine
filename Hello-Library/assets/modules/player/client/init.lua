-- The client half of a player: the local player starts in game input with its sidebar, and
-- its own body turns dynamic, because this client drives its Transform. The body arrives
-- from the server with its collider and only changes type here: a body added after its
-- collider never attaches. The net client marks its own player `core/net/local` frames
-- after the player arrives, so both edges count.

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "player", "core/net/local" },
        },
        with = { "player", "core/net/local" },
        optional = { "RigidBody3d" },
    })) do
        e:patch({
            input = { mode = "input/game" },
            sidebar = {},
        })
        if e:has("RigidBody3d") then
            e:set({ RigidBody3d = "Dynamic" })
        end
    end
end, { label = "PlayerLocal" })

-- `player` was taken off an entity that stays: take off what this half added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "player" } })) do
        e:patch({
            input = null,
            sidebar = null,
        })
    end
end, { label = "PlayerRemoved" })
