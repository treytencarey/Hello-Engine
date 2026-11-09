-- git/world/served, the server's half: a world served from git says so in its boot
-- (`return { base = "git/world/served" }`), and on a server that brings its write policy,
-- git/collaborators/authorize. Core names no git, and the asset layer refuses every edit to a
-- world whose boot declares no policy. It also states the world's commit to its players, through
-- a `git/world/head` child of the carrier.
--
-- git/world/served = {}

app:add_systems(Update, {
    Query[{ added = { "git/world/served" }, without = { "WorldMirror" } }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        commands:spawn({ ["git/world/head"] = {}, ChildOf = e:id() })
    end
end):in_set("git/world/served")

-- A despawned carrier takes its head with it; this is for git/world/served taken off an entity
-- that stays.
app:add_systems(Update, {
    Query[{ removed = { "git/world/served" } }],
    Query[{ with = { "git/world/head", "ChildOf" }, without = { "WorldMirror" } }],
    Commands,
}, function(removed, heads, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do gone[e:id()] = true end
    for _, head in ipairs(heads:iter()) do
        if gone[head:get("ChildOf")] then commands:entity(head:id()):despawn() end
    end
end):in_set("git/world/served")

return { base = "git/collaborators/authorize" }
