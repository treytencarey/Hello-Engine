-- git/world/served, the server's half: a world served from git says so in its boot
-- (`return { base = "git/world/served" }`), and on a server that brings its write policy,
-- git/collaborators/authorize. Core names no git, and the asset layer refuses every edit to a
-- world whose boot declares no policy. It also states the world's commit to its players, through
-- a `git/world/head` child of the carrier, and puts git/ignore, the filter core asks about the
-- world's tree, on the asset endpoint serving that tree.
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

-- The world's own tree is the one its writable endpoint serves: a library front is read-only.
local function serves_the_world(endpoint)
    local cfg = endpoint:get("core/asset")
    return cfg.mode == "server" and cfg.read_only ~= true
end

-- git/ignore on each endpoint serving the world's tree, once a carrier is here.
app:add_systems(Update, {
    Query[{ with = { "core/asset" }, without = { "WorldMirror", "git/ignore" } }],
    Commands,
}, function(endpoints, commands)
    for _, e in ipairs(endpoints:iter()) do
        if serves_the_world(e) then commands:entity(e:id()):insert({ ["git/ignore"] = {} }) end
    end
end):in_set("git/world/served"):run_if({
    Query[{ ["or"] = { added = { "git/world/served", "core/asset" } }, without = { "WorldMirror" } }],
    Query[{ with = { "git/world/served" }, without = { "WorldMirror" } }],
}, function(touched, carriers)
    return not touched:is_empty() and not carriers:is_empty()
end)

-- A despawned carrier takes its head with it; this is for git/world/served taken off an entity
-- that stays. With the last carrier gone, git/ignore leaves the endpoints.
app:add_systems(Update, {
    Query[{ removed = { "git/world/served" } }],
    Query[{ with = { "git/world/head", "ChildOf" }, without = { "WorldMirror" } }],
    Query[{ with = { "git/world/served" }, without = { "WorldMirror" } }],
    Query[{ with = { "core/asset", "git/ignore" }, without = { "WorldMirror" } }],
    Commands,
}, function(removed, heads, carriers, filtered, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do gone[e:id()] = true end
    if next(gone) == nil then return end
    for _, head in ipairs(heads:iter()) do
        if gone[head:get("ChildOf")] then commands:entity(head:id()):despawn() end
    end
    if carriers:is_empty() then
        for _, e in ipairs(filtered:iter()) do commands:entity(e:id()):try_remove("git/ignore") end
    end
end):in_set("git/world/served")

return { base = "git/collaborators/authorize" }
