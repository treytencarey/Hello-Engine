-- The server half of a player: what every player has, who it is, and its Transform following
-- the owner's. The owning client drives the Transform (until prediction
-- returns with the net rewrite); it arrives in `core/net/sync/Transform`, seeded by the
-- spawner, and the server eases its own toward it. Missing fields get defaults when it is
-- added.
--
-- player = {
--     client_id = <the owning client>,
--     spawn_index = <its spawn point, 0 for the centre>,
--     user_id = <who the player is, from its join ticket; "" until known>,
--     smoothing = <how fast the server's Transform follows the owner's, per second>,
-- }

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "player" }, without = { "WorldMirror" } })) do
        local p = e:get("player")
        e:patch({
            player = { user_id = p.user_id or "", smoothing = p.smoothing or 15 },
            ["core/player/attest"] = {},
            ["camera/third_person"] = {},
            movement = {},
            ["abilities/fireball"] = {},
            ["abilities/grenade"] = {},
        })
    end
end, { label = "PlayerSetup" })

-- Who the player is, from the join ticket its client presented (`core/player/attest`).
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        changed = { "core/player/attest" },
        with = { "player" },
        without = { "WorldMirror" },
    })) do
        local a = e:get("core/player/attest")
        e:patch({ player = { user_id = a.state == "attested" and a.user or "" } })
    end
end, { label = "PlayerIdentity" })

-- Follows, so it polls: the server's Transform eases toward the owner's.
register_system("Update", function(world)
    local dt = world:delta_time() or 0
    for _, e in ipairs(world:query({
        with = { "player", "core/net/sync/Transform", "Transform" },
        without = { "WorldMirror" },
    })) do
        local target = e:get("core/net/sync/Transform")
        local current = e:get("Transform")
        -- `smoothing` is filled when the player is added; skip until then
        local smoothing = e:get("player").smoothing
        if smoothing ~= nil then
            local t = math.min(1, smoothing * dt)
            e:patch({
                Transform = {
                    translation = world:call_static_method("Vec3", "lerp", current.translation, target.translation, t),
                    rotation = world:call_static_method("Quat", "slerp", current.rotation, target.rotation, t),
                },
            })
        end
    end
end, { label = "PlayerFollow" })

-- `player` was taken off an entity that stays: take off what this half added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "player" } })) do
        e:patch({
            ["core/player/attest"] = null,
            ["camera/third_person"] = null,
            movement = null,
            ["abilities/fireball"] = null,
            ["abilities/grenade"] = null,
        })
    end
end, { label = "PlayerRemoved" })

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
