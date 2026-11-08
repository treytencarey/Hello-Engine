---
depends_on: [git/collaborators/authorize]
conflicts_with: []
exposes: [git/world/served, git/world/served/status, git/world/served/merge]
---

# git/world/served

A world served from git says so in its own boot, and this mod is what that statement brings. Core names no git: who may edit a world's files is the world's policy, so the world states it.

## Components

- `git/world/served = {}`: on the world's boot entity, put there by the boot's `base`. It never crosses the network; each side's boot brings its own half.
  - On a server, its base is `git/collaborators/authorize`, the world's write policy.
  - On a client, it adds its two sub-mods to its own entity, `git/world/served/status = {}` and `git/world/served/merge = {}`, while this world's own content library is the player's checkout. It removes them when the library stops being one, or when `git/world/served` leaves an entity that stays. The checkout is this world's when the `core/library` whose `ref` is the world's scope (its own `core/world/status`) has `edits = true`, which core sets from the home fact.

## Sub-mods

- `git/world/served/status`: the player's edits to the checkout, read from git.
- `git/world/served/merge`: the world's versions of those files, merged into the checkout.

Each has its own folder and manifest. Neither declares this mod as its `base`: a base has one child per entity, and both ride the same carrier.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update (client) | `git/world/served` | When a carrier, a `core/library` or the world's status row changes: add both sub-mods to each carrier while the world's own library is the checkout, remove them otherwise |
| Update (client) | none | When `git/world/served` is taken off an entity that stays, remove both sub-mods |

## Use

```lua
-- in a world's world/boot halves
return { base = "git/world/served" }
```

## Notes

- A world whose boot doesn't declare it plays normally, and the asset layer refuses every edit to it.
- Nothing here watches files or asks git: its sub-mods do, and only on the carrier this mod gave them.
- `git/collaborators/authorize` is named as the server half's base before it is in this library; until it is, a served world on a server has no write policy and refuses every edit.
- Suites run headless. `test_served` checks when the carrier carries its sub-mods, not what they do.
