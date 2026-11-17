-- A mod with git/world/served's shape for the write policy: its server half names
-- git/collaborators/authorize as its base, which names core/permission in turn. It pins the
-- policy's `proof_wait` short through a carrier default.

return {
    base = "git/collaborators/authorize",
    defaults = {
        ["git/collaborators/authorize"] = { proof_wait = 6 },
    },
}
