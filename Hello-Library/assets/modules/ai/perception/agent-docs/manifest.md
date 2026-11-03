---
depends_on: [ai/agent, ai/noisemaker]
conflicts_with: []
exposes: [ai/perception, ai/perception/target]
---

# ai/perception

What an agent notices, written into its `ai/agent/memory`. It decides nothing. Vision looks at each thought and hearing happens as each sound does. Server only.

## Components

- `ai/perception = { ... }`, on each agent. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `vision_range` | metres | 18 |
  | `vision_fov_deg` | degrees of the whole cone | 100 |
  | `awareness_range` | metres within which the cone does not matter | 3 |
  | `eye_height` | metres from its origin up to its eyes | 1 |
  | `target_height` | metres from a target's origin up to where it looks | 0.3 |
  | `target_margin` | metres short of a target its look stops, so only something between counts | 0.7 |
  | `forget_seen_after` | seconds | 20 |
  | `hearing_range` | metres, for the loudest sound | 25 |
  | `forget_sound_after` | seconds | 20 |

- `ai/perception/target`: on what agents look for, added by whoever wants it seen. `player` adds it to every player. An entity that is both sees everything but itself.

It writes both lists of `ai/agent/memory`, and nothing else does: `seen = { { entity, at, seen_at }, ... }` and `sound = { { at, heard_at }, ... }`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Update | `ai/perception/see` | On a changed `ai/agent/tick`: what is in range, inside the cone and not behind anything is seen; what it no longer sees stays until `forget_seen_after` or its entity goes |

It observes `ai/noisemaker/sound`: a sound within `hearing_range` times its `loudness` is heard. Old sounds are dropped then, so a list may hold sounds past `forget_sound_after` until the next one arrives: a reader looks at `heard_at`.

## Use

```lua
commands:entity(agent):patch({ ["ai/perception"] = { vision_range = 30 } })
commands:entity(barrel):patch({ ["ai/perception/target"] = {} })
```

## Notes

- Two sounds landing in one frame both stay, as the observer writes through its row.
- A collider counts only from the physics step after it lands, so a wall arriving this frame hides nothing from a look this frame.
- Its look skips the agent's own body, so eyes inside the capsule see out.
