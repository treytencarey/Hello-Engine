---
depends_on: [vault/git, core/process]
conflicts_with: []
exposes: [git/world/served/status, git/world/served/status/scan]
---

# git/world/served/status

The player's edits to a world's checkout, read from git. Every file `git status` reports under the checkout's `assets/` becomes core's `core/library/edit`, which core uploads. This world runs no git: it asks root, which reads the checkout of a world it started (`vault/git/status`). A sub-mod of `git/world/served`, which adds and removes it.

Git answers the branch-switch case by itself. A `git checkout` rewrites many files, but afterwards they match HEAD, so no scan names them. Only the player's own work is dirty.

## Components

- `git/world/served/status = {}`: on the entity that watches. `git/world/served` adds it to its own carrier while the world's tree is the player's checkout.
- `git/world/served/status/scan { asked_at, head, ops }`, on the carrier, added with the first request:
  - `asked_at`: this world's clock, in seconds, when the last request was asked;
  - `head`: the checkout's commit at the last scan;
  - `ops = { [path] = { op, mtime } }`: what the last scan reported, by asset-relative path. `op` is `"write"`, `"create"` or `"delete"`, and `mtime` is when root read the file as last written (absent for a delete).
- The requests are children of the carrier: `{ ["vault/git/status"] = {}, ["vault/git"] = {}, Request = {} }`, one open at a time, each closed once answered.
- The edits are children of the carrier: `core/library/edit { path, seq, deleted }`, one per path, asset relative. They are kept through a reload of this mod, and go with the carrier, or with `git/world/served/status` when it is taken off.

## When it asks

- Only while a carrier exists, every 2 s.
- Not in both-mode: root's `core/process` says `mode = "both"` when this process hosts the world from the same checkout, so there is nothing to send.
- Not while the player is signed out: root's `core/player/identity` carries `site_user_id` only while they are signed in.
- Only root's statements count: a mirror whose `WorldMirror.world_id` is 0, or the VM's own row at root. Any world can share a `core/process` or a `core/player/identity` of its own.

## What each scan states

- A path the scan reports and no edit names: a new edit, `seq = 1`, `deleted` for a delete.
- A path whose `op` or `mtime` changed since the last scan: its `seq` moves. A second save of a file that is still dirty moves only its `mtime`.
- A path that left the list while HEAD stayed put is a revert, and still the player's change: its `seq` moves once more, so the committed version goes up. A file the last scan listed as new is `deleted`. The next scan drops it.
- A path that left the list because HEAD moved, a commit or a branch switch, is dropped at once.
- A scan that failed changes nothing.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `git/world/served/status` | While a carrier exists, outside both-mode and while signed in: asks root every 2 s, one request at a time. A request root has not answered in 10 s is closed and asked again |
| Update | `git/world/served/status` | On a status reply under a carrier: restates the edits and the scan, and closes the request. Runs on the reply's edge |
| Update | none | When `git/world/served/status` is taken off an entity that stays: despawns its edits and its open request |

## Use

```lua
-- normally put there by git/world/served
commands:spawn({ ["git/world/served/status"] = {} })
```

## Notes

- A save changes nothing a query can see, so this mod asks on a timer. The timer runs only while a carrier exists, and the two checks are run conditions on it.
- Root answers only a world it started. A carrier anywhere else asks every 10 s and is never answered.
- Only replies on this mod's own requests are read. `git/world/head` asks root for status too, on its own entity.
- Content is core's concern. `mtime` only says that a file was written again. Core reads the file and sends nothing when its content is what was last sent.
- Merging a held version into an edit is `git/world/served/merge`'s job.
- Suites run headless. `test_status` runs a client world on a scratch repository, with root answering through real git and sharing a signed-in identity. `test_status_watch` stands in for root with scripted scans, and covers both checks.
