---
depends_on: [core/asset, core/player/attest, core/net, vault/git]
conflicts_with: []
exposes: [git/collaborators/authorize, git/collaborators/authorize/proof]
---

# git/collaborators/authorize

The write policy of a world served from git: a player may change the world's files once they have proved they can push to its repository. The proof is a ref the player's root pushes, `refs/hello/challenge/<nonce>`, named by the nonce of the ticket the player joined on; this world's root checks that the ref is there. No writer record crosses worlds, and this world runs no git and holds no credential.

Server only. `git/world/served`'s server half brings it as its base, and its client half sends the player's push.

## Components

- `git/collaborators/authorize = {}`: on the world's boot entity. The mod marks it `core/asset/authorizer = {}`, so core asks it about every write, and takes the marker off when the component leaves an entity that stays.
- `git/collaborators/authorize/proof { user, nonce, state, why, asked_at }`: one per client, on the server's `core/net/connection`, where `core/player/attest` writes who the client is. Never synced. It lasts as long as the connection, whichever player entity the client controls or however often it respawns.
  - `user` and `nonce`: the connection's `core/player/attest` when the check was asked;
  - `state`: `"checking"` (a check is open), `"writer"` (root found the ref), `"absent"` (root did not), `"denied"` (root answered `failed` or `refused`);
  - `why`: root's message, with `denied`;
  - `asked_at`: this world's clock, in seconds, at the first ask for this nonce.
  - It goes with the connection, and is removed when the connection's attestation changes: a new nonce, a refusal or an anonymous ticket.
- The checks are children of the connection, so they go with it: `{ ["vault/git/proof"] = {}, ["vault/git"] = { nonce }, Request = {} }`, one open at a time per connection, each closed once answered or when the record goes.

## How a write is answered

Core spawns `core/asset/write { op, path, author, client }` for each write it holds. `author` is the identity the connection's join ticket proved, `{ role, user, name, links }`, absent when anonymous. `client` is the asset connection's id, not the game connection's, so the connection is found by `user`: the connections whose `core/player/attest` is `attested` with that `user` and a `nonce`.

- No `author.user` (anonymous, or a ticket that names no user): deny.
- No such connection in this world: deny.
- A connection whose proof is `writer`, for the same user and nonce: allow.
- A check open: the write waits.
- No proof, or `absent`: ask root once, and the write waits.
- `denied`: deny.

Root's answer settles every write waiting for that connection: `proved` allows them, anything else denies them. The player's push may still be landing, as the player's status uploads a dirty file as soon as its world turns edits on. So an `absent` less than 10 s after the first ask is asked again at once, and the writes keep waiting, inside core's 20 s hold; root's round trip spaces those asks. A later `absent` denies, and the next write asks again. A reply counts only on this mod's own check, for the nonce the record holds; a delivered or mirrored row is never read. Core refuses a write still waiting after its own timeout.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `git/collaborators/authorize` | On an added `git/collaborators/authorize`: marks the carrier `core/asset/authorizer` |
| First | none | When `git/collaborators/authorize` leaves an entity that stays: takes the marker off |
| First | `git/collaborators/authorize` | After `core/asset/server_ops`, before `core/asset/server_verdict`: reads root's answers on its checks, asking again on an early `absent`, then answers each waiting write or asks root. Runs on a new write, a reply or a removed record, and twice a second while a reply waits |
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
