---
depends_on: [ai/agent, ai/nav]
conflicts_with: []
exposes: [ai/behavior/patrol, ai/behavior/patrol/option, ai/behavior/patrol/state]
---

# ai/behavior/patrol

Wanders around where the agent first patrolled from, pausing between legs. Its option's score is flat, low and never 0, so it is what an agent falls back on when nothing else is worth doing. Server only.

## Components

- `ai/behavior/patrol = { ... }`, on an agent. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `speed` | metres per second, written to `ai/steering` while chosen | 1.8 |
  | `base_score` | its score | 0.2 |
  | `radius` | metres from home it wanders | 14 |
  | `near_share` | the share of the radius a leg ends no nearer than | 0.35 |
  | `pause_min` | seconds it stands, at least | 1.5 |
  | `pause_max` | seconds it stands, at most | 4 |

- `ai/behavior/patrol/option`: marks its option entity, which also has `ai/agent/option` and a `Name`.
- `ai/behavior/patrol/state = { home, resume_at, path_before }`: on the option entity. `resume_at` is when it walks on, while it stands, and `path_before` is the `ai/nav/path` it had when it asked.

It writes its own key, `patrol`, in `ai/nav/request`, while chosen.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/behavior/patrol/option` | Spawns its option once the agent exists |
| First | `ai/behavior/patrol/removed` | When it is removed from an agent that stays, its option and key go |
| Update | `ai/behavior/patrol/score` | Its score follows the field |
| Update | `ai/behavior/patrol/act` | Chosen, at each thought: walk a leg, stand a while, walk another; a leg with no way there is picked again |
| Update | `ai/behavior/patrol/exit` | No longer chosen, remove its key |

## Use

```lua
commands:entity(agent):patch({ ["ai/behavior/patrol"] = { radius = 6 } })
```

## Notes

- What `ai/steering` says counts only for a path answered since it asked, as a stale `"arrived"` is about the last place it went.
- The option outlives the mod's reloads, as its home lives there, and goes with the agent by its link.
