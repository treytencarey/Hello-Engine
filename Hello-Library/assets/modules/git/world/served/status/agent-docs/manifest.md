---
depends_on: [vault/git, core/process, git/merge/notice, notification, git/world/head]
conflicts_with: []
exposes: [git/world/served/status, git/world/served/status/scan]
---

# git/world/served/status

The player's edits to a world's checkout, read from git. Every file `git status` reports under the checkout's `assets/` becomes core's `core/library/edit`, which core uploads. This world runs no git: it asks root, which reads the checkout of a world it started (`vault/git/status`). A sub-mod of `git/world/served`, which adds and removes it.

Git answers the branch-switch case by itself. A `git checkout` rewrites many files, but afterwards they match HEAD, so no scan names them. Only the player's own work is dirty.

## Components

- `git/world/served/status = {}`: on the entity that watches. `git/world/served` adds it to its own carrier while the world's tree is the player's checkout.
- `git/world/served/status/scan { asked_at, head, upstream, ops }`, on the carrier, added with the first request:
  - `asked_at`: this world's clock, in seconds, when the last request was asked;
  - `head`: the checkout's commit at the last scan;
  - `upstream = { ahead, behind }`: the last scan's, copied from root's reply (`vault/git/status/reply.upstream`): how many commits the checkout's branch is ahead of its upstream and behind it. Absent when the last scan named none: no upstream, or a detached HEAD;
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

## A push

A push changes nothing a query of the world's head can see: the world still states its commit, and `git/world/head`'s client compares only when that commit moves. A push does lower the branch's `ahead`, so when a scan that succeeded names an upstream whose `ahead` is lower than the last scan's, this mod puts `git/world/head/recheck = {}` on the world's `git/world/head` entity, the one the world's server synced to this player, and that mod's client compares the checkout against the world's commit again: within one scan of the push, about 2 s. Nothing is marked on the first scan, nor when the last scan named no upstream, nor when `ahead` rose or stayed.

## The provider of the facts

The carrier also says this mod states its tree's edit facts, with core's `core/library/edit/provider { ref, paused?, merges? }`, `ref` being the world's scope (its `core/world/status.scope_key`). Each scan that succeeds sets it:

- the checkout on the commit the world states (`git/world/head.sha`) and on the world's branch (the scope's last `:` part): `{ ref, merges = true }`. Core then takes a file git does not list as not the player's, so the world's version of it lands, and asks `git/world/served/merge` about a file both sides changed;
- the checkout on another branch: `{ ref, paused = true }`. Nothing goes up and nothing lands until the checkout is back, as before the home re-roots after a branch switch;
- the checkout on another commit of the world's branch: no marker, so core's own fallback compares the tree by hash and time.

Before the first scan's answer there is no marker either, and core's fallback runs for those frames. In both cases a world that declares `git/ignore` still keeps what git ignores off the wire.

Git's answer is exact where core's own would guess: the shared commit is the base, each side's changes are its own `git status`, and no file time decides a path only one side changed. It is cheap too: a status of a 189 MB tree took about 0.12 s, where hashing it in Lua takes about 8 s. The pause exists because, until the home re-roots after a branch switch, the old world is still rooted at this checkout, and a version landing then would land in the other branch's files.

Signed out (root's `core/player/identity` without `site_user_id`), it says `paused = true` on the identity's edge. The marker goes with this mod. Each fact also carries `mtime`, the file's time in milliseconds as root read it, and `both = true` when the world changed the same file too: when it is in `git/world/head/dirty`, the world's live edits, which the server sends to a writer's own player. The facts restate `both` when that list changes.

## A refused edit

When this world refuses an edit that was not stale, core marks the path's edit `core/library/edit/refused = {}` and takes the mark off when the path goes up again. On the mark's `added` edge, for an edit under a status carrier, this mod prints "this world refused your edit of <path>" and spawns a `git/merge/notice` with the title `REFUSED`, the text "This world refused your edit of <path>. It stays in your copy only.", `notification = { timeout = 20 }` and `["core/script/owner"] = false`. A stale refusal is held and merged instead, and shows nothing here.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `git/world/served/status` | While a carrier exists, outside both-mode and while signed in: asks root every 2 s, one request at a time. A request root has not answered in 10 s is closed and asked again |
| Update | `git/world/served/status` | On a status reply under a carrier: restates the edits and the scan, sets the provider marker, marks the world's head `git/world/head/recheck` when the upstream's `ahead` dropped, and closes the request. Runs on the reply's edge |
| Update | `git/world/served/status` | On a changed root `core/player/identity`, signed out: the provider marker paused |
| Update | `git/world/served/status` | On an added, changed or removed `git/world/head/dirty`: each fact under a carrier restates `both` |
| Update | `git/world/served/status` | On `added core/library/edit/refused`, for an edit under a carrier: the `REFUSED` notice |
| Update | none | When `git/world/served/status` is taken off an entity that stays: despawns its edits and its open request, and takes the provider marker off |

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
- Suites run headless. `test_status` runs a client world on a scratch repository, with root answering through real git and sharing a signed-in identity. `test_status_watch` stands in for root with scripted scans, and covers both checks and when a scan marks the world's head to compare again.
