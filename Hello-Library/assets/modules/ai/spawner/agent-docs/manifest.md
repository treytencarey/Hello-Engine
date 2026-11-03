---
depends_on: [animation, movement]
conflicts_with: []
exposes: [ai/spawner, ai/spawner/agent, ai/spawner/agents]
---

# ai/spawner

Makes plain bodies for a scene to populate itself with, and links each to itself. A body has the same capsule and body type a player's has on its own client, `animation` for its model and `movement` for how clients show it. It has no `player`. What a body becomes is for a subclass to say: `ai/archetype/<name>/spawner`, with this mod as its `base`. Server only.

## Components

- `ai/spawner = { ... }`, on any entity. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `count` | bodies to have | 1 |
  | `radius` | metres from the centre | 12 |
  | `center_x` | metres | 0 |
  | `center_z` | metres | 0 |
  | `y` | metres up they start | 1.5 |
  | `body_radius` | metres | 0.4 |
  | `body_half_height` | metres | 0.5 |
  | `model` | the `animation` model | absent, its default |

- `ai/spawner/agent = { entity = <its spawner> }`, on a body: a relationship with target `ai/spawner/agents`, `linked_spawn = true`, so bodies go with their spawner.
- `ai/spawner/agents`: a spawner's bodies, kept by the engine.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/spawner/spawn` | On a changed `ai/spawner`, makes bodies up to `count` |
| First | `ai/spawner/removed` | When it is removed from an entity that stays, its bodies go |

## Use

```lua
-- plain bodies: a subclass says what they become
commands:spawn({ ["ai/spawner"] = { count = 4, radius = 8 }, ["core/net/sync"] = false })
```

## Notes

- Raising `count` adds bodies. Lowering it takes none, as the bodies are in the world by then and may be doing anything.
- A body's place comes from its number, turning by the golden angle, so any first few are evenly spread and more fill the gaps.
- Body, collider and place are synced from the server together, as a body added after its collider never attaches. `movement` makes the copy kinematic on each client.
