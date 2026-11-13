---
depends_on: [core/asset, core/player/attest, core/net, vault/git]
conflicts_with: []
exposes: [git/collaborators/authorize, git/collaborators/authorize/proof]
---

# git/collaborators/authorize

The write policy of a world served from git: a player may change the world's files once they have proved they can push to its repository. The proof is a ref the player's root pushes, `refs/hello/challenge/<nonce>`, named by the nonce of the ticket the player joined on; this world's root checks that the ref is there. No writer record crosses worlds, and this world runs no git and holds no credential.

Server only. `git/world/served`'s server half brings it as its base, and its client half sends the player's push.

## Components

- `git/collaborators/authorize = { proof_wait }`: on the world's boot entity. `proof_wait` (default 90) is how many seconds after the first ask an `absent` may still turn into `writer`; a world's boot may set another. The mod marks it `core/asset/authorizer = {}`, so core asks it about every write, and takes the marker off when the component leaves an entity that stays.
- `git/collaborators/authorize/proof { user, nonce, state, why, asked_at, next_at }`: one per client, on the server's `core/net/connection`, where `core/player/attest` writes who the client is. Never synced. It lasts as long as the connection, whichever player entity the client controls or however often it respawns.
  - `user` and `nonce`: the connection's `core/player/attest` when the check was asked;
  - `state`: `"checking"` (a check is open), `"writer"` (root found the ref), `"absent"` (root did not), `"denied"` (root answered `failed` or `refused`);
  - `why`: root's message, with `denied`;
  - `asked_at`: this world's clock, in seconds, at the first ask for this nonce;
  - `next_at`: while `absent` may still turn into `writer`, when root is asked again; absent once `absent` is final.
  - It goes with the connection, and is removed when the connection's attestation changes: a new nonce, a refusal or an anonymous ticket.
- The checks are children of the connection, so they go with it: `{ ["vault/git/proof"] = {}, ["vault/git"] = { nonce }, Request = {} }`, one open at a time per connection, each closed once answered or when the record goes.

## How a write is answered

Core spawns `core/asset/write { op, path, author, client }` for each write it holds. `author` is the identity the connection's join ticket proved, `{ role, user, name, links }`, absent when anonymous. `client` is the asset connection's id, not the game connection's, so the connection is found by `user`: the connections whose `core/player/attest` is `attested` with that `user` and a `nonce`.

- No `author.user` (anonymous, or a ticket that names no user): deny.
- No such connection in this world: deny.
- A connection whose proof is `writer`, for the same user and nonce: allow.
- A check open: the write waits.
- No proof: ask root once, and the write waits.
- `absent` with a `next_at`: the write waits.
- `absent` and final: a write that just arrived asks again from its own arrival; one that already waited is denied.
- `denied`: deny.

Root's answer settles every write waiting for that connection: `proved` allows them, `failed` or `refused` denies them. `absent` is not a verdict while the player's push may still be landing (one measured live took about 30 s): the writes keep waiting, which core allows up to its ceiling, and root is asked again after as long as it has been since the first ask (about 1, 2, 4, 8, 16, 32 s), until `proof_wait`. Then `absent` is final for that nonce, and every write still waiting on it is denied, however many connections its author has. A later write asks again. A reply counts only on this mod's own check, for the nonce the record holds; a delivered or mirrored row is never read. Core refuses a write still waiting at its own ceiling (300 s), which only bounds a policy that never answers. The back-off replaced fixed asks under which one connection's `absent` was final at 10 s while two or more asked until core's old 20 s cut: the wait is now the same for any number of connections.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `git/collaborators/authorize` | On an added `git/collaborators/authorize`: marks the carrier `core/asset/authorizer` |
| First | none | When `git/collaborators/authorize` leaves an entity that stays: takes the marker off |
| First | `git/collaborators/authorize` | After `core/asset/server_ops`, before `core/asset/server_verdict`: reads root's answers on its checks (an early `absent` sets `next_at`), then answers each waiting write or asks root. Runs on a new write, a reply, or a changed or removed record |
| First | `git/collaborators/authorize` | Timed: a record `absent` whose `next_at` has come is asked of root again, or made final once `proof_wait` has passed. Runs only while one is due |
| Update | `git/collaborators/authorize` | After `core/player/attest`: on a changed attestation, removes a record for another nonce, and its open check |

## Use

```lua
-- normally the base of git/world/served's server half
return { base = "git/collaborators/authorize" }
```

## Notes

- One proof per connection per hosted world. The first edit in a world waits for it.
- `denied` holds for the connection: a check that failed is not asked again until the player joins again.
- Dev both-mode has no ticket, so no nonce and no proof: every write there is refused.
- A check spawned by this mod survives its reload, so a reload never closes one root is answering.
- Suites run headless. `test_authorize` stands in for core's write requests, for the connections and their attestations, and for root's answers.
