---
depends_on: [core/library/filter, vault/git]
conflicts_with: []
exposes: [git/ignore]
---

# git/ignore

What git ignores in a tree is left out of it: never served, listed or sent. Git decides, through root: this mod parses nothing. The filter belongs to the tree: this mod rides on the tree's own entity, and core asks it about that tree's paths alone.

## Components

- `git/ignore = {}`: on the entity of the tree it filters, put there by `git/world/served` with its sub-mods and removed with them. A world never declares it itself.
  - On a server: the asset endpoint serving the world's tree (`core/asset { mode = "server" }`, not a `read_only` library front).
  - On a client: the world's own content library, the `core/library` whose `ref` is the world's scope, while it is the player's checkout (`edits = true`).
  - Its own base is core's `core/library/filter`, so it brings that onto the same entity, and core asks this mod about each path of that tree before it serves, lists or sends it. Core never asks it about another tree in the VM.
- For each `core/library/filter/ask { paths }` under a carrier, the mod asks root `{ ["vault/git/check_ignore"] = { paths }, ["vault/git"] = {}, Request = {} }`, children of the ask:
  - one request per chunk of at most 100 paths, 12000 characters in all;
  - root runs `git check-ignore --no-index` in the tree it started the world on.
- Once every request is answered, the mod answers the ask: `core/library/filter/ask/reply { out }`, the union of what git ignores.
  - When any request was refused or failed, `out` is every path of the ask, said once in the log, so nothing goes on a question git didn't answer.
  - An ask with no paths is answered at once with none.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `git/ignore` | On an added ask under a carrier: its paths go to root in chunks |
| Update | `git/ignore` | On a root reply: when every request under its ask is answered, answers the ask. Runs on the reply's edge |

## Use

```lua
-- in a world's world/boot halves: git/world/served brings git/ignore onto the tree's entity
return { base = "git/world/served" }
```

## Notes

- Git answers for paths that don't exist: a Gateway whose clone has no `assets/config/` still says `assets/config/x.json` is ignored.
- Nested `.gitignore` files, `!` and the global excludes are git's own. `--no-index` makes a tracked file that a rule matches count as ignored.
- Suite: `tests/test_ignore.lua` runs a client world root started on a scratch repository and asks with real git. It checks:
  - a `config/` file with no `config/` folder, and a `.blend1`, are out;
  - a nested `.gitignore` and its `!` hold;
  - a path git doesn't ignore is in;
  - a refused ask puts every path out;
  - an ask under a carrier without this mod gets no answer.
