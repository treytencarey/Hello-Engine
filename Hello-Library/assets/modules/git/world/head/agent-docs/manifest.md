---
depends_on: [vault/git, git/merge/notice, notification]
conflicts_with: []
exposes: [git/world/head]
---

# git/world/head

A world says which commit its tree is on, and each player whose checkout this world is learns how that checkout stands against it: behind (pull), on a commit they have not fetched (pull), or ahead (nothing to say). The other way round too: when the player's upstream holds commits the world's commit lacks, work pushed while the world ran, the player's half asks the world to pull.

Neither half runs git. Each asks root (`vault/git`), which reads the checkout of the world it started: the server's half the world's own tree, the client's half the player's checkout.

## Components

- `git/world/head = { sha }`, server authority, synced to the world's players: the commit the world's tree is on. One entity per world, spawned by the world's server; this mod writes `sha`. Absent until root has answered.
- The requests this mod sends root are children of the `git/world/head` entity, so they go with it: `vault/git/status` (the server's commit), `vault/git/pull` (a pull, server) and `vault/git/head` (the comparison, client). Each is closed once answered.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update (server) | `git/world/head/state` | On an added `git/world/head`: asks root for the tree's status |
| Update (server) | `git/world/head/state` | On a status or pull reply under a `git/world/head`: writes the commit it names into `sha`, and closes the request. Runs on the reply's edge, and twice a second while a reply waits |
| Update (server) | `git/world/head/pulling` | On an added `core/net/predict` carrying `git/world/head/pull`: despawns it; asks root to pull when the ask names the world's current commit and no pull is under way |
| Update (client) | `git/world/head/compare` | On an added or changed `git/world/head` with a `sha`: asks root how this player's checkout stands against it, closing a request for a commit the world has left. Only in a world with a `core/library` marked `edits` (the tree the player edits by hand); the edges wait until there is one |
| Update (client) | `git/world/head/compare` | On a head reply for the world's current commit: a notice when behind or not fetched; when `pushed`, a `git/world/head/pull` and a notice. Closes the request. Runs on the reply's edge, and twice a second while a reply waits |

## Use

```lua
-- the world's server spawns the entity once; the mod does the rest
commands:spawn({ ["git/world/head"] = {} })
```

## Notes

- A request goes to root; a world root did not start gets no reply, and its request waits until the world's commit moves.
- One request per stated commit: the commit moving closes the old request, which stops its git process at root.
- A pull answers `vault/git/pull/reply { status, sha, message }`; `sha` is the commit the pull left the tree on, and becomes `git/world/head.sha`. Only the pulls this mod asked for restate the commit.
- A request's reply crosses from root's VM, and an edge that crosses VMs can be missed, so a reply still waiting is looked at again twice a second.
- The ask to pull carries nothing the server trusts but its existence: root pulls the world's own branch into its own tree, as a restart would.
- Notices are `git/merge/notice` with a 20 s `notification` timeout.
- Suites run headless, each with a scratch repository: a world root starts on it, and the suite stands in for root's pull.
