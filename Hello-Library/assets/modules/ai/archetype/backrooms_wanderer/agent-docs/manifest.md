---
depends_on: [ai/agent, ai/nav, ai/steering, ai/perception, ai/behavior/chase, ai/behavior/investigate, ai/behavior/patrol]
conflicts_with: []
exposes: [ai/archetype/backrooms_wanderer]
---

# ai/archetype/backrooms_wanderer

A slow wanderer that goes to look at noises and chases what it can see. Put on a body, it makes an agent of it. It is entirely configuration: its `base` is `ai/agent`, and it declares navigation, steering, perception and its behaviours with how this creature wants each. Server only.

## Components

- `ai/archetype/backrooms_wanderer = {}`, on a body. It has no fields of its own.

It patches these onto the body:

| Component | Values |
|-----------|--------|
| `ai/agent` | `think_hz` 6 |
| `ai/nav` | `capabilities = { walk = true }` |
| `ai/steering` | `speed` 1.8, `arrive_radius` 0.9, `separation_radius` 1.6, `turn_speed` 6 |
| `ai/perception` | `vision_range` 20, `vision_fov_deg` 110, `awareness_range` 3, `eye_height` 1.1, `hearing_range` 26 |
| `ai/behavior/chase` | `speed` 5.2, `repath_distance` 2 |
| `ai/behavior/investigate` | `speed` 3.4, `look_time` 2.5 |
| `ai/behavior/patrol` | `speed` 1.8, `radius` 14, `pause_min` 1.5, `pause_max` 4 |

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/archetype/backrooms_wanderer/init` | On an added archetype, patches the values above |
| First | `ai/archetype/backrooms_wanderer/removed` | When it is removed from a body that stays, what it declared goes; `ai/agent` goes with it as its base |

## Use

```lua
commands:entity(body):patch({ ["ai/archetype/backrooms_wanderer"] = {} })
```

## Notes

- A reload patches its values again, so a value changed by hand on a wanderer goes back then.
- A player runs at 6 m/s, so a wanderer is outrun in a straight line, but never stops coming.
