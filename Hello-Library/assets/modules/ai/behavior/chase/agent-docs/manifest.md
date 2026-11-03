---
depends_on: [ai/agent, ai/nav]
conflicts_with: []
exposes: [ai/behavior/chase, ai/behavior/chase/option, ai/behavior/chase/state]
---

# ai/behavior/chase

Runs at what the agent has seen. It keeps an option linked to the agent and scores it from `ai/agent/memory`'s `seen`. There is no "lost it": what it saw grows stale, the score falls, and the agent's other options take over. Server only.

## Components

- `ai/behavior/chase = { ... }`, on an agent. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `speed` | metres per second, written to `ai/steering` while chosen | 5.2 |
  | `base_score` | its score for something seen just now is this plus `fresh_weight` | 0.9 |
  | `fresh_weight` | what freshness adds to the score | 0.1 |
  | `fresh_for` | seconds a sighting is worth chasing | 3 |
  | `distance_weight` | how much a metre of distance counts against freshness | 0.02 |
  | `switch_margin` | how much better another target must be | 0.25 |
  | `repath_distance` | metres a target must move before it asks again | 2 |
  | `give_up_for` | seconds it scores nothing after finding no way | 3 |

- `ai/behavior/chase/option`: marks its option entity, which also has `ai/agent/option` and a `Name`.
- `ai/behavior/chase/state = { target = <entity>, at = { x, y, z }, gave_up_until }`: on the option entity.

It writes its own key, `chase`, in `ai/nav/request`, while chosen.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/behavior/chase/option` | Spawns its option once the agent exists |
| First | `ai/behavior/chase/removed` | When it is removed from an agent that stays, its option and key go |
| Update | `ai/behavior/chase/score` | At each thought, pick a target, score it, keep the state |
| Update | `ai/behavior/chase/act` | Chosen, ask for the way to where its target was last seen; write its speed |
| Update | `ai/behavior/chase/exit` | No longer chosen, remove its key |
| Update | `ai/behavior/chase/give_up` | Blocked or no way there, score nothing for `give_up_for`, so it stops being chosen |

## Use

```lua
commands:entity(agent):patch({ ["ai/behavior/chase"] = { speed = 4, fresh_for = 5 } })
```

## Notes

- Having caught up is no reason to ask: `ai/steering` has stood it still.
- It goes to where its target was last seen until `fresh_for` runs out, with no hand-off to `ai/behavior/investigate`, which only works over sounds.
- The option outlives the mod's reloads, as what it knows lives there, and goes with the agent by its link.
