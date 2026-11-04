-- The client half of a 2D player: the local player starts in game input with its sidebar. The
-- net client marks its own player `core/net/local` frames after the player arrives, so both
-- edges count.

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "player/2d", "core/net/local" },
        },
        with = { "player/2d", "core/net/local" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter()) do
        commands:entity(e:id()):patch({
            input = {},
            ["input/mode"] = { mode = "input/game" },
            sidebar = {},
        })
    end
end):in_set("player/2d/local")

-- `player/2d` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player/2d" } }],
    Query[{ any_of = { "input", "sidebar" } }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove("input", "input/mode", "sidebar")
    end
end):in_set("player/2d/removed")
