---
depends_on: [vault/git, core/library, git/merge/notice, notification]
conflicts_with: []
exposes: [git/merge, git/merge/job, git/merge/result]
---

# git/merge

The world's version of a file the player edited, merged into their own checkout. When a version from the world cannot land because the player has edited that file, core holds it (`core/library/upstream.held[path]`, its content in the held store). This mod asks root to merge it with the player's working copy, and root writes the result into the checkout itself. World mods never touch files: core's watcher sees the file change.

- **Clean**: root writes the merged text, or the held version when only the world changed it (`take = "theirs"`), or leaves the player's copy when only they changed it (`take = "mine"`). The path's `core/library/edit` gets `on = <held hash>`, so its next send expects the held version and lands instead of coming back stale.
- **Conflict**: root writes the file with git's conflict markers, and a `CONFLICT` notice tells the player. Nothing gets `on`, so a save that still has markers comes back stale and never reaches the world. A save that resolves them comes back stale too, for now: this mod cannot yet tell a resolved file from one that still has markers, since a world reads no files.
- **Failed** (a binary both sides changed, a refusal, or no answer in time): a `COULD NOT MERGE` notice with the reason, and nothing gets `on`.

## Components

- `git/merge = {}`: the carrier, on the entity of a world whose content library is the player's checkout (`git/world/served` adds it beside `git/status`).
- `git/merge/job = { asked_at }`: on each request this mod sends root, `{ ["vault/git/merge"] = {}, ["vault/git"] = { path = "assets/" .. path, hash, apply = true }, Request = {} }`, a child of the carrier. `asked_at` is `Time`'s elapsed seconds when it was sent. A request is closed once answered, or after 30 s with no answer.
- `git/merge/result = { key, hash, status }`: one per file, a child of the carrier. `key` is the file as `held` names it (asset relative), `hash` the held version that was merged, `status` `"clean"`, `"conflict"` or `"failed"`. It goes when the file is no longer held at that version, so a new held version is merged again, and one already answered is not asked twice.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `git/merge` | When a carrier is added or an edited library's `core/library/upstream` changes: a request for each held version with no request or record, and closes the requests and records for versions no longer held |
| Update | `git/merge` | On a merge reply under a carrier, or a request 30 s old: writes the file's record, a notice for a conflict or a failure, and closes the request. Runs on the reply's edge, and twice a second while a request is open |
| Update | `git/merge` | When a record or a `core/library/edit` is added, or a record changes: sets `on` to the record's hash on the edit for each file merged clean |

## Use

```lua
-- on the world's entity, while its content library is the player's checkout
commands:entity(e):insert({ ["git/merge"] = {} })
```

## Notes

- A world root did not start gets no reply: its requests close after 30 s, and the file's record says `failed`.
- Only libraries marked `edits` are read: the tree the player edits by hand.
- A reply crosses from root's VM, and an edge that crosses VMs can be missed, so a request still open is looked at again twice a second.
- An edit stated after the answer gets `on` too: the record outlives the request.
- Notices are `git/merge/notice` with a 20 s `notification` timeout.
- Suites run headless, each with a scratch repository a world root starts on: `test_merge` with a stand-in for core's held state, `test_merge_flow` end to end, with root hosting the authority.
