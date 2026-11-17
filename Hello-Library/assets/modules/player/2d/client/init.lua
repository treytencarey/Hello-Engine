-- The client half of a 2D player: the local player starts in game input with its sidebar, and
-- its own body turns dynamic, because this client drives its Transform. The body arrives from
-- the server with its collider and only changes type here: a body added after its collider
-- never attaches. This client's own player is one in its own nets' `core/net/owns`: an owner can
-- come after the player, so both edges count.

--- Is the row's owner one of this client's own nets? Its owner column must be named.
local function mine(own, row)
    local owner = row:get("core/net/owner")
    return owner ~= nil and own:contains(owner)
end

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "player/2d", "core/net/owner" },
            changed = { "core/net/owner" },
        },
        with = { "player/2d", "core/net/owner" },
        optional = { Mut["RigidBody2d"] },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(players, own, commands)
    for _, e in ipairs(players:iter_mut()) do
        if mine(own, e) then
            commands:entity(e:id()):patch({
                input = {},
                ["input/mode"] = { mode = "input/game" },
                sidebar = {},
            })
            if e:has("RigidBody2d") then
                e:set({ RigidBody2d = "Dynamic" })
            end
        end
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
