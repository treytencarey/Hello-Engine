---
depends_on: [git/status, git/collaborators/authorize]
conflicts_with: []
exposes: [git/world/served]
---

# git/world/served

A world served from git says so in its own boot, and this mod is what that statement brings. Core names no git: who may edit a world's files is the world's policy, so the world states it.

## Components

- `git/world/served = {}`: on the world's boot entity, put there by the boot's `base`. It never crosses the network; each side's boot brings its own half.
  - On a server, its base is `git/collaborators/authorize`, the world's write policy.
  - On a client, it adds `git/status = {}` to its own entity while this world's own content library is the player's checkout, and removes it when it stops being one, or when `git/world/served` leaves an entity that stays. The checkout is this world's when the `core/library` whose `ref` is the world's scope (its own `core/world/status`) has `edits = true`, which core sets from the home fact.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update (client) | `git/world/served` | When a carrier, a `core/library` or the world's status row changes: add `git/status` to each carrier while the world's own library is the checkout, remove it otherwise |
| Update (client) | `git/world/served/removed` | When `git/world/served` is taken off an entity that stays, remove the `git/status` it added |

## Use

```lua
-- in a world's world/boot halves
return { base = "git/world/served" }
```

## Notes

- A world whose boot doesn't declare it plays normally, and the asset layer refuses every edit to it.
- Nothing here watches files or asks git: `git/status` does, and only on the carrier this mod gave it.
- `git/collaborators/authorize` is named as the server half's base before it is in this library; until it is, a served world on a server has no write policy and refuses every edit.
