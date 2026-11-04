-- The server half of a 2D player: what every 2D player has, who it is, and its Transform
-- following the owner's. The owning client drives the Transform (until prediction returns with
-- the net rewrite); it arrives in `core/net/sync/Transform`, seeded by the spawner, and the
-- server eases its own toward it. Missing fields get defaults when it is added.
--
-- player/2d = {
--     client_id = <the owning client>,
--     spawn_index = <its spawn point, 0 for the centre>,
--     user_id = <who the player is, from its join ticket; "" until known>,
--     smoothing = <how fast the server's Transform follows the owner's, per second>,
-- }

local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")

app:add_systems(First, {
    Query[{
        added = { "player/2d" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        commands:entity(e:id()):patch({
            ["core/player/attest"] = {},
            ["camera/2d"] = {},
            ["movement/2d"] = {},
            ["animation/sprite"] = {},
        })
    end
end):in_set("player/2d/init")

-- Who the player is, from the join ticket its client presented (`core/player/attest`).
app:add_systems(Update, {
    Query[{
        changed = { "core/player/attest" },
        with = { "player/2d" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(attested, commands)
    for _, e in ipairs(attested:iter()) do
        local a = e:get("core/player/attest")
        commands:entity(e:id()):patch({ ["player/2d"] = { user_id = a.state == "attested" and a.user or "" } })
    end
end):in_set("player/2d/identity")

-- Follows, so it polls: the server's Transform eases toward the owner's. A 2D body never turns.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "player/2d", "core/net/sync/Transform", Mut["Transform"] },
        without = { "WorldMirror" },
    }],
}, function(time, players)
    local dt = time:delta_secs()
    for _, e in ipairs(players:iter_mut()) do
        local p = e:get("player/2d")
        local target = e:get("core/net/sync/Transform")
        local current = e:get("Transform")
        e:patch({
            Transform = {
                translation = Vec3.lerp(current.translation, target.translation, math.min(1, p.smoothing * dt)),
            },
        })
    end
end):in_set("player/2d/follow")

-- `player/2d` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player/2d" } }],
    Query[{
        any_of = {
            "core/player/attest",
            "camera/2d",
            "movement/2d",
            "animation/sprite",
        },
    }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove(
            "core/player/attest",
            "camera/2d",
            "movement/2d",
            "animation/sprite")
    end
end):in_set("player/2d/removed")

return {
    defaults = {
        ["player/2d"] = {
            user_id = "",
            smoothing = 15,
        },
    },
    ["core/net/sync"] = {
        authority = "server",
    },
}
