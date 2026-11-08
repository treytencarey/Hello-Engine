-- The server half of a player: what every player has, who it is, and its Transform following
-- the owner's. The owning client drives the Transform, as there is no client prediction
-- yet; it arrives in `core/net/sync/Transform`, seeded by the
-- spawner, and the server eases its own toward it. Missing fields get defaults when it is
-- added.
--
-- player = {
--     client_id = <the owning client>,
--     spawn_index = <its spawn point, 0 for the centre>,
--     user_id = <who the player is, from its join ticket; "" until known>,
--     smoothing = <how fast the server's Transform follows the owner's, per second>,
-- }

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")

app:add_systems(First, {
    Query[{
        added = { "player" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        commands:entity(e:id()):patch({
            ["camera/third_person"] = {},
            movement = {},
            animation = {},
            ["abilities/fireball"] = {},
            ["abilities/grenade"] = {},
            ["ai/perception/target"] = {},
            ["ai/noisemaker"] = {},
            ["sidebar/file_browser"] = {},
            ["player/vr"] = {},
        })
    end
end):in_set("player/init")

-- Who the player is, from the join ticket its client presented: `core/player/attest` on the
-- server's `core/net/connection` with the player's `client_id`. It lives on the connection, so a
-- player spawned again for the same connection is who it was.
app:add_systems(Update, {
    Query[{
        changed = { "core/player/attest" },
        with = { "core/net/connection" },
    }],
    Query[{
        added = { "player" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "core/net/connection", "core/player/attest" } }],
    Query[{
        with = { Mut["player"] },
        without = { "WorldMirror" },
    }],
}, function(attested, arrived, connections, players)
    local changed = {}
    for _, c in ipairs(attested:iter()) do
        changed[#changed + 1] = c:get("core/net/connection").client_id
    end
    for _, p in ipairs(arrived:iter()) do
        changed[#changed + 1] = p:get("player").client_id
    end
    for _, client_id in ipairs(changed) do
        local user_id = ""
        for _, c in ipairs(connections:iter()) do
            local a = c:get("core/player/attest")
            if c:get("core/net/connection").client_id == client_id and a.state == "attested" then user_id = a.user end
        end
        for _, p in ipairs(players:iter_mut()) do
            local player = p:get_mut("player")
            if player.client_id == client_id and player.user_id ~= user_id then player.user_id = user_id end
        end
    end
end):in_set("player/identity")

-- Follows, so it polls: the server's Transform eases toward the owner's.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "player", "core/net/sync/Transform", Mut["Transform"] },
        without = { "WorldMirror" },
    }],
}, function(time, players)
    local dt = time:delta_secs()
    for _, e in ipairs(players:iter_mut()) do
        local target = e:get("core/net/sync/Transform")
        local current = e:get("Transform")
        local t = math.min(1, e:get("player").smoothing * dt)
        e:patch({
            Transform = {
                translation = Vec3.lerp(current.translation, target.translation, t),
                rotation = Quat.slerp(current.rotation, target.rotation, t),
            },
        })
    end
end):in_set("player/follow")

-- `player` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player" } }],
    Query[{
        any_of = {
            "camera/third_person",
            "movement",
            "animation",
            "abilities/fireball",
            "abilities/grenade",
            "ai/perception/target",
            "ai/noisemaker",
            "sidebar/file_browser",
            "player/vr",
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
            "camera/third_person",
            "movement",
            "animation",
            "abilities/fireball",
            "abilities/grenade",
            "ai/perception/target",
            "ai/noisemaker",
            "sidebar/file_browser",
            "player/vr")
    end
end):in_set("player/removed")

return {
    defaults = {
        player = {
            user_id = "",
            smoothing = 15,
        },
    },
    ["core/net/sync"] = {
        authority = "server",
    },
}
