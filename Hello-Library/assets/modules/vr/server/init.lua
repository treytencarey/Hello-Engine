-- The server half: only the owner knows it is in VR, so `vr/active` crosses from the owner, and
-- every client hears it.

app:add_systems(First, {
    Query[{
        added = { "vr" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        commands:entity(e:id()):patch({
            ["core/net/sync"] = { ["vr/active"] = { authority = "client" } },
        })
    end
end):in_set("vr/sync")

-- `vr` was taken off an entity that stays: take off the sync this half added. A despawned player
-- has no row in `synced`.
app:add_systems(First, {
    Query[{ removed = { "vr" } }],
    Query[{ with = { "core/net/sync" } }],
    Commands,
}, function(removed, synced, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(synced:iter_many(gone)) do
        commands:entity(e:id()):patch({
            ["core/net/sync"] = { ["vr/active"] = null },
        })
    end
end):in_set("vr/unsync")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
