---
depends_on: [vault/git, core/library]
conflicts_with: []
exposes: [git/world/served/merge, git/world/served/merge/result]
---

# git/world/served/merge

Git's three-way text merge, as core's resolver for a file both the player and the world changed. When the tree's provider of edit facts says it merges (`core/library/edit/provider { merges = true }`, which `git/world/served/status` sets), core asks for each such file with `core/library/merge { path, mine, theirs }`, `theirs` being the world's version, kept in the held store. This mod asks root to merge it into the player's checkout, and root writes only a merge with no conflict. Core keeps the newer copy whenever this mod says no. No conflict markers are ever written: a file holding them would count as the player's newer copy and go up into the world. World mods never touch files: core's watcher sees the file change. A sub-mod of `git/world/served`, which adds and removes it.

## Components

- `git/world/served/merge = {}`: the carrier, on the entity of a world whose content library is the player's checkout (`git/world/served` adds it beside `git/world/served/status`).
- `git/world/served/merge/result = { key, hash, asked_at, status }`: one per file asked, a child of the carrier, while core's request for it is open.
  - `key`: the file, asset relative;
  - `hash`: the world's version being merged (core's `theirs`);
  - `asked_at`: `Time`'s elapsed seconds when root was asked. Root's request is closed once answered, or after 30 s with no answer;
  - `status`: `"clean"`, `"conflict"` or `"failed"`, absent while root's request is open.
- Root's requests are children of the carrier, `{ ["vault/git/merge"] = {}, ["vault/git"] = { path = "assets/" .. path, hash = theirs, apply = "clean" }, Request = {} }`.
- The answer goes on core's request: `core/library/merge/reply = { status = "merged" | "no" }`, `"merged"` for `clean` (root wrote the merge, or left the player's copy, or took the world's), `"no"` for a conflict, a failure, a refusal or no answer.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `git/world/served/merge` | On an added `core/library/merge`: asks root, and spawns the file's record |
| Update | `git/world/served/merge` | On a merge reply under a carrier, or a record 30 s old: sets the record's `status`, answers core's request, and closes root's. Runs on the reply's edge, and when a record still waiting reaches 30 s |
| Update | `git/world/served/merge` | On a removed `core/library/merge`: that file's record goes, and root's request if open |
| Update | none | When `git/world/served/merge` is taken off an entity that stays: closes its open requests. Its records go with it as its sub-components |

## Use

```lua
-- normally put there by git/world/served
commands:entity(e):insert({ ["git/world/served/merge"] = {} })
```

## Notes

- Root merges over the working copy, its `HEAD` version and the world's: the base is the shared commit only when the checkout is on the commit the world states, which is when `git/world/served/status` says it merges.
- A binary both sides changed is a failure to git, so core keeps the newer copy and says so.
- A reply crosses from root's VM, and a mirrored edge arrives as surely as a local one, so each reply is read on its own edge; only the 30 s limit runs on the clock.
- `test_merge` runs headless, standing in for core's requests and root's answers.
