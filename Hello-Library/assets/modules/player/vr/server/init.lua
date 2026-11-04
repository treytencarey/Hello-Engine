-- A player in VR: this composer names the stack. It gives a player `vr`, which says when its
-- client is in VR, and swaps its camera and how it turns while that lasts. Until then it does
-- nothing, so a player with no headset keeps its desktop camera. The camera is synced, so the choice
-- is the server's, and it costs one round trip in third person at the start.
--
-- A camera mod replaces the one it finds under the same base, across levels too, keeping
-- `camera`: adding one is the whole swap.

app:add_systems(First, {
    Query[{
        added = { "player/vr" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        commands:entity(e:id()):patch({ vr = {} })
    end
end):in_set("player/vr/init")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "vr/active", "player/vr", "movement" },
        },
        with = { "vr/active", "player/vr", "movement" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(entered, commands)
    for _, e in ipairs(entered:iter()) do
        commands:entity(e:id()):patch({
            ["camera/vr"] = {},
            movement = { face = "look" },
        })
    end
end):in_set("player/vr/enter")

-- Out of VR with the mod staying: back to the desktop.
app:add_systems(First, {
    Query[{
        removed = { "vr/active" },
        with = { "player/vr" },
        optional = { "movement" },
    }],
    Commands,
}, function(left, commands)
    for _, e in ipairs(left:iter()) do
        local player = commands:entity(e:id())
        player:patch({ ["camera/third_person"] = {} })
        if e:has("movement") then
            player:patch({ movement = { face = "velocity" } })
        end
    end
end):in_set("player/vr/leave")

-- `player/vr` was taken off an entity that stays: take off what this half added. A player gets its
-- desktop camera back, which replaces `camera/vr`; what is no longer a player just loses it. A
-- despawned entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player/vr" } }],
    Query[{
        any_of = { "vr", "camera/vr" },
        optional = { "player", "movement" },
    }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        local player = commands:entity(e:id())
        player:remove("vr")
        if e:has("camera/vr") then
            if e:has("player") then
                player:patch({ ["camera/third_person"] = {} })
            else
                player:remove("camera/vr")
            end
            if e:has("movement") then
                player:patch({ movement = { face = "velocity" } })
            end
        end
    end
end):in_set("player/vr/removed")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
