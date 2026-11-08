-- git/world/served, the server's half: a world served from git says so in its boot
-- (`return { base = "git/world/served" }`), and on a server that brings its write policy,
-- git/collaborators/authorize. Core names no git, and the asset layer refuses every edit to a
-- world whose boot declares no policy.
--
-- git/world/served = {}

return { base = "git/collaborators/authorize" }
