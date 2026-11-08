---
depends_on: [vault/git, core/library, git/merge/notice, notification]
conflicts_with: []
exposes: [git/world/served/merge, git/world/served/merge/result]
---

# git/world/served/merge

The world's version of a file the player edited, merged into their own checkout. When a version from the world cannot land because the player has edited that file, core holds it (`core/library/upstream.held[path]`, its content in the held store). This mod asks root to merge it with the player's working copy, and root writes the result into the checkout itself. World mods never touch files: core's watcher sees the file change. A sub-mod of `git/world/served`, which adds and removes it.

- **Clean**: root writes the merged text, or the held version when only the world changed it (`take = "theirs"`), or leaves the player's copy when only they changed it (`take = "mine"`). The path's `core/library/edit` gets `on = <held hash>`, so its next send expects the held version and lands instead of coming back stale.
- **Conflict**: root writes the file with git's conflict markers, and a `CONFLICT` notice tells the player. Nothing gets `on`, so a save that still has markers comes back stale and never reaches the world. A save that resolves them comes back stale too, for now (Pending, below).
- **Failed** (a binary both sides changed, a refusal, or no answer in time): a `COULD NOT MERGE` notice with the reason, and nothing gets `on`.

## Components

- `git/world/served/merge = {}`: the carrier, on the entity of a world whose content library is the player's checkout (`git/world/served` adds it beside `git/world/served/status`).
- `git/world/served/merge/result = { key, hash, asked_at, status }`: one per file, a child of the carrier, spawned with the file's request.
  - `key`: the file as `held` names it (asset relative);
  - `hash`: the held version being merged;
  - `asked_at`: `Time`'s elapsed seconds when the request was sent. A request is closed once answered, or after 30 s with no answer;
  - `status`: `"clean"`, `"conflict"` or `"failed"`, absent while the request is open.
  - It goes when the file is no longer held at that version, so a new held version is merged again, and one already answered is not asked twice.
- The requests are children of the carrier, `{ ["vault/git/merge"] = {}, ["vault/git"] = { path = "assets/" .. path, hash, apply = true }, Request = {} }`, carrying nothing of this mod's.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `git/world/served/merge` | When a carrier is added or an edited library's `core/library/upstream` changes: a request and a record for each held version with no record, and closes the requests and records for versions no longer held |
| Update | `git/world/served/merge` | On a merge reply under a carrier, or a record 30 s old: sets the record's `status`, a notice for a conflict or a failure, and closes the request. Runs on the reply's edge, and when a record still waiting reaches 30 s |
| Update | `git/world/served/merge` | When a record or a `core/library/edit` is added, or a record changes: sets `on` to the record's hash on the edit for each file merged clean |
| Update | none | When `git/world/served/merge` is taken off an entity that stays: closes its open requests. Its records go with it as its sub-components |

## Use

```lua
-- normally put there by git/world/served
commands:entity(e):insert({ ["git/world/served/merge"] = {} })
```

## Pending

- **Resolving a conflict.** Once the player has resolved the markers, the save should go through. That waits on a `vault/git` check, not yet built, that asks root whether the working copy still holds markers; this mod then sets `on` and the save lands. Until then a resolved file comes back stale like one that still has markers.

## Notes

- A world root did not start gets no reply: its requests close after 30 s, and the file's record says `failed`.
- Only libraries marked `edits` are read: the tree the player edits by hand.
- A reply crosses from root's VM, and a mirrored edge arrives as surely as a local one, so each reply is read on its own edge; only the 30 s limit runs on the clock.
- An edit stated after the answer gets `on` too: the record outlives the request.
- Notices are `git/merge/notice` with a 20 s `notification` timeout.
- Suites run headless, each with a scratch repository a world root starts on: `test_merge` with a stand-in for core's held state, `test_merge_flow` end to end, with root hosting the authority and a stand-in write policy that allows every write.
