---
depends_on: [ai/agent, ai/nav]
conflicts_with: []
exposes: [ai/behavior/investigate, ai/behavior/investigate/option, ai/behavior/investigate/state]
---

# ai/behavior/investigate

Walks to where something was heard and looks around. It keeps an option linked to the agent and scores it from `ai/agent/memory`'s `sound`. Once it has looked, or found no way there, that sound and older ones are done with, and the score falls. Server only.

## Components

- `ai/behavior/investigate = { ... }`, on an agent. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `speed` | metres per second, written to `ai/steering` while chosen | 3.4 |
  | `base_score` | its score for a sound as it goes stale | 0.35 |
  | `fresh_weight` | what freshness adds to the score | 0.45 |
  | `fresh_for` | seconds a sound is worth walking to | 20 |
  | `distance_weight` | how much a metre of distance counts against freshness | 0.02 |
  | `switch_margin` | how much better another sound must be | 0.25 |
  | `look_time` | seconds it looks around when it gets there | 2.5 |

- `ai/behavior/investigate/option`: marks its option entity, which also has `ai/agent/option` and a `Name`.
- `ai/behavior/investigate/state = { at, heard_at, done_at, look_until, path_before }`: on the option entity. `at` and `heard_at` are the sound it is going to, `done_at` is when the newest sound it is done with was heard, and `path_before` is the `ai/nav/path` it had when it asked.

It writes its own key, `investigate`, in `ai/nav/request`, while chosen.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/behavior/investigate/option` | Spawns its option once the agent exists |
| First | `ai/behavior/investigate/removed` | When it is removed from an agent that stays, its option and key go |
| Update | `ai/behavior/investigate/score` | At each thought, pick a sound, score it, keep the state |
| Update | `ai/behavior/investigate/act` | Chosen, at each thought: ask for the way, look around once there, be done with it then or when there is no way there |
| Update | `ai/behavior/investigate/exit` | No longer chosen, remove its key |

## Use

```lua
commands:entity(agent):patch({ ["ai/behavior/investigate"] = { look_time = 5 } })
```

## Notes

- What `ai/steering` says counts only for a path answered since it asked, as a stale `"arrived"` is about the last place it went.
- The option outlives the mod's reloads, as what it knows lives there, and goes with the agent by its link.
